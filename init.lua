--Basic protect by rnd, 2016
local protector = {};
protector.radius = 20; -- 20x20x20 area

protector.cache = {};

local old_is_protected = minetest.is_protected
function minetest.is_protected(pos, digger)
	local r = protector.radius;
	local p = {x=math.floor((pos.x)/r)*r,y=math.floor((pos.y)/r)*r,z=math.floor((pos.z)/r)*r}
	
	if not protector.cache[digger] then -- cache current check for faster future lookups
		protector.cache[digger] = p;
	else
		local p0 = protector.cache[digger];
		if (p0.x==p.x and p0.y==p.y and p0.z==p.z) then -- already checked, just lookup
			return protector.cache[digger].is_protected 
		else 
			protector.cache[digger] = p; -- refresh cache
		end
	end
	
	if minetest.get_node(p).name == "basic_protect:protector" then 
		local meta = minetest.get_meta(p);
		local owner = meta:get_string("owner");
		if digger~=owner then 
			minetest.chat_send_player(digger, "area owned by " .. owner);
			protector.cache[digger].is_protected = true;
			return true 
		end
	end
	protector.cache[digger].is_protected = old_is_protected(pos, digger);
	return  protector.cache[digger].is_protected;
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
		local p = {x=math.floor((pos.x)/r)*r,y=math.floor((pos.y)/r)*r,z=math.floor((pos.z)/r)*r}
		if minetest.get_node(p).name == "basic_protect:protector" then
			minetest.chat_send_player(name,"area already protected at " .. minetest.pos_to_string(p));
			return nil
		end
		minetest.set_node(p, {name = "basic_protect:protector"});
		local meta = minetest.get_meta(p);meta:set_string("owner",name);
		minetest.chat_send_player(name, "#protector: protected new area (" .. p.x .. "," .. p.y .. "," .. p.z .. ") + " .. protector.radius-1 .. " nodes");
		meta:set_string("infotext", "property of " .. name);
		protector.cache = {}; -- reset cache
		itemstack:take_item(); return itemstack
	end,
	on_punch = function(pos, node, puncher, pointed_thing) 
		local meta = minetest.get_meta(pos);local owner = meta:get_string("owner");
		if owner == puncher:get_player_name() then
			minetest.add_entity({x=pos.x-0.5+protector.radius/2,y=pos.y-0.5+protector.radius/2,z=pos.z-0.5+protector.radius/2}, "basic_protect:display")
		end
	end
});


minetest.register_entity("basic_protect:display", {
	physical = false,
	collisionbox = {0, 0, 0, 0, 0, 0},
	visual = "wielditem",
	-- wielditem seems to be scaled to 1.5 times original node size
	visual_size = {x = 1.29*protector.radius/21, y = 1.29*protector.radius/21},
	textures = {"protector:display_node"},
	timer = 0,

	on_activate = function(self, staticdata)
		self.timer = 0;
		-- Xanadu server only
		if mobs and mobs.entity and mobs.entity == false then
			self.object:remove()
		end
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