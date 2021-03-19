
--register craftitem
--TODO: come back to finish this



minetest.register_craftitem("plane:plane", {
    description = "Plane",
    inventory_image = "plane_item.png",
    on_place = function(itemstack, placer, pointed_thing)
        minetest.add_entity(pointed_thing.above, "plane:plane_ent")
        return itemstack:take_item()
    end,
    liquids_pointable = true,
})




---helper functions

local function is_water(pos)
	local nn = minetest.get_node(pos).name
	return minetest.get_item_group(nn, "water") ~= 0
end


local function get_velocity(v, yaw, y)
	local x = -math.sin(yaw) * v
	local z =  math.cos(yaw) * v
	return {x = x, y = y, z = z}
end

--get_velocity magnitude
local function get_v(v)
	return math.sqrt(v.x ^ 2 + v.z ^ 2)
end



--
-- plane entity
--

local plane = {
	initial_properties = {
		physical = true,
		-- Warning: Do not change the position of the collisionbox top surface,
		-- lowering it causes the boat to fall through the world if underwater
		collisionbox = {-0.5, -0.35, -0.5, 0.5, 0.3, 0.5},
		visual = "mesh",
        visual_size = {x=5,y=5,z=5},
		mesh = "plane.b3d",
		textures = {"plane_rivits.png","plane_window.png","plane_propeller.png","plane_landing.png"},
	},

	driver = nil,
	v = 0,
	vel_y = 0,
	last_v = 0,
	removed = false,
	lift = 0.0,
	
}


function plane.on_rightclick(self, clicker)
	if not clicker or not clicker:is_player() then
		return
	end
	local name = clicker:get_player_name()

	if self.driver and name == self.driver then
        --detach player
		self.driver = nil
		self.auto = false
		clicker:set_detach()
		player_api.player_attached[name] = false
		player_api.set_animation(clicker, "stand" , 30)
		local pos = clicker:get_pos()
		pos = {x = pos.x, y = pos.y + 0.2, z = pos.z}
		minetest.after(0.1, function()
			clicker:set_pos(pos)
		end)
	elseif not self.driver then
		local attach = clicker:get_attach()
		if attach and attach:get_luaentity() then
			local luaentity = attach:get_luaentity()
			if luaentity.driver then
				luaentity.driver = nil
			end
			clicker:set_detach()
		end
		self.driver = name
		clicker:set_attach(self.object, "",
			{x = 0.5, y = 1, z = -3}, {x = 0, y = 0, z = 0})
		clicker: set_properties({visual_size = {x=1, y=1},}) 
		player_api.player_attached[name] = true
		minetest.after(0.2, function()
			player_api.set_animation(clicker, "sit" , 30)
		end)
		clicker:set_look_horizontal(self.object:get_yaw())
	end
end


-- If driver leaves server while driving plane
function plane.on_detach_child(self, child)
	self.driver = nil
	self.auto = false
end


function plane.on_activate(self, staticdata, dtime_s)
	self.object:set_armor_groups({immortal = 1})
	if staticdata then
		self.v = tonumber(staticdata)
	end
	self.last_v = self.v
end


function plane.get_staticdata(self)
	return tostring(self.v)
end


function plane.on_punch(self, puncher)
	if not puncher or not puncher:is_player() or self.removed then
		return
	end

	local name = puncher:get_player_name()
	if self.driver and name == self.driver then
		self.driver = nil
		puncher:set_detach()
		player_api.player_attached[name] = false
	end
	if not self.driver then
		self.removed = true
		local inv = puncher:get_inventory()
		if not minetest.is_creative_enabled(name)
				or not inv:contains_item("main", "plane:plane") then
			local leftover = inv:add_item("main", "plane:plane")
			-- if no room in inventory add a replacement plane to the world
			if not leftover:is_empty() then
				minetest.add_item(self.object:get_pos(), leftover)
			end
		end
		-- delay remove to ensure player is detached
		minetest.after(0.1, function()
			self.object:remove()
		end)
	end
end


