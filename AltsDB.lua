local _G = getfenv(0)
local ADDON_NAME, AddonData = ...

local AltsDB = {}
AddonData.AltsDB = AltsDB

-- Use local versions of standard LUA items for performance
local string = _G.string
local table = _G.table
local pairs = _G.pairs
local ipairs = _G.ipairs
local select = _G.select
local tinsert, tremove, tContains = tinsert, tremove, tContains
local unpack, next = _G.unpack, _G.next
local wipe = _G.wipe

local LibAlts = LibStub("LibAlts-1.0")

AltsDB.useLibAlts = false
AltsDB.playerRealm = nil
AltsDB.playerRealmAbbr = nil
AltsDB.Mains = {}
AltsDB.MainsBySource = {}

local function ReverseTable(table)
	local reverse = {}
	if table then
    	for k,v in pairs(table) do
    		for i,a in ipairs(v) do
    			reverse[a] = k
    		end
    	end
	end
	return reverse
end

local realmNames = {
    ["Aeriepeak"] = "AeriePeak",
    ["Altarofstorms"] = "AltarofStorms",
    ["Alteracmountains"] = "AlteracMountains",
    ["Aman'thul"] = "Aman'Thul",
    ["Argentdawn"] = "ArgentDawn",
    ["Azjolnerub"] = "AzjolNerub",
    ["Blackdragonflight"] = "BlackDragonflight",
    ["Blackwaterraiders"] = "BlackwaterRaiders",
    ["Blackwinglair"] = "BlackwingLair",
    ["Blade'sedge"] = "Blade'sEdge",
    ["Bleedinghollow"] = "BleedingHollow",
    ["Bloodfurnace"] = "BloodFurnace",
    ["Boreantundra"] = "BoreanTundra",
    ["Burningblade"] = "BurningBlade",
    ["Burninglegion"] = "BurningLegion",
    ["Cenarioncircle"] = "CenarionCircle",
    ["Darkiron"] = "DarkIron",
    ["Dath'remar"] = "Dath'Remar",
    ["Demonsoul"] = "DemonSoul",
    ["Drak'tharon"] = "Drak'Tharon",
    ["Earthenring"] = "EarthenRing",
    ["Echoisles"] = "EchoIsles",
    ["Eldre'thalas"] = "Eldre'Thalas",
    ["Emeralddream"] = "EmeraldDream",
    ["Grizzlyhills"] = "GrizzlyHills",
    ["Jubei'thos"] = "Jubei'Thos",
    ["Kel'thuzad"] = "Kel'Thuzad",
    ["Khazmodan"] = "KhazModan",
    ["Kirintor"] = "KirinTor",
    ["Kultiras"] = "KulTiras",
    ["Laughingskull"] = "LaughingSkull",
    ["Lightning'sblade"] = "Lightning'sBlade",
    ["Mal'ganis"] = "Mal'Ganis",
    ["Mok'nathal"] = "Mok'Nathal",
    ["Moonguard"] = "MoonGuard",
    ["Quel'thalas"] = "Quel'Thalas",
    ["Scarletcrusade"] = "ScarletCrusade",
    ["Shadowcouncil"] = "ShadowCouncil",
    ["Shatteredhalls"] = "ShatteredHalls",
    ["Shatteredhand"] = "ShatteredHand",
    ["Silverhand"] = "SilverHand",
    ["Sistersofelune"] = "SistersofElune",
    ["Steamwheedlecartel"] = "SteamwheedleCartel",
    ["Theforgottencoast"] = "TheForgottenCoast",
    ["Thescryers"] = "TheScryers",
    ["Theunderbog"] = "TheUnderbog",
    ["Theventureco"] = "TheVentureCo",
    ["Thoriumbrotherhood"] = "ThoriumBrotherhood",
    ["Tolbarad"] = "TolBarad",
    ["Twistingnether"] = "TwistingNether",
    ["Wyrmrestaccord"] = "WyrmrestAccord",
}

local MULTIBYTE_FIRST_CHAR = "^([\192-\255]?%a?[\128-\191]*)"

--- Returns a name formatted in title case (i.e., first character upper case, the rest lower).
-- @name :TitleCase
-- @param name The name to be converted.
-- @return string The converted name.
function AltsDB:TitleCase(name)
    if not name then return "" end
    if #name == 0 then return "" end
	name = name:lower()
    return name:gsub(MULTIBYTE_FIRST_CHAR, string.upper, 1)
end

