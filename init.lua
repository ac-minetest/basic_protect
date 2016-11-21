--Basic protect by rnd, 2016

-- features: 
-- super fast protection checks with caching
-- no slowdowns due to large protection radius or larger protector counts
-- shared protection: just write players names in list, separated by spaces

local protector = {};
protector.radius = 20; -- by default protects 20x10x20 chunk, protector placed in center at positions that are multiplier of 20,20 (x,y,z)



protector.cache = {};
local round = math.floor;
local protector_position = function(pos) 
	local r = protector.radius;
	local ry = 2*r;
	return {x=round(pos.x/r+0.5)*r,y=round(pos.y/ry+0.5)*ry,z=round(pos.z/r+0.5)*r};
end


local function check_protector (p, digger) -- is it protected for digger at this protector?

	local meta = minetest.get_meta(p);
	local owner = meta:get_string("owner");
	if digger~=owner then 
		--check for shared protection
		local shares = meta:get_string("shares");
		for word in string.gmatch(shares, "%S+") do
			if digger == word then
				return false;
			end
		end
		minetest.chat_send_player(digger,"#PROTECTOR: this area is owned by " .. owner);
		return true;
	else
		return false;
	end

end

--check if position is protected
local old_is_protected = minetest.is_protected
function minetest.is_protected(pos, digger)
	local p = protector_position(pos);
	local is_protected = true;
	
	if not protector.cache[digger] then -- cache current check for faster future lookups
		
		if minetest.get_node(p).name == "basic_protect:protector" then 
			is_protected = check_protector (p, digger)
		else
			is_protected = old_is_protected(pos, digger);
		end
		protector.cache[digger] = {pos = {x=p.x,y=p.y,z=p.z}, is_protected = is_protected};
	
	else -- look up cached result
	
		local p0 = protector.cache[digger].pos;
		if (p0.x==p.x and p0.y==p.y and p0.z==p.z) then -- already checked, just lookup
			is_protected = protector.cache[digger].is_protected;
		else -- another block, we need to check again
			if minetest.get_node(p).name == "basic_protect:protector" then 
				is_protected = check_protector (p, digger)
			else
				is_protected = old_is_protected(pos, digger);
			end
			protector.cache[digger] = {pos = {x=p.x,y=p.y,z=p.z}, is_protected = is_protected}; -- refresh cache;
		end
	end

	if is_protected then -- DEFINE action for trespassers here
		
		--teleport offender
		local tpos = protector.cache[digger].tpos;
		if not tpos then 
			local meta = minetest.get_meta(p);
			local xt = meta:get_int("xt"); local yt = meta:get_int("yt"); local zt = meta:get_int("zt");
			tpos = {x=xt,y=yt,z=zt};
		end
		
		local player = minetest.get_player_by_name(digger);
		if player and (tpos.x~=p.x or tpos.y~=p.y or tpos.z~=p.z) then
			player:setpos(tpos);
		end
	end
	
	return is_protected;
end