function plane.on_step(self, dtime)


    

    self.v = get_v(self.object:get_velocity()) * math.sign(self.v)
	self.vel_y = self.object:get_velocity().y 
	
	if self.driver then
		local driver_objref = minetest.get_player_by_name(self.driver)
		if driver_objref then
			local ctrl = driver_objref:get_player_control()

			if ctrl.down then
				-- decelerate
				self.v = self.v - dtime * 3.0
				
			elseif ctrl.up or self.auto then
				--accellerate
				self.v = self.v + dtime * 3.0
			end
			if ctrl.left then
				if self.v < -0.001 then
					self.object:set_yaw(self.object:get_yaw() - dtime * 0.9)
				else
					self.object:set_yaw(self.object:get_yaw() + dtime * 0.9)
				end
			elseif ctrl.right then
				if self.v < -0.001 then
					self.object:set_yaw(self.object:get_yaw() + dtime * 0.9)
				else
					self.object:set_yaw(self.object:get_yaw() - dtime * 0.9)
				end
			end
			if ctrl.jump then
				self.lift = self.lift + self.v * dtime * 0.1
			elseif ctrl.sneak then
				self.lift = self.lift - dtime * 0.2
			end
			if self.v < .001 then 
				self.lift = 0
			end
			if self.lift > 1 then
				self.lift = 1
			end
		end
	end
	local velo = self.object:get_velocity()
	--make sure its stopped
	if not self.driver and
			self.v == 0 and velo.x == 0 and velo.y == 0 and velo.z == 0 then
		self.object:set_pos(self.object:get_pos())
		return
	end


	local p = self.object:get_pos()
	p.y = p.y - 0.5 --?
	local new_velo
	local new_acce = {x = 0, y = 0, z = 0}
	if not is_water(p) then

		-- We need to preserve velocity sign to properly apply drag force
		-- while moving backward
		local drag = dtime * math.sign(self.v) * (0.01 + 0.045 * self.v * self.v)
		-- If drag is larger than velocity, then stop horizontal movement
		if math.abs(self.v) <= math.abs(drag) then
			self.v = 0
		else
			self.v = self.v - drag
		end

		local nodedef = minetest.registered_nodes[minetest.get_node(p).name]
		-- if not nodedef or not nodedef.walkable then --its air-like
		-- 			end
		new_acce = {x = 0, y = -9.81, z = 0}
		new_velo = get_velocity(self.v, self.object:get_yaw(),	self.object:get_velocity().y / 2 + self.lift )

		self.object:set_pos(self.object:get_pos())
	
	else

		--apply drag
		-- We need to preserve velocity sign to properly apply drag force
		-- while moving backward
		local drag = dtime * math.sign(self.v) * (0.01 + 0.0996 * self.v * self.v)
		-- If drag is larger than velocity, then stop horizontal movement
		if math.abs(self.v) <= math.abs(drag) then
			self.v = 0
		else
			self.v = self.v - drag
		end



		p.y = p.y + 1



		if is_water(p) then

			



			local y = self.object:get_velocity().y
			if y > 5 then
				y = 5
			elseif y < 0 then
				new_acce = {x = 0, y = 15, z = 0}
			else
				new_acce = {x = 0, y = 5, z = 0}
			end
			self.v = self.v
			new_velo = get_velocity(self.v, self.object:get_yaw(), y)
			self.object:set_pos(self.object:get_pos())
		else
			new_acce = {x = 0, y = 0, z = 0}
			if math.abs(self.object:get_velocity().y) < 1 then
				local pos = self.object:get_pos()
				pos.y = math.floor(pos.y) + 0.5
				self.object:set_pos(pos)
				new_velo = get_velocity(self.v, self.object:get_yaw(), 0)
			else
				new_velo = get_velocity(self.v, self.object:get_yaw(),
					self.object:get_velocity().y)
				self.object:set_pos(self.object:get_pos())
			end
		end
	end
	self.object:set_velocity(new_velo)
	self.object:set_acceleration(new_acce)
end


minetest.register_entity("plane:plane_ent", plane)