function AltsDB:GetProperRealmName(realm)
	if not realm then return end
	realm = self:TitleCase(realm:gsub("[ -]", ""))
	return realmNames[realm] or realm
end

function AltsDB:FormatNameWithRealm(name, realm, relative)
	if not name then return end
	name = self:TitleCase(name)
	realm = self:GetProperRealmName(realm)
	if relative and realm and realm == self.playerRealmAbbr then
		return name
	elseif realm and #realm > 0 then
		return name.."-"..realm
	else
		return name
	end
end

function AltsDB:FormatRealmName(realm)
	-- Spaces are removed.
	-- Dashes are removed. (e.g., Azjol-Nerub)
	-- Apostrophe / single quotes are not removed.
	if not realm then return end
	return realm:gsub("[ -]", "")
end

function AltsDB:HasRealm(name)
	if not name then return end
	local matches = name:gmatch("[-]")
	return matches and matches()
end

function AltsDB:ParseName(name)
	if not name then return end
	local matches = name:gmatch("([^%-]+)")
	if matches then
		local nameOnly = matches()
		local realm = matches()
		return nameOnly, realm
	end
	return nil
end

function AltsDB:FormatUnitName(name, relative)
	local nameOnly, realm = self:ParseName(name)
	return self:FormatNameWithRealm(nameOnly, realm, relative)
end

function AltsDB:FormatUnitList(sep, relative, ...)
	local str = ""
	local first = true
	local v
	for i = 1, select('#', ...), 1 do
		v = select(i, ...)
		if v and #v > 0 then
			if not first then str = str .. sep end
			str = str .. self:FormatUnitName(v, relative)
			if first then first = false end
		end
	end
	return str
end

function AltsDB:GetAlternateName(name)
	local nameOnly, realm = self:ParseName(name)
	return realm and self:TitleCase(nameOnly) or
		self:FormatNameWithRealm(self:TitleCase(nameOnly), self.playerRealmAbbr)
end

--- Remove a data source, including all main-alt relationships.
-- @name :RemoveSourceLocal
-- @param source Data source to be removed.
function AltsDB:RemoveSourceLocal(source)
    if self.db.realm.altsBySource[source] then
        wipe(self.db.realm.altsBySource[source])
        self.db.realm.altsBySource[source] = nil
    end
    if self.MainsBySource[source] then
        wipe(self.MainsBySource[source])
        self.MainsBySource[source] = nil
    end
end

--- Remove a data source, including all main-alt relationships.
-- @name :RemoveSource
-- @param source Data source to be removed.
function AltsDB:RemoveSource(source)
	if self.useLibAlts then
		return LibAlts:RemoveSource(source)
	end
	return self:RemoveSourceLocal(source)
end

--- Define a main-alt relationship.
-- @name :SetAltLocal
-- @param main Name of the main character.
-- @param alt Name of the alt character.
-- @param source The data source to store it in.
function AltsDB:SetAltLocal(main, alt, source)
    if not main or not alt then return end
    
    main = self:TitleCase(main)
    alt = self:TitleCase(alt)

    if not source then
        self.db.realm.alts[main] = self.db.realm.alts[main] or {}
        for i,v in ipairs(self.db.realm.alts[main]) do
            if v == alt then
                return
            end
        end

        tinsert(self.db.realm.alts[main], alt)
    
        if self.Mains then
            self.Mains[alt] = main
        end
    else
        self.db.realm.altsBySource[source] = self.db.realm.altsBySource[source] or {}
        self.db.realm.altsBySource[source][main] = 
            self.db.realm.altsBySource[source][main] or {}
        for i,v in ipairs(self.db.realm.altsBySource[source][main]) do
            if v == alt then
                return
            end
        end

        tinsert(self.db.realm.altsBySource[source][main], alt)
    
        if self.MainsBySource then
            self.MainsBySource[source] = self.MainsBySource[source] or {}
            self.MainsBySource[source][alt] = main
        end
    end
end

--- Define a main-alt relationship.
-- @name :SetAlt
-- @param main Name of the main character.
-- @param alt Name of the alt character.
-- @param source The data source to store it in.
function AltsDB:SetAlt(main, alt, source)
	if self.useLibAlts then
		return LibAlts:SetAlt(main, alt, source)
	end
	return self:SetAltLocal(main, alt, source)
end

--- Return a list of alts for a given name.
-- @name :GetAlt
-- @param main Name of the main character.
-- @return list List of alts for the main.
function AltsDB:GetAlts(main)
	if self.useLibAlts then
		return LibAlts:GetAlts(main)
	end

    if not main then return end
    
    main = self:TitleCase(main)
    local alts = {}
    local name

    if self.db.realm.alts[main] and #self.db.realm.alts[main] > 0 then
        for i,v in ipairs(self.db.realm.alts[main]) do
            if not tContains(alts, v) then
                tinsert(alts, v)
            end
        end
    end

    for k,v in pairs(self.db.realm.altsBySource) do
        if self.db.realm.altsBySource[k][main] and #self.db.realm.altsBySource[k][main] > 0 then
            for i,v in ipairs(self.db.realm.altsBySource[k][main]) do
                if not tContains(alts, v) then
                    tinsert(alts, v)
                end
            end
        end
    end

    if alts and #alts > 0 then
        return unpack(alts)
    end

    return nil
end

--- Return a list of alts for a given name.
--- Checks the alternate name.
-- @name :GetAlt
-- @param main Name of the main character.
-- @return list List of alts for the main.
function AltsDB:GetAltsForMain(main, merge)
	local alts = { self:GetAlts(main) }
	if merge then
		local altMain = self:GetAlternateName(main)
		local moreAlts = { self:GetAlts(altMain) }
		if #moreAlts > #alts then main = altMain end
		for i, v in ipairs(moreAlts) do
			if not tContains(alts, v) then
				tinsert(alts, v)
			end
		end
	else
		if not alts or #alts < 1 then
			main = self:GetAlternateName(main)
			alts = { self:GetAlts(main) }
		end
	end
	return main, alts
end

--- Return a list of alts for a given name for a given data source.
-- @name :GetAltsForSource
-- @param main Name of the main character.
-- @param source The data source to use.
-- @return list List of alts for the main.
function AltsDB:GetAltsForSource(main, source)
    if not main or #main == 0 or not source or #source == 0 then return nil end

    main = self:TitleCase(main)
    
    if not source then
    	if self.db.realm.alts[main] and #self.db.realm.alts[main] > 0 then
    	    return unpack(self.db.realm.alts[main])
    	end
    else
        if not self.db.realm.altsBySource[source] then return nil end

        if self.db.realm.altsBySource[source][main] and
            #self.db.realm.altsBySource[source][main] > 0 then
            return unpack(self.db.realm.altsBySource[source][main])
        end
    end

    return nil
end

--- Remove a main-alt relationship.
-- @name :DeleteAltLocal
-- @param main Name of the main character.
-- @param alt Name of the alt being removed.
-- @param source The data source to use.
function AltsDB:DeleteAltLocal(main, alt, source)
	main = self:TitleCase(main)
	alt = self:TitleCase(alt)

    if not source then
    	if not self.db.realm.alts[main] then return end

    	for i = 1, #self.db.realm.alts[main] do
    		if self.db.realm.alts[main][i] == alt then
    			tremove(self.db.realm.alts[main], i)
    		end
    	end
    	if #self.db.realm.alts[main] == 0 then
    		self.db.realm.alts[main] = nil
    	end
	
    	if self.Mains then
    	    for i,v in ipairs(self.Mains) do
    	        if v[1] == alt then
    	            tremove(self.Mains, i)
                end
            end
        end
    else
    	if not self.db.realm.altsBySource[source] then return end
    	if not self.db.realm.altsBySource[source][main] then return end

    	for i = 1, #self.db.realm.altsBySource[source][main] do
    		if self.db.realm.altsBySource[source][main][i] == alt then
    			tremove(self.db.realm.altsBySource[source][main], i)
    		end
    	end
    	if #self.db.realm.altsBySource[source][main] == 0 then
    		self.db.realm.altsBySource[source][main] = nil
    	end
	
    	if self.MainsBySource and self.MainsBySource[source] then
    	    for i,v in ipairs(self.MainsBySource[source]) do
    	        if v[1] == alt then
    	            tremove(self.MainsBySource[source], i)
                end
            end
        end
    end
end

--- Remove a main-alt relationship.
-- @name :DeleteAlt
-- @param main Name of the main character.
-- @param alt Name of the alt being removed.
-- @param source The data source to use.
function AltsDB:DeleteAlt(main, alt, source)
	if self.useLibAlts then
		return LibAlts:DeleteAlt(main, alt, source)
	end
	return self:DeleteAltLocal(main, alt, source)
end

--- Get the main for a given alt character
-- @name :GetMain 
-- @param alt Name of the alt character.
-- @return string Name of the main character.
function AltsDB:GetMain(alt)
	if self.useLibAlts then
		return LibAlts:GetMain(alt)
	end

	if not alt or not self.Mains then return end
	alt = self:TitleCase(alt)

	local main = self.Mains[alt]
	if main then return main end

	if not self.MainsBySource then return nil end
	for k, v in pairs(self.MainsBySource) do
	    main = self.MainsBySource[k][alt]
	    if main then return main end
    end
end

--- Get the main for a given alt character.  
--- Checks the alternate form of the name.
-- @name :GetMainForAlt
-- @param alt Name of the alt character.
-- @return string Name of the main character.
-- @return string Name of the alt that was found.
function AltsDB:GetMainForAlt(alt)
    if not alt or #alt < 1 then return end

	local altFound = alt
    local main = self:GetMain(altFound)
	if not main or #main < 1 then
		altFound = self:GetAlternateName(alt)
		main = self:GetMain(altFound)
	end
	return main, main and altFound or nil
end

--- Get all the mains in the database
-- @name :GetAllMains 
-- @return table Table of all main names.
function AltsDB:GetAllMains(table)
	if self.useLibAlts then
		return LibAlts:GetAllMains(table)
	end

    for k, v in pairs(self.db.realm.alts) do
        if not tContains(table, k) then
            tinsert(table, k)
        end
    end
	for k, v in pairs(self.db.realm.altsBySource) do
	    for key,val in pairs(self.db.realm.altsBySource[k]) do
	        if not tContains(table, key) then
	            tinsert(table, key)
	        end
        end
    end
    return table
end

function AltsDB:DeleteUserMain(main)
    if not main then return end

    local alts
    if self.useLibAlts == true then
        alts = { LibAlts:GetAltsForSource(main, nil) }
    else
        alts = { self:GetAltsForSource(main, nil) }
    end
    
    if alts and #alts > 0 then
        for i, alt in pairs(alts) do
            if alt and #alt > 0 then
                self:DeleteAlt(main, alt)
            end
        end
    end
end

function AltsDB:PushLibAltsData()
    if self.useLibAlts == true then
        for k, v in pairs(self.db.realm.alts) do
            for i, alt in ipairs(self.db.realm.alts[k]) do
                LibAlts:SetAlt(k, alt)
            end
        end
        
        for source, mains in pairs(self.db.realm.altsBySource) do
            for main, alts in pairs(mains) do
                for i, alt in ipairs(alts) do
                    LibAlts:SetAlt(main, alt, source)
                end 
            end
        end
    end
end

function AltsDB:UpdateMainsBySource(source)
    self.MainsBySource[source] = ReverseTable(self.db.realm.altsBySource[source])
end

function AltsDB:UpdateMains()
    self.Mains = ReverseTable(self.db.realm.alts)
end

function AltsDB:SetAltEvent(event, main, alt, source)
    self:SetAltLocal(main, alt, source)
end

function AltsDB:DeleteAltEvent(event, main, alt, source)
    self:DeleteAltLocal(main, alt, source)
end

function AltsDB:RemoveSourceEvent(event, source)
    self:RemoveSourceLocal(source)
end

function AltsDB:OnInitialize(Alts)
	self.Alts = Alts
	self.db = Alts.db
	self.playerRealm = _G.GetRealmName()
	self.playerRealmAbbr = self:FormatRealmName(self.playerRealm)

    self:UpdateMains()

    -- Check that LibAlts is available and has the correct methods
    if LibAlts and LibAlts.RegisterCallback and LibAlts.SetAlt and 
        LibAlts.DeleteAlt and LibAlts.RemoveSource and LibAlts.GetAlts then
        self.useLibAlts = true
    end

    if self.useLibAlts == true then
        -- Push the data into LibAlts before registering callbacks
        self:PushLibAltsData()
        -- Register callbacks for LibAlts
        LibAlts.RegisterCallback(self, "LibAlts_SetAlt", "SetAltEvent")
        LibAlts.RegisterCallback(self, "LibAlts_RemoveAlt", "DeleteAltEvent")
        LibAlts.RegisterCallback(self, "LibAlts_RemoveSource", "RemoveSourceEvent")
    end
end

function AltsDB:OnEnable()
    -- Build reverse lookup tables for other guilds.
    for k,v in pairs(self.db.realm.altsBySource) do
        local guildName = _G.GetGuildInfo("player")
        if not (k == guildName and self.db.profile.autoGuildImport) then
			self:UpdateMainsBySource(k)
        end
    end
end