local update_formspec = function(pos)
	local meta = minetest.get_meta(pos);
	local shares = meta:get_string("shares");
	local tpos = meta:get_string("tpos");
	if tpos == "" then 
		tpos = "0 0 0" 
	end
	meta:set_string("formspec",
					"size[5,5]"..
					"field[0.25,1;5,1;shares;Write in names of players you want to add in protection ;".. shares .."]"..
					"field[0.25,2;5,1;tpos;where to teleport intruders - default 0 0 0 ;".. tpos .."]"..
					"button_exit[4,4.5;1,1;OK;OK]"
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
		local p = protector_position(pos);
		if minetest.get_node(p).name == "basic_protect:protector" then
			local meta = minetest.get_meta(p);
			minetest.chat_send_player(name,"#PROTECTOR: protector already at " .. minetest.pos_to_string(p) .. ", owned by " .. meta:get_string("owner"));
			return nil
		end
		pos.y=pos.y+1;
		minetest.set_node(pos, {name = "air"});
		minetest.set_node(p, {name = "basic_protect:protector"});
		local meta = minetest.get_meta(p);meta:set_string("owner",name);
		minetest.chat_send_player(name, "#PROTECTOR: protected new area, protector placed at(" .. p.x .. "," .. p.y .. "," .. p.z .. "), area size " .. protector.radius "x" .. protector.radius .. " , 2x more in vertical direction");
		meta:set_string("infotext", "property of " .. name);
		minetest.add_entity({x=p.x,y=p.y,z=p.z}, "basic_protect:display")
		local shares = "";
		update_formspec(p);
		protector.cache = {}; -- reset cache
		itemstack:take_item(); return itemstack
	end,
	
	on_punch = function(pos, node, puncher, pointed_thing) -- for unknown reason texture is unknown
		local meta = minetest.get_meta(pos);
		local owner = meta:get_string("owner");
		local name = puncher:get_player_name();
		if owner == name or minetest.is_protected(pos, name) then
			minetest.add_entity({x=pos.x,y=pos.y,z=pos.z}, "basic_protect:display")
		end
	end,
	
    on_receive_fields = function(pos, formname, fields, player)
		local meta = minetest.get_meta(pos);
		local owner = meta:get_string("owner");
		
		if owner~= player:get_player_name() then return end
		
		if fields.OK then
			if fields.shares then
				meta:set_string("shares",fields.shares);
				protector.cache = {}
			end
			
			if fields.tpos then
				meta:set_string("tpos", fields.tpos)
			    local words = {}
				for word in string.gmatch(fields.tpos, "%S+") do
					words[#words+1] = tonumber(word) or 0
				end
				
				local xt = (words[1] or 0); if math.abs(xt)>protector.radius then xt = 0 end
				local yt = (words[2] or 0); if math.abs(yt)>protector.radius then yt = 0 end
				local zt = (words[3] or 0); if math.abs(zt)>protector.radius then zt = 0 end
				
				meta:set_int("xt", xt+pos.x)
				meta:set_int("yt", yt+pos.y)
				meta:set_int("zt", zt+pos.z)
			end
			
			update_formspec(pos)
		end
    end,
	
	can_dig = function(pos, player)
		local meta = minetest.get_meta(pos);
		local owner = meta:get_string("owner");
		local name = player:get_player_name();
		local privs = minetest.get_player_privs(name)
		if owner~= player:get_player_name() and not privs.privs then return false end
		return true
	end
});


-- entities used to display area when protector is punched

local x = protector.radius/2;
local y = 2*x;
minetest.register_node("basic_protect:display_node", {
	tiles = {"area_display.png"},
	use_texture_alpha = true,
	walkable = false,
	drawtype = "nodebox",
	node_box = {
		type = "fixed",
		fixed = {
			
			{-(x+.55), -(y+.55), -(x+.55), -(x+.45), (y-1+.55), (x-1+.55)},-- sides
			{-(x+.55), -(y+.55), (x-1+.45), (x-1+.55), (y-1+.55), (x-1+.55)},
			{(x-1+.45), -(y+.55), -(x+.55), (x-1+.55), (y-1+.55), (x-1+.55)},
			{-(x+.55), -(y+.55), -(x+.55), (x-1+.55), (y-1+.55), -(x+.45)},
			
			{-(x+.55), (y-1+.45), -(x+.55), (x-1+.55), (y-1+.55), (x-1+.55)},-- top
			
			{-(x+.55), -(y+.55), -(x+.55), (x-1+.55), -(y+.45), (x-1+.55)},-- bottom
			
			{-.55,-.55,-.55, .55,.55,.55},-- middle (surround protector)
		},
	},
	selection_box = {
		type = "regular",
	},
	paramtype = "light",
	groups = {dig_immediate = 3, not_in_creative_inventory = 1},
	drop = "",
})



minetest.register_entity("basic_protect:display", {
	physical = false,
	collisionbox = {0, 0, 0, 0, 0, 0},
	visual = "wielditem",
	visual_size = {x = 1.0 / 1.5, y = 1.0 / 1.5},
	textures = {"basic_protect:display_node"},
	timer = 0,
	
	on_step = function(self, dtime)

		self.timer = self.timer + dtime

		if self.timer > 30 then
			self.object:remove()
		end
	end,
})

-- CRAFTING

minetest.register_craft({
	output = "basic_protect:protector",
	recipe = {
		{"default:stone", "default:stone","default:stone"},
		{"default:stone", "default:steel_ingot","default:stone"},
		{"default:stone", "default:stone", "default:stone"}
	}
})