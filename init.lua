--Basic protect by rnd, 2016

-- features: 
-- super fast protection checks with caching
-- no slowdowns due to large protection radius or larger protector counts
-- shared protection: just write players names in list, separated by spaces

--local protector = {};
basic_protect = {};
basic_protect.radius = 20; -- by default protects 20x10x20 chunk, protector placed in center at positions that are multiplier of 20,20 (x,y,z)




basic_protect.cache = {};
local round = math.floor;
local protector_position = function(pos) 
	local r = basic_protect.radius;
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
	
	if not basic_protect.cache[digger] then -- cache current check for faster future lookups
		
		if minetest.get_node(p).name == "basic_protect:protector" then 
			is_protected = check_protector (p, digger)
		else
			if minetest.get_node(p).name == "ignore" then 
				is_protected=true
			else
				is_protected = old_is_protected(pos, digger);
			end
		end
		basic_protect.cache[digger] = {pos = {x=p.x,y=p.y,z=p.z}, is_protected = is_protected};
	
	else -- look up cached result
	
		local p0 = basic_protect.cache[digger].pos;
		if (p0.x==p.x and p0.y==p.y and p0.z==p.z) then -- already checked, just lookup
			is_protected = basic_protect.cache[digger].is_protected;
		else -- another block, we need to check again
			
			local updatecache = true;
			if minetest.get_node(p).name == "basic_protect:protector" then 
				is_protected = check_protector (p, digger)
			else
				if minetest.get_node(p).name == "ignore" then  -- area not yet loaded
					is_protected=true; updatecache = false;
					minetest.chat_send_player(digger,"#PROTECTOR: chunk " .. p.x .. " " .. p.y .. " " .. p.z .. " is not yet completely loaded");
				else
					is_protected = old_is_protected(pos, digger);
				end
			end
			if updatecache then 
				basic_protect.cache[digger] = {pos = {x=p.x,y=p.y,z=p.z}, is_protected = is_protected}; -- refresh cache;
			end
		end
	end

	if is_protected then -- DEFINE action for trespassers here
		
		--teleport offender
		local tpos = basic_protect.cache[digger].tpos;
		if not tpos then 
			local meta = minetest.get_meta(p);
			local xt = meta:get_int("xt"); local yt = meta:get_int("yt"); local zt = meta:get_int("zt");
			tpos = {x=xt,y=yt,z=zt};
		end
		
		
		if (tpos.x~=p.x or tpos.y~=p.y or tpos.z~=p.z) then
			local player = minetest.get_player_by_name(digger);
			if minetest.get_node(p).name == "basic_protect:protector" then
				if player then player:setpos(tpos) end;
			end
		end
	end
	
	return is_protected;
end

local update_formspec = function(pos)
	local meta = minetest.get_meta(pos);
	local shares = meta:get_string("shares");
	local tpos = meta:get_string("tpos");
	--local subfree = meta:get_string("subfree");
	--if subfree == "" then subfree = "0 0 0 0 0 0" end
	
	if tpos == "" then 
		tpos = "0 0 0" 
	end
	meta:set_string("formspec",
					"size[5,5]"..
					"label[-0.25,-0.25; PROTECTOR]"..
					"field[0.25,1;5,1;shares;Write in names of players you want to add in protection ;".. shares .."]"..
					"field[0.25,2;5,1;tpos;where to teleport intruders - default 0 0 0 ;".. tpos .."]"..
					--"field[0.25,3;5,1;subfree;specify free to dig sub area x1 y1 z1 x2 y2 z2 - default 0 0 0 0 0 0;".. subfree .."]"..
					"button_exit[4,4.5;1,1;OK;OK]"
					);
end

basic_protect.protect_new = function(p,name)	
	local meta = minetest.get_meta(p);
	meta:set_string("owner",name);
	meta:set_int("xt",p.x);meta:set_int("yt",p.y);meta:set_int("zt",p.z);
	meta:set_string("tpos", "0 0 0");
	meta:set_string("timestamp", minetest.get_gametime());
	
	minetest.chat_send_player(name, "#PROTECTOR: protected new area, protector placed at(" .. p.x .. "," .. p.y .. "," .. p.z .. "), area size " .. basic_protect.radius .. "x" .. basic_protect.radius .. " , 2x more in vertical direction.  Say /unprotect to unclaim area.. ");
	meta:set_string("infotext", "property of " .. name);
	
	if #minetest.get_objects_inside_radius(p, 1)==0 then 
		minetest.add_entity({x=p.x,y=p.y,z=p.z}, "basic_protect:display")
	end
	local shares = "";
	update_formspec(p);
	basic_protect.cache = {}; -- reset cache
end

minetest.register_node("basic_protect:protector", {
	description = "Protects a rectangle area of size " .. basic_protect.radius,
	tiles = {"basic_protector.png","basic_protector_down.png","basic_protector_down.png","basic_protector_down.png","basic_protector_down.png","basic_protector_down.png"},
	--drawtype = "allfaces",
	--paramtype = "light",
	param1=1,
	groups = {oddly_breakable_by_hand=2},
	sounds = default.node_sound_wood_defaults(),
	on_place = function(itemstack, placer, pointed_thing)
	--after_place_node = function(pos, placer)
		local pos = pointed_thing.under;
		local name = placer:get_player_name();
		local r = basic_protect.radius;
		local p = protector_position(pos);
		if minetest.get_node(p).name == "basic_protect:protector" then
			local meta = minetest.get_meta(p);
			minetest.chat_send_player(name,"#PROTECTOR: protector already at " .. minetest.pos_to_string(p) .. ", owned by " .. meta:get_string("owner"));
			local obj = minetest.add_entity({x=p.x,y=p.y,z=p.z}, "basic_protect:display");
			local luaent = obj:get_luaentity();	luaent.timer = 5; -- just 5 seconds display
			return nil
		end
		
		minetest.set_node(p, {name = "basic_protect:protector"});
		basic_protect.protect_new(p,name);
		
		pos.y=pos.y+1;
		minetest.set_node(pos, {name = "air"});
		itemstack:take_item(); return itemstack
	end,
	
	on_punch = function(pos, node, puncher, pointed_thing) -- for unknown reason texture is unknown
		local meta = minetest.get_meta(pos);
		local owner = meta:get_string("owner");
		local name = puncher:get_player_name();
		if owner == name or not minetest.is_protected(pos, name) then
			if #minetest.get_objects_inside_radius(pos, 1)==0 then 
				minetest.add_entity({x=pos.x,y=pos.y,z=pos.z}, "basic_protect:display")
			end
		end
	end,
	
	
	on_use = function(itemstack, user, pointed_thing)
		local ppos = pointed_thing.under;
		if not ppos then return end
		local pos = protector_position(ppos);
		local meta = minetest.get_meta(pos);
		local owner = meta:get_string("owner");
		local name = user:get_player_name();
		
		if owner == name then
			if #minetest.get_objects_inside_radius(pos, 1)==0 then 
				minetest.add_entity({x=pos.x,y=pos.y,z=pos.z}, "basic_protect:display")
			end
			minetest.chat_send_player(name,"#PROTECTOR: this is your area, protector placed at(" .. pos.x .. "," .. pos.y .. "," .. pos.z .. ". say /unprotect to unclaim area. ");
		elseif owner~=name and minetest.get_node(pos).name=="basic_protect:protector" then
			minetest.chat_send_player(name,"#PROTECTOR: this area is owned by " .. owner .. ", protector placed at(" .. pos.x .. "," .. pos.y .. "," .. pos.z .. ")");
		else
			minetest.chat_send_player(name,"#PROTECTOR: this area is FREE. place protector to claim it. Center is at (" .. pos.x .. "," .. pos.y .. "," .. pos.z.. ")");
		end
	end,
	
	mesecons = {effector = { 
		action_on = function (pos, node,ttl) 
			local meta = minetest.get_meta(pos);
			meta:set_int("space",0)
		end,
		
		action_off = function (pos, node,ttl) 
			local meta = minetest.get_meta(pos);
			meta:set_int("space",1)
		end,
		}
	},
	
	
    on_receive_fields = function(pos, formname, fields, player)
		local meta = minetest.get_meta(pos);
		local owner = meta:get_string("owner");
		local name = player:get_player_name();
		local privs = minetest.get_player_privs(name);
		
		if owner~= name and not privs.privs then return end
		
		if fields.OK then
			if fields.shares then
				meta:set_string("shares",fields.shares);
				basic_protect.cache = {}
			end
			
			if fields.tpos then
				meta:set_string("tpos", fields.tpos)
			    local words = {}
				for word in string.gmatch(fields.tpos, "%S+") do
					words[#words+1] = tonumber(word) or 0
				end
				
				local xt = (words[1] or 0); if math.abs(xt)>basic_protect.radius then xt = 0 end
				local yt = (words[2] or 0); if math.abs(yt)>basic_protect.radius then yt = 0 end
				local zt = (words[3] or 0); if math.abs(zt)>basic_protect.radius then zt = 0 end
				
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

local x = basic_protect.radius/2;
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
	timer = 30,
	
	on_step = function(self, dtime)

		self.timer = self.timer - dtime

		if self.timer < 0 then
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


minetest.register_chatcommand("unprotect", { 
	description = "Unprotects current area",
	privs = {
		interact = true
	},
	func = function(name, param)
		local privs = minetest.get_player_privs(name);
		local player = minetest.get_player_by_name(name);
		local pos = player:getpos();
		local ppos = protector_position(pos);
		
		if minetest.get_node(ppos).name == "basic_protect:protector" then
			local meta = minetest.get_meta(ppos);
			local owner = meta:get_string("owner");
			if owner == name then
				minetest.set_node(ppos,{name = "air"});
				local inv = player:get_inventory();
				inv:add_item("main",ItemStack("basic_protect:protector"));
				minetest.chat_send_player(name, "#PROTECTOR: area unprotected ");
			end
		end
	end
})

minetest.register_chatcommand("protect", { 
	description = "Protects current area",
	privs = {
		interact = true
	},
	func = function(name, param)
		local privs = minetest.get_player_privs(name);
		local player = minetest.get_player_by_name(name);
		if not player then return end
		local pos = player:getpos();
		local ppos = protector_position(pos);
		
		if minetest.get_node(ppos).name == "basic_protect:protector" then
			local meta = minetest.get_meta(ppos);
			local owner = meta:get_string("owner");
			if owner == name then
				if #minetest.get_objects_inside_radius(ppos, 1)==0 then 
					minetest.add_entity({x=ppos.x,y=ppos.y,z=ppos.z}, "basic_protect:display")
				end
				minetest.chat_send_player(name,"#PROTECTOR: this is your area, protector placed at(" .. ppos.x .. "," .. ppos.y .. "," .. ppos.z .. "). say /unprotect to unclaim area. ");
			end
		else
			local inv = player:get_inventory();
			local item = ItemStack("basic_protect:protector");
			if inv:contains_item("main",item) then
				minetest.set_node(ppos,{name = "basic_protect:protector"})
				basic_protect.protect_new(ppos,name);
				inv:remove_item("main",item)

			end
		end
	end
})