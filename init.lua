--Basic protect by rnd, 2016

-- features: 
-- super fast protection checks with caching
-- no slowdowns due to large protection radius or larger protector counts
-- shared protection: just write players names in list, separated by spaces

local protector = {};
protector.radius = 20; -- by default protects 20x10x20 chunk, protector placed in center at positions that are multiplier of 20,20 (x,y,z)



protector.cache = {};
local round = math.floor;

--check if position is protected
local old_is_protected = minetest.is_protected
function minetest.is_protected(pos, digger)
	local r = protector.radius;
	local p = {x=round(pos.x/r+0.5)*r,y=round(pos.y/r+0.5)*r,z=round(pos.z/r+0.5)*r}
	
	if not protector.cache[digger] then -- cache current check for faster future lookups
		protector.cache[digger] = p;
	else
		local p0 = protector.cache[digger];
		if (p0.x==p.x and p0.y==p.y and p0.z==p.z) then -- already checked, just lookup
			return protector.cache[digger].is_protected 
		else 
			--minetest.chat_send_all(digger .. " " .. minetest.pos_to_string(p0) .. " : "  .. minetest.pos_to_string(p))
			protector.cache[digger] = {x=p.x,y=p.y,z=p.z, is_protected = false}; -- refresh cache
		end
	end
	
	if minetest.get_node(p).name == "basic_protect:protector" then 
		local meta = minetest.get_meta(p);
		local owner = meta:get_string("owner");
		if digger~=owner then 
			--check for shared protection
			local shares = meta:get_string("shares");
			
			for word in string.gmatch(shares, "%S+") do
				if digger == word then
					protector.cache[digger].is_protected = false;
					return false
				end
			end
			
			minetest.chat_send_player(digger, "area owned by " .. owner);
			protector.cache[digger].is_protected = true;
			return true 
		end
	end
	protector.cache[digger].is_protected = old_is_protected(pos, digger);
	return protector.cache[digger].is_protected;
end

local update_formspec = function(pos)
	local meta = minetest.get_meta(pos);
	local shares = meta:get_string("shares");
	meta:set_string("formspec",
					"size[5,5]"..
					"field[0.25,1;5,1;shares;Write in names of players you want to add in protection ;".. shares .."]"..
					"button_exit[4,4;1,1;OK;OK]"
					);
end

minetest.register_node("basic_protect:protector", {
	description = "Protects a rectangle area of size " .. protector.radius,
	tiles = {"basic_protector.png"},
	groups = {oddly_breakable_by_hand=2},
	sounds = default.node_sound_wood_defaults(),
	on_place = function(itemstack, placer, pointed_thing)
	--after_place_node = function(pos, placer)
		local pos = pointed_thing.under;
		local name = placer:get_player_name();
		local r = protector.radius;
		local p = {x=round(pos.x/r+0.5)*r,y=round(pos.y/r+0.5)*r,z=round(pos.z/r+0.5)*r}
		if minetest.get_node(p).name == "basic_protect:protector" then
			minetest.chat_send_player(name,"area already protected at " .. minetest.pos_to_string(p));
			return nil
		end
		pos.y=pos.y+1;
		minetest.set_node(pos, {name = "air"});
		minetest.set_node(p, {name = "basic_protect:protector"});
		local meta = minetest.get_meta(p);meta:set_string("owner",name);
		minetest.chat_send_player(name, "#protector: protected new area (" .. p.x .. "," .. p.y .. "," .. p.z .. ") + radius " .. 0.5*protector.radius .. " around");
		meta:set_string("infotext", "property of " .. name);
		local shares = "";
		update_formspec(p);
		protector.cache = {}; -- reset cache
		itemstack:take_item(); return itemstack
	end,
	
	on_punch = function(pos, node, puncher, pointed_thing) -- for unknown reason texture is unknown
		 -- local meta = minetest.get_meta(pos);local owner = meta:get_string("owner");
		-- if owner == puncher:get_player_name() then
			-- minetest.add_entity({x=pos.x-0.5,y=pos.y-0.5,z=pos.z-0.5}, "basic_protect:display")
		-- end
	end,
	
    on_receive_fields = function(pos, formname, fields, player)
		local meta = minetest.get_meta(pos);
		if minetest.is_protected(pos, player:get_player_name()) then return end
		if fields.OK then
			if fields.shares then
				meta:set_string("shares",fields.shares);
				protector.cache = {};
			end
			update_formspec(pos);
		end
    end
});


minetest.register_entity("basic_protect:display", {
	physical = false,
	collisionbox = {0, 0, 0, 0, 0, 0},
	visual = "wielditem",
	-- wielditem seems to be scaled to 1.5 times original node size
	visual_size = {x = 1.29*protector.radius/21, y = 1.29*protector.radius/21},
	timer = 0,

	on_activate = function(self, staticdata)
		self.timer = 0;
		self.object:set_properties({textures={"area_display.png"}})
	end,

	on_step = function(self, dtime)

		self.timer = self.timer + dtime

		if self.timer > 20 then
			self.object:remove()
		end
	end,
})

minetest.register_craft({
	output = "basic_protect:protector",
	recipe = {
		{"default:stone", "default:stone","default:stone"},
		{"default:stone", "default:steel_ingot","default:stone"},
		{"default:stone", "default:stone", "default:stone"}
	}
})