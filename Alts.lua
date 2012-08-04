Alts = LibStub("AceAddon-3.0"):NewAddon("Alts", "AceConsole-3.0", "AceHook-3.0", "AceEvent-3.0", "AceTimer-3.0")
local AGU = LibStub("AceGUI-3.0")

local ADDON_NAME = ...
local ADDON_VERSION = "@project-version@"

local DEBUG = false

local L = LibStub("AceLocale-3.0"):GetLocale("Alts", true)
local LibDeformat = LibStub("LibDeformat-3.0")
local LDB = LibStub("LibDataBroker-1.1")
local icon = LibStub("LibDBIcon-1.0")
local LibAlts = LibStub("LibAlts-1.0")
local ScrollingTable = LibStub("ScrollingTable")

-- Need to setup an AltHandler or Proxy so that it can be standalone if needed
-- If using LibAlt then call LibAlt set, delete, and remove and allow the callback
-- to update our local data.  Might be able to get rid of the Mains tables then.
-- If using the local handler, then it 

local GREEN = "|cff00ff00"
local YELLOW = "|cffffff00"
local BLUE = "|cff0198e1"
local ORANGE = "|cffff9933"
local WHITE = "|cffffffff"

-- Use local versions of standard LUA items for performance
local tinsert, tremove, tContains = tinsert, tremove, tContains
local tconcat, tsort = table.concat, table.sort
local pairs, ipairs, unpack = pairs, ipairs, unpack

-- Functions defined at the end of the file.
local formatCharName
local wrap

local defaults = {
	profile = {
		minimap = {
			hide = true,
		},
		verbose = true,
		disableInCombat = true,
		autoGuildImport = true,
		showMainInTooltip = true,
		showAltsInTooltip = true,
        showInfoOnLogon = true,
        showInfoOnWho = true,
        showMainsInChat = true,
        singleLineChatDisplay = true,
        singleLineTooltipDisplay = true,
		wrapTooltip = true,
		wrapTooltipLength = 50,
		reportMissingMains = false,
		lock_main_window = false,
		remember_main_pos = true,
		main_window_x = 0,
		main_window_y = 0,
		remember_contrib_pos = true,
		contrib_window_x = 0,
		contrib_window_y = 0,
		saveGuild = true,
		exportUseName = true,
		exportUseRank = true,
		exportUseLevel = true,
		exportUseClass = true,
		exportUsePublicNote = true,
		exportUseOfficerNote = true,
		exportUseLastOnline = true,
		exportUseAchvPoints = true,
		exportUseWeeklyXP = true,
		exportUseTotalXP = true,
		exportUseAlts = true,
		exportEscape = true,
		exportOnlyMains = true,
		exportOnlyGuildAlts = true,
		reportRemovedFriends = true,
		reportRemovedIgnores = true,
		reportGuildChanges = true
	},
	realm = {
	    alts = {},
	    altsBySource = {},
	    guilds = {},
		guildLog = {},
	},
	char = {
	    friends = {},
	    ignores = {},
	}
}

local combat = false
local monitor = true
local options
local playerName = ""
local useLibAlts = false
local altsLDB = nil
local altsFrame = nil
local contribFrame = nil
local setMainFrame = nil
local addAltFrame = nil
local addMainFrame = nil
local editAltsFrame = nil
local confirmDeleteFrame = nil
local confirmMainDeleteFrame = nil
local Mains = {}
local MainsBySource = {}
local AllMains = {}
local MainsTable = {}
local EditAltsTable = {}
local GuildXP = {
    weekly = {
        data = {},
        sorted = {},
        totalXP = 0
    },
    total = {
        data = {},
        sorted = {},
        totalXP = 0
    }
}

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

function Alts:HookChatFrames()
    for i = 1, NUM_CHAT_WINDOWS do
        local chatFrame = _G["ChatFrame" .. i]
        if chatFrame ~= COMBATLOG then
            self:RawHook(chatFrame, "AddMessage", true)
        end
    end
end

function Alts:UnhookChatFrames()
    for i = 1, NUM_CHAT_WINDOWS do
        local chatFrame = _G["ChatFrame" .. i]
        if chatFrame ~= COMBATLOG then
            self:Unhook(chatFrame, "AddMessage")
        end
    end
end

local function AddMainNameForChat(message, name)
    if name and #name > 0 and name ~= playerName then
        local main = LibAlts:GetMain(name)
        if main and #main > 0 then
            local messageFmt = "%s (%s)"
            return messageFmt:format(message, main)
        end
    end
    
    return message
end

function Alts:AddMessage(frame, text, ...)
    -- If we are monitoring chat and the message is text then try to rewrite it.
    if monitor and text and type(text) == "string" then
        text = text:gsub("(|Hplayer:([^:]+).-|h.-|h)", AddMainNameForChat)
    end
    return self.hooks[frame].AddMessage(frame, text, ...)
end

--- Returns a name formatted in title case (i.e., first character upper case, the rest lower).
-- @name :TitleCase
-- @param name The name to be converted.
-- @return string The converted name.
function Alts:TitleCase(name)
    if not name then return "" end
    if #name == 0 then return "" end

    local MULTIBYTE_FIRST_CHAR = "^([\192-\255]?%a?[\128-\191]*)"
    name = name:lower()
    return name:gsub(MULTIBYTE_FIRST_CHAR, string.upper, 1)
end

--- Remove a data source, including all main-alt relationships.
-- @name :RemoveSource
-- @param source Data source to be removed.
function Alts:RemoveSource(source)
    if self.db.realm.altsBySource[source] then
        wipe(self.db.realm.altsBySource[source])
        self.db.realm.altsBySource[source] = nil
    end
    if MainsBySource[source] then
        wipe(MainsBySource[source])
        MainsBySource[source] = nil
    end
    
    self:UpdateMainsTable()
end

--- Define a main-alt relationship.
-- @name :SetAlt
-- @param main Name of the main character.
-- @param alt Name of the alt character.
-- @param source The data source to store it in.
function Alts:SetAlt(main, alt, source)
    if not main or not alt then return end
    
    main = self:TitleCase(main)
    alt = self:TitleCase(alt)

    if main then
        self:UpdateMainsTable(main)
    end

    if not source then
        self.db.realm.alts[main] = self.db.realm.alts[main] or {}
        for i,v in ipairs(self.db.realm.alts[main]) do
            if v == alt then
                return
            end
        end

        tinsert(self.db.realm.alts[main], alt)
    
        if Mains then
            Mains[alt] = main
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
    
        if MainsBySource then
            MainsBySource[source] = MainsBySource[source] or {}
            MainsBySource[source][alt] = main
        end
    
    end
end

function Alts:SetAltEvent(event, main, alt, source)
    self:SetAlt(main, alt, source)
end

function Alts:DeleteAltEvent(event, main, alt, source)
    self:DeleteAlt(main, alt, source)
end

function Alts:RemoveSourceEvent(event, source)
    self:RemoveSource(source)
end

function Alts:PushLibAltsData()
    if useLibAlts == true then
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

function Alts:CheckAndUpdateFriends()
    local friends = {}
    local numFriends = GetNumFriends()
    local strFmt = L["FriendsLog_RemovedFriend"]
    
    local name, level, class, area, connected, status, note, RAF
    
    for i = 1, numFriends do
        name, level, class, area, connected, status, note, RAF = GetFriendInfo(i)
        if name and name ~= "" then
            friends[name] = (note or "")
        end
    end
    
    -- Check for removed friends
    for name, note in pairs(self.db.char.friends) do
        if friends[name] == nil and self.db.profile.reportRemovedFriends == true then
            self:Print(strFmt:format(name))
        end
    end

    self.db.char.friends = friends
end

function Alts:CheckAndUpdateIgnores()
    local ignores = {}
    local numIgnores = GetNumIgnores()
    local strFmt = L["IgnoreLog_RemovedIgnore"]
    
    local name, value
    
    for i = 1, numIgnores do
        name = GetIgnoreName(i)
        if name and name ~= "?" then
            ignores[name] = true
        end
    end
    
    -- Check for removed ignores
    for name, value in pairs(self.db.char.ignores) do
        if ignores[name] == nil and self.db.profile.reportRemovedIgnores == true then
            self:Print(strFmt:format(name))
        end
    end

    self.db.char.ignores = ignores
end

function Alts:GuildContrib()
    wipe(GuildXP.weekly.data)
    wipe(GuildXP.total.data)
    GuildXP.weekly.totalXP = 0
    GuildXP.total.totalXP = 0
    
    local guildName = GetGuildInfo("player")
    local numMembers = GetNumGuildMembers(true)
    
    if not guildName or numMembers == 0 then return end

    local source = LibAlts.GUILD_PREFIX..guildName

    for i = 1, numMembers do
        local name, rank, rankIndex, level, class, zone, publicnote,  
            officernote, online, status, classFileName, achPts, 
            achRank, isMobile, canSoR = GetGuildRosterInfo(i)

        local years, months, days, hours = GetGuildRosterLastOnline(i)
        local lastOnline = 0
        if online then
            lastOnline = time()
        elseif years and months and days and hours then
            local diff = (((years*365)+(months*30)+days)*24+hours)*60*60
            lastOnline = time() - diff
        end

        local weeklyXP, totalXP, weeklyRank, totalRank = GetGuildRosterContribution(i)

        local main = (LibAlts:GetMainForSource(name, source) or name)

        GuildXP.weekly.data[main] = (GuildXP.weekly.data[main] or 0) + weeklyXP
        GuildXP.weekly.totalXP = GuildXP.weekly.totalXP + weeklyXP
        GuildXP.total.data[main] = (GuildXP.total.data[main] or 0) + totalXP
        GuildXP.total.totalXP = GuildXP.total.totalXP + totalXP
    end

    wipe(GuildXP.weekly.sorted)
    for name, xp in pairs(GuildXP.weekly.data) do
        tinsert(GuildXP.weekly.sorted, {name, xp})
    end
    tsort(GuildXP.weekly.sorted, function(a,b) return a[2] > b[2] end)

    wipe(GuildXP.total.sorted)
    for name, xp in pairs(GuildXP.total.data) do
        tinsert(GuildXP.total.sorted, {name, xp})
    end
    tsort(GuildXP.total.sorted, function(a,b) return a[2] > b[2] end)
end

function Alts:UpdateGuild()
    if not self.db.profile.autoGuildImport then return end
    
    local guildName = GetGuildInfo("player")
    local numMembers = GetNumGuildMembers(true)
    
    if not guildName or numMembers == 0 then return end

    local source = LibAlts.GUILD_PREFIX..guildName

    if useLibAlts == true then
        LibAlts:RemoveSource(source)
    else
        self:RemoveSource(source)
    end
    
    local guildMembers = {}
    local numAlts = 0
    local numMains = 0
    
    -- Build a list of the guild members
    -- Using it later to verify that names are in the guild
    for i = 1, numMembers do
        local name, rank, rankIndex, level, class, zone, publicnote,  
            officernote, online, status, classFileName, achPts, 
            achRank, isMobile, canSoR = GetGuildRosterInfo(i)
        local years, months, days, hours = GetGuildRosterLastOnline(i)

        local lastOnline = 0
        if online then
            lastOnline = time()
        elseif years and months and days and hours then
            local diff = (((years*365)+(months*30)+days)*24+hours)*60*60
            lastOnline = time() - diff
        end

        guildMembers[LibAlts:TitleCase(name)] = lastOnline
    end

    -- Save the information if we're tracking the guild.
    if self.db.profile.saveGuild then
        local nameWithMainFmt = "%s (" .. L["Main: "] .. "%s)"
        -- Before updating the saved guild info, check for the differences.
        self.db.realm.guilds[guildName] = self.db.realm.guilds[guildName] or {}
        self.db.realm.guildLog[guildName] = self.db.realm.guildLog[guildName] or {}

        if self.db.realm.guilds[guildName] ~= {} then
            -- Compare the new guild roster to the old
            local name, lastOnline
            local joinFmt = "%s "..L["GuildLog_JoinedGuild"]
            local joinLogFmt = "%s  %s "..L["GuildLog_JoinedGuild"]
            for name, lastOnline in pairs(guildMembers) do
                if self.db.realm.guilds[guildName][name] == nil then
                    if self.db.profile.reportGuildChanges == true then
                        self:Print(joinFmt:format(name))
                    end
                    tinsert(self.db.realm.guildLog[guildName],
                        joinLogFmt:format(date("%Y/%m/%d %H:%M"), name))
                end 
            end

            local leaveFmt = "%s "..L["GuildLog_LeftGuild"]
            local leaveLogFmt = "%s  %s "..L["GuildLog_LeftGuild"]
            for name, lastOnline in pairs(self.db.realm.guilds[guildName]) do
                if guildMembers[name] == nil then
                    local nameWithMain = name
                    local main = LibAlts:GetMain(name)
                    if main and #main > 0 then
                        nameWithMain = nameWithMainFmt:format(name, main)
                    end
                    if self.db.profile.reportGuildChanges == true then
                        self:Print(leaveFmt:format(nameWithMain))
                    end
                    tinsert(self.db.realm.guildLog[guildName],
                        leaveLogFmt:format(date("%Y/%m/%d %H:%M"), nameWithMain))
                end 
            end
        end

        -- Update the saved guild information
        self.db.realm.guilds[guildName] = guildMembers
    end

    -- Walk through the list and look for alt names
    for i = 1, numMembers do
        local name, rank, rankIndex, level, class, zone, publicnote,  
            officernote, online, status, classFileName, achPts, 
            achRank, isMobile, canSoR = GetGuildRosterInfo(i)
        local years, months, days, hours = GetGuildRosterLastOnline(i)

        name = self:TitleCase(name)

        local main
        -- Look for the following patterns in public and officer notes:
        --   * <name>'s alt
        --   * ALT: <name>
        --   * Alt of <name>
        --   * <name>
        --   * AKA: <name>
        --   * (<name>)
        --   * ([name])
        local altMatch1 = "(.-)'s? [Aa][Ll][Tt]"
        local altMatch2 = "[Aa][Ll][Tt]:%s*([%a\128-\255]+)"
        local altMatch3 = "[Aa][Ll][Tt] [Oo][Ff] ([%a\128-\255]+)"
        local altMatch4 = "[Aa][Kk][Aa]:%s*([%a\128-\255]+)"
        local altMatch5 = "^[(]([%a\128-\255]+)[)]"
        local altMatch6 = "^[%[]([%a\128-\255]+)[%]]"

        local funcs = {
            -- Check if the note format is "<name>'s alt"
            function(val)
                return val:match(altMatch1)
            end,
            -- Check if the note format is "ALT: <name>"
            function(val)
                return val:match(altMatch2)
            end,
            -- Check if the note format is "Alt of <name>"
            function(val)
                return val:match(altMatch3)
            end,
            -- Check if the note format is "AKA: <name>"
            function(val)
                return val:match(altMatch4)
            end,
            -- Check if the note format is "(<name>)"
            function(val)
                return val:match(altMatch5)
            end,
            -- Check if the note format is "([name])"
            function(val)
                return val:match(altMatch6)
            end,
            -- Check if the note is just a name
            function(val)
                return val
            end,     
        }

        for i,v in ipairs(funcs) do
            local badRefFmt = L["Reference to a non-existent main %s for %s."]

            main = self:TitleCase(v(officernote))
            if main and #main > 0 then
                if guildMembers[main] then 
                    break
                elseif main ~= self:TitleCase(officernote) then
                    if self.db.profile.reportMissingMains then
                        self:Print(badRefFmt:format(main, name))
                    end
                end
            end
            
            main = self:TitleCase(v(publicnote))
            if main and #main > 0 then
                if guildMembers[main] then
                    break
                elseif main ~= self:TitleCase(publicnote) then
                    if self.db.profile.reportMissingMains then
                        self:Print(badRefFmt:format(main, name))
                    end
                end
            end
        end
        
        -- Check if we found a valid alt name
        if main and #main > 0 then
            if guildMembers[main] then
                -- If the main doesn't exist yet, then increase the counter
                if not self:GetAltsForSource(main, source) then
                    numMains = numMains + 1
                end
                -- Add the main-alt relationship for this guild
                if useLibAlts == true then
                    LibAlts:SetAlt(main, name, source)
                else
                    self:SetAlt(main, name, source)
                end
                numAlts = numAlts + 1
            end
        end
    end

    -- Create the reverse lookup table
    MainsBySource[source] = ReverseTable(self.db.realm.altsBySource[source])

    local importFormat = L["Imported the guild '%s'. Mains: %d, Alts: %d."]
    self:Print(importFormat:format(guildName, numMains, numAlts))
end

--- Return a list of alts for a given name.
-- @name :GetAlt
-- @param main Name of the main character.
-- @return list List of alts for the main.
function Alts:GetAlts(main)
    if not main then return end
    
    main = self:TitleCase(main)

    local alts = {}
    
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

--- Return a list of alts for a given name for a given data source.
-- @name :GetAltsForSource
-- @param main Name of the main character.
-- @param source The data source to use.
-- @return list List of alts for the main.
function Alts:GetAltsForSource(main, source)
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
-- @name :DeleteAlt
-- @param main Name of the main character.
-- @param alt Name of the alt being removed.
-- @param source The data source to use.
function Alts:DeleteAlt(main, alt, source)
	main = self:TitleCase(main)
	alt = self:TitleCase(alt)

    if main then
        self:UpdateMainsTable(main)
    end

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
	
    	if Mains then
    	    for i,v in ipairs(Mains) do
    	        if k[1] == alt then
    	            tremove(Mains, i)
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
	
    	if MainsBySource and MainsBySource[source] then
    	    for i,v in ipairs(MainsBySource[source]) do
    	        if k[1] == alt then
    	            tremove(MainsBySource[source], i)
                end
            end
        end
    end
end

--- Get the main for a given alt character
-- @name :GetMain 
-- @param alt Name of the alt character.
-- @return string Name of the main character.
function Alts:GetMain(alt)
	if not alt or not Mains then return end

	alt = self:TitleCase(alt)

	local main = Mains[alt]
	
	if main then return main end
	
	if not MainsBySource then return nil end
	
	for k, v in pairs(MainsBySource) do
	    main = MainsBySource[k][alt]
	    if main then return main end
    end
end

--- Get all the mains in the database
-- @name :GetAllMains 
-- @return table Table of all main names.
function Alts:GetAllMains()
    for k, v in pairs(self.db.realm.alts) do
        if not tContains(AllMains, k) then
            tinsert(AllMains, k)
        end
    end

	for k, v in pairs(self.db.realm.altsBySource) do
	    for key,val in pairs(self.db.realm.altsBySource[k]) do
	        if not tContains(AllMains, key) then
	            tinsert(AllMains, key)
	        end
        end
    end

    return AllMains
end

function Alts:DeleteUserMain(main)
    if not main then return end

    local alts
    if useLibAlts == true then
        alts = { LibAlts:GetAltsForSource(main, nil) }
    else
        alts = { self:GetAltsForSource(main, nil) }
    end
    
    if alts and #alts > 0 then
        for i, alt in pairs(alts) do
            if alt and #alt > 0 then
                if useLibAlts then
                    LibAlts:DeleteAlt(main, alt)
                else
                    self:DeleteAlt(main, alt)
                end
            end
        end
    end
end

function Alts:UpdateMainsTable(main)
    local altList
    local alts
    if not main then
        local allMains

        if useLibAlts == true then
            allMains = {}
            LibAlts:GetAllMains(allMains)
        else
            allMains = self:GetAllMains()
        end

        wipe(MainsTable)

        for i,v in pairs(allMains) do
            local name = self:TitleCase(v)
            if useLibAlts == true then
--[[
                alts = {LibAlts:GetAlts(name)}
                for i, v in ipairs(alts) do
                    if v and alts[i] then
                        alts[i] = self:TitleCase(v)
                    end
                end
                altList = tconcat(alts, ", ") or ""
]]--
                altList = strjoin(", ", LibAlts:GetAlts(name)) or ""
            else
                altList = strjoin(", ", self:GetAlts(name)) or ""
            end
            tinsert(MainsTable, {name, altList})
        end
    else
		local name
        main = self:TitleCase(main)
        for i, v in ipairs(MainsTable) do
            if v then
                name = v[1]
--                if self:TitleCase(name) == main then
                if name == main then
                    -- Remove the existing entry
                    tremove(MainsTable, i)
                    break
                end
            end
        end

        if useLibAlts == true then
--[[
            alts = {LibAlts:GetAlts(main)}
            for i, v in ipairs(alts) do
                if v and alts[i] then
                    alts[i] = self:TitleCase(v)
                end
            end
            altList = tconcat(alts, ", ") or ""
]]--
            altList = strjoin(", ", LibAlts:GetAlts(main)) or ""
        else
            altList = strjoin(", ", self:GetAlts(main)) or ""
        end
        tinsert(MainsTable, {main, altList})
    end

    if altsFrame and altsFrame:IsVisible() then
        altsFrame.table:SortData()
    end
end

function Alts:GetOptions()
    if not options then
        options = {
            name = ADDON_NAME,
            type = 'group',
            args = {
                core = {
				    order = 1,
					name = L["General Options"],
					type = "group",
					args = {
                		displayheader = {
                			order = 0,
                			type = "header",
                			name = L["General Options"],
                		},
                	    minimap = {
                            name = L["Minimap Button"],
                            desc = L["Toggle the minimap button"],
                            type = "toggle",
                            set = function(info,val)
                                	-- Reverse the value since the stored value is to hide it
                                    self.db.profile.minimap.hide = not val
                                	if self.db.profile.minimap.hide then
                                		icon:Hide("AltsLDB")
                                	else
                                		icon:Show("AltsLDB")
                                	end
                                  end,
                            get = function(info)
                        	        -- Reverse the value since the stored value is to hide it
                                    return not self.db.profile.minimap.hide
                                  end,
                			order = 10
                        },
                	    disableInCombat = {
                            name = L["Disable in Combat"],
                            desc = L["DisableInCombat_OptionDesc"],
                            type = "toggle",
                            set = function(info, val)
                                    self.db.profile.disableInCombat = val
                                end,
                            get = function(info)
                                    return self.db.profile.disableInCombat
                                end,
                			order = 12
                        },
                	    verbose = {
                            name = L["Verbose"],
                            desc = L["Toggles the display of informational messages"],
                            type = "toggle",
                            set = function(info, val) self.db.profile.verbose = val end,
                            get = function(info) return self.db.profile.verbose end,
                			order = 15
                        },
                		headerMainWindow = {
                			order = 200,
                			type = "header",
                			name = L["Main Window"],
                		},
                        lock_main_window = {
                            name = L["Lock"],
                            desc = L["Lock_OptionDesc"],
                            type = "toggle",
                            set = function(info,val)
                                self.db.profile.lock_main_window = val
                                altsFrame.lock = val
                            end,
                            get = function(info) return self.db.profile.lock_main_window end,
                			order = 210
                        },
                        remember_main_pos = {
                            name = L["Remember Position"],
                            desc = L["RememberPosition_OptionDesc"],
                            type = "toggle",
                            set = function(info,val) self.db.profile.remember_main_pos = val end,
                            get = function(info) return self.db.profile.remember_main_pos end,
                			order = 220
                        },
                		displayheaderTooltip = {
                			order = 300,
                			type = "header",
                			name = L["Tooltip Options"],
                		},
                        wrapTooltip = {
                            name = L["Wrap Tooltips"],
                            desc = L["Wrap notes in tooltips"],
                            type = "toggle",
                            set = function(info,val) self.db.profile.wrapTooltip = val end,
                            get = function(info) return self.db.profile.wrapTooltip end,
                			order = 310
                        },
                        wrapTooltipLength = {
                            name = L["Tooltip Wrap Length"],
                            desc = L["Maximum line length for a tooltip"],
                            type = "range",
                			min = 20,
                			max = 80,
                			step = 1,
                            set = function(info,val) self.db.profile.wrapTooltipLength = val end,
                            get = function(info) return self.db.profile.wrapTooltipLength end,
                			order = 320
                        },
                    },
                },
                notes = {
				    order = 2,
					name = L["Notes"],
					type = "group",
					args = {
                		displayheaderDisplay = {
                			order = 100,
                			type = "header",
                			name = L["Display Options"],
                		},
                	    showMainsInChat = {
                            name = L["Main Names in Chat"],
                            desc = L["MainNamesInChat_OptionDesc"],
                            type = "toggle",
                            set = function(info, val)
                                    self.db.profile.showMainsInChat = val
                                    if val then
                                        self:HookChatFrames()
                                    else
                                        self:UnhookChatFrames()
                                    end
                                end,
                            get = function(info) return self.db.profile.showMainsInChat end,
                			order = 105
                        },
                	    mainInTooltip = {
                            name = L["Main Name In Tooltips"],
                            desc = L["Toggles the display of the main name in tooltips"],
                            type = "toggle",
                            set = function(info, val) self.db.profile.showMainInTooltip = val end,
                            get = function(info) return self.db.profile.showMainInTooltip end,
                			order = 110
                        },
                	    altsInTooltip = {
                            name = L["Alt Names In Tooltips"],
                            desc = L["Toggles the display of alt names in tooltips"],
                            type = "toggle",
                            set = function(info, val) self.db.profile.showAltsInTooltip = val end,
                            get = function(info) return self.db.profile.showAltsInTooltip end,
                			order = 120
                        },
                	    infoOnLogon = {
                            name = L["Main/Alt Info on Friend Logon"],
                            desc = L["Toggles the display of main/alt information when a friend or guild member logs on"],
                            type = "toggle",
                            set = function(info, val) self.db.profile.showInfoOnLogon = val end,
                            get = function(info) return self.db.profile.showInfoOnLogon end,
                			order = 130
                        },
                	    infoOnWho = {
                            name = L["Main/Alt Info with /who"],
                            desc = L["Toggles the display of main/alt information with /who results"],
                            type = "toggle",
                            set = function(info, val) self.db.profile.showInfoOnWho = val end,
                            get = function(info) return self.db.profile.showInfoOnWho end,
                			order = 140
                        },
                	    singleLineChatDisplay = {
                            name = L["Single Line for Chat"],
                            desc = L["Toggles whether the main and alt information is on one line or separate lines in the chat window."],
                            type = "toggle",
                            set = function(info, val) self.db.profile.singleLineChatDisplay = val end,
                            get = function(info) return self.db.profile.singleLineChatDisplay end,
                			order = 140
                        },
                	    singleLineTooltipDisplay = {
                            name = L["Single Line for Tooltip"],
                            desc = L["Toggles whether the main and alt information is on one line or separate lines in tooltips."],
                            type = "toggle",
                            set = function(info, val) self.db.profile.singleLineTooltipDisplay = val end,
                            get = function(info) return self.db.profile.singleLineTooltipDisplay end,
                			order = 150
                        },
                    },
                },
                guild = {
				    order = 3,
					name = L["Guild"],
					type = "group",
					args = {
                		displayheaderGuild = {
                			order = 20,
                			type = "header",
                			name = L["Guild Import Options"],
                		},
                	    autoImportGuild = {
                            name = L["Auto Import Guild"],
                            desc = L["Toggles if main/alt data should be automatically imported from guild notes."],
                            type = "toggle",
                            set = function(info, val) self.db.profile.autoGuildImport = val end,
                            get = function(info) return self.db.profile.autoGuildImport end,
                			order = 30
                        },
                	    reportMissingMains = {
                            name = L["Report Missing Mains"],
                            desc = L["Toggles if missing mains should be reported when importing."],
                            type = "toggle",
                            set = function(info, val) self.db.profile.reportMissingMains = val end,
                            get = function(info) return self.db.profile.reportMissingMains end,
                			order = 40
                        },
                		headerLogs = {
                			order = 100,
                			type = "header",
                			name = L["Log Options"],
                		},
                	    reportGuildChanges = {
                            name = L["Report Guild Changes"],
                            desc = L["ReportGuildChanges_OptionDesc"],
                            type = "toggle",
                            width = "double",
                            set = function(info, val) self.db.profile.reportGuildChanges = val end,
                            get = function(info) return self.db.profile.reportGuildChanges end,
                			order = 110
                        },
                        guildLogButton = {
                            name = L["Guild Log"],
                            desc = L["GuildLog_OptionDesc"],
                            type = "execute",
                            width = "normal",
                            func = function()
                            	local optionsFrame = InterfaceOptionsFrame
                                optionsFrame:Hide()
                                self:GuildLogHandler("")
                            end,
                			order = 120
                        },
                		headerExport = {
                			order = 200,
                			type = "header",
                			name = L["Export"],
                		},
                        guildExportButton = {
                            name = L["Guild Export"],
                            desc = L["GuildExport_OptionDesc"],
                            type = "execute",
                            width = "normal",
                            func = function()
                            	local optionsFrame = InterfaceOptionsFrame
                                optionsFrame:Hide()
                                self:GuildExportHandler("")
                            end,
                			order = 210
                        },
                		headerContribs = {
                			order = 300,
                			type = "header",
                			name = L["Contributions"],
                		},
                        guildWeeklyButton = {
                            name = L["Guild Contribution"],
                            desc = L["GuildContribution_OptionDesc"],
                            type = "execute",
                            width = "normal",
                            func = function()
                            	local optionsFrame = InterfaceOptionsFrame
                                optionsFrame:Hide()
                                self:GuildContribHandler("")
                            end,
                			order = 310
                        },
                    },
                },
                friends = {
				    order = 4,
					name = L["Friends"],
					type = "group",
					args = {
                		displayOptions = {
                			order = 100,
                			type = "header",
                			name = L["General Options"],
                		},
                	    reportRemovedFriends = {
                            name = L["Report Removed Friends"],
                            desc = L["ReportRemovedFriends_OptionDesc"],
                            type = "toggle",
                            width = "double",
                            set = function(info, val) self.db.profile.reportRemovedFriends = val end,
                            get = function(info) return self.db.profile.reportRemovedFriends end,
                			order = 110
                        },
            		},
        		},
                ignores = {
				    order = 5,
					name = L["Ignores"],
					type = "group",
					args = {
                		displayOptions = {
                			order = 100,
                			type = "header",
                			name = L["General Options"],
                		},
                	    reportRemovedFriends = {
                            name = L["Report Removed Ignores"],
                            desc = L["ReportRemovedIgnores_OptionDesc"],
                            type = "toggle",
                            width = "double",
                            set = function(info, val) self.db.profile.reportRemovedIgnores = val end,
                            get = function(info) return self.db.profile.reportRemovedIgnores end,
                			order = 110
                        },
            		},
        		},
            }
        }
	    options.args.profile = LibStub("AceDBOptions-3.0"):GetOptionsTable(self.db)
    end

    return options
end

function Alts:ShowOptions()
	InterfaceOptionsFrame_OpenToCategory(self.optionsFrame.Notes)
	InterfaceOptionsFrame_OpenToCategory(self.optionsFrame.Main)
end

function Alts:OnInitialize()
    -- Called when the addon is loaded
    self.db = LibStub("AceDB-3.0"):New("AltsDB", defaults, "Default")
    Mains = ReverseTable(self.db.realm.alts)

    -- Register the options table
    local displayName = GetAddOnMetadata(ADDON_NAME, "Title")
	local options = self:GetOptions()
    LibStub("AceConfigRegistry-3.0"):RegisterOptionsTable(displayName, options)
    self.optionsFrame = {}
    local ACD = LibStub("AceConfigDialog-3.0")
	self.optionsFrame.Main = ACD:AddToBlizOptions(
	    displayName, displayName, nil, "core")
	self.optionsFrame.Notes = ACD:AddToBlizOptions(
	    displayName, L["Notes"], displayName, "notes")
	self.optionsFrame.Guild = ACD:AddToBlizOptions(
	    displayName, L["Guild"], displayName, "guild")
	self.optionsFrame.Guild = ACD:AddToBlizOptions(
	    displayName, L["Friends"], displayName, "friends")
	self.optionsFrame.Guild = ACD:AddToBlizOptions(
	    displayName, L["Ignores"], displayName, "ignores")
	ACD:AddToBlizOptions(
	    displayName, options.args.profile.name, displayName, "profile")

    -- Check that LibAlts is available and has the correct methods
    if LibAlts and LibAlts.RegisterCallback and LibAlts.SetAlt and 
        LibAlts.DeleteAlt and LibAlts.RemoveSource and LibAlts.GetAlts then
        useLibAlts = true
    end

    if useLibAlts == true then
        -- Push the data into LibAlts before registering callbacks
        self:PushLibAltsData()
        -- Register callbacks for LibAlts
        LibAlts.RegisterCallback(self, "LibAlts_SetAlt", "SetAltEvent")
        LibAlts.RegisterCallback(self, "LibAlts_RemoveAlt", "DeleteAltEvent")
        LibAlts.RegisterCallback(self, "LibAlts_RemoveSource", "RemoveSourceEvent")
    end

	self:RegisterChatCommand("alts", "AltsHandler")
	self:RegisterChatCommand("setmain", "SetMainHandler")
	self:RegisterChatCommand("delalt", "DelAltHandler")
	self:RegisterChatCommand("getalts", "GetAltsHandler")
	self:RegisterChatCommand("getmain", "GetMainHandler")
	self:RegisterChatCommand("isalt", "IsAltHandler")
	self:RegisterChatCommand("ismain", "IsMainHandler")
	self:RegisterChatCommand("getallmains", "GetAllMainsHandler")
	self:RegisterChatCommand("guildlog", "GuildLogHandler")
	self:RegisterChatCommand("guildexport", "GuildExportHandler")

	-- Create the LDB launcher
	altsLDB = LDB:NewDataObject("Alts",{
		type = "launcher",
		icon = "Interface\\Icons\\Achievement_Character_Human_Male.blp",
		OnClick = function(clickedframe, button)
    		if button == "RightButton" then
    			local optionsFrame = InterfaceOptionsFrame

    			if optionsFrame:IsVisible() then
    				optionsFrame:Hide()
    			else
    			    self:HideAltsWindow()
    				self:ShowOptions()
    			end
    		elseif button == "LeftButton" then
    			if self:IsVisible() then
    				self:HideAltsWindow()
    			else
        			local optionsFrame = InterfaceOptionsFrame
    			    optionsFrame:Hide()
    				self:AltsHandler("")
    			end
            end
		end,
		OnTooltipShow = function(tooltip)
			if tooltip and tooltip.AddLine then
				tooltip:AddLine(GREEN .. L["Alts"].." "..ADDON_VERSION)
				tooltip:AddLine(YELLOW .. L["Left click"] .. " " .. WHITE
					.. L["to open/close the window"])
				tooltip:AddLine(YELLOW .. L["Right click"] .. " " .. WHITE
					.. L["to open/close the configuration."])
			end
		end
	})
	icon:Register("AltsLDB", altsLDB, self.db.profile.minimap)
	
	playerName = UnitName("player")
end

function Alts:SetMainHandler(input)
	if input and #input > 0 then
		local alt, main = string.match(input, "^(%S+) *(.*)")
		alt = self:TitleCase(alt)
		if main and #main > 0 then
    		main = self:TitleCase(main)

            if useLibAlts == true then
                LibAlts:SetAlt(main, alt)
            else
			    self:SetAlt(main, alt)
		    end

			if self.db.profile.verbose == true then
				local strFormat = L["Set main for %s: %s"]
				self:Print(strFormat:format(main, alt))
			end
		else
		    main = self:GetMain(alt)

            --self:StaticPopupSetMain(alt, main)
		    setMainFrame.charname:SetText(alt)
	        setMainFrame.editbox:SetText(main or "")
		    setMainFrame:Show()
			--self:Print(L["Usage: /setmain <alt> <main>"])
		end
	else
		self:Print(L["Usage: /setmain <alt> <main>"])
	end	
end

function Alts:StaticPopupSetMain(alt, main)
    StaticPopupDialogs["ALTS_SET_MAIN"] = StaticPopupDialogs["ALTS_SET_MAIN"] or {
        text = "Set the main for %s",
        maintext = "",
        button1 = OKAY,
        button2 = CANCEL,
        hasEditBox = true,
        hasWideEditBox = true,
        enterClicksFirstButton = true,
        OnShow = function(this, data)
            this.wideEditBox:SetText(StaticPopupDialogs["ALTS_SET_MAIN"].maintext or "")
            this.wideEditBox:SetFocus()
            this.wideEditBox:HighlightText()
        end,
        OnAccept = function(this)
            self:SaveMainName(alt, this.wideEditBox:GetText())
        end,
        EditBoxOnEscapePressed = function(this) this:GetParent():Hide(); end,
        EditBoxOnEnterPressed = function(this)
            self:SaveMainName(alt, this:GetText())
            this:GetParent():Hide()
        end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true
    }

    StaticPopupDialogs["ALTS_SET_MAIN"].maintext = main
    StaticPopup_Show("ALTS_SET_MAIN", alt)
end

function Alts:DelAltHandler(input)
	if input and #input > 0 then
		local alt, main = string.match(input, "^(%S+) *(.*)")
		alt = self:TitleCase(alt)
		if main and #main > 0 then
    		main = self:TitleCase(main)

            if useLibAlts == true then
                LibAlts:DeleteAlt(main, alt)
            else
			    self:DeleteAlt(main, alt)
			end

			if self.db.profile.verbose == true then
				local strFormat = L["Deleted alt %s for %s"]
				self:Print(strFormat:format(alt, main))
			end
		else
			self:Print(L["Usage: /delalt <alt> <main>"])
		end
	else
		self:Print(L["Usage: /delalt <alt> <main>"])
	end	
end

function Alts:IsMainHandler(input)
    local outputFmt = "%s is %sa main %s"
    local sourceFmt = "(source: %s)"

	if input and #input > 0 then
		local name, source = string.match(input, "^(%S+) *(.*)")
        local isMain
		name = self:TitleCase(name)

        local sourceUsed = ""
		if source and #source > 0 then
            isMain = LibAlts:IsMainForSource(name, source)
            sourceUsed = sourceFmt:format(source)
        else
            isMain = LibAlts:IsMain(name)
        end

        local result = ""
        if not isMain then result = "not " end

        self:Print(outputFmt:format(name, result, sourceUsed))
    else
        self:Print("Usage: /ismain name <source>")
    end
end

function Alts:IsAltHandler(input)
    local outputFmt = "%s is %san alt %s"
    local sourceFmt = "(source: %s)"

	if input and #input > 0 then
		local name, source = string.match(input, "^(%S+) *(.*)")
        local isAlt
		name = self:TitleCase(name)

        local sourceUsed = ""
		if source and #source > 0 then
            isAlt = LibAlts:IsAltForSource(name, source)
            sourceUsed = sourceFmt:format(source)
        else
            isAlt = LibAlts:IsAlt(name)
        end

        local result = ""
        if not isAlt then result = "not " end

        self:Print(outputFmt:format(name, result, sourceUsed))
    else
        self:Print("Usage: /isalt name <source>")
    end
end

function Alts:GetAllMainsHandler(input)
    local source = nil
    local sourceName = "nil"
	if input and #input > 0 then
	    source = input
        sourceName = source
    end

    local mains = {}
    LibAlts:GetAllMainsForSource(mains, source)

    if mains then
        for k, v in pairs(mains) do
            self:Print(v)
        end
        local resultFmt = "Found %d mains for source '%s'."
        self:Print(resultFmt:format(#mains, sourceName))
    end
end

function Alts:GetAltsHandler(input)
	if input and #input > 0 then
		local main = self:TitleCase(input)
		local alts = { self:GetAlts(main) }
		if alts and #alts > 0 then
            local altList = strjoin(", ", unpack(alts))
            local strFormat = L["Alts for %s: %s"]
		    self:Print(strFormat:format(main, altList))
		else
		    self:Print(L["No alts found for "]..main)
		end
	else
		self:Print(L["Usage: /getalts <main>"])
	end	
end

function Alts:GetMainHandler(input)
	if input and #input > 0 then
		local alt = self:TitleCase(input)
		local main
		if useLibAlts then
		    main = LibAlts:GetMain(alt)
		else
		    main = self:GetMain(alt)
	    end
		if main and #main > 0 then
            local strFormat = L["Main for %s: %s"]
		    self:Print(strFormat:format(alt, main))
		else
		    self:Print(L["No main found for "]..alt)
		end
	else
		self:Print(L["Usage: /getmain <alt>"])
	end	
end

function Alts:AddAltHandler(main)
	if main and #main > 0 then
		main = self:TitleCase(main)

        --self:StaticPopupSetMain(alt, main)
	    addAltFrame.charname:SetText(main)
        --addAltFrame.editbox:SetText(main or "")
	    addAltFrame:Show()
	end
end

local GuildLogFrame = nil
function Alts:ShowGuildLogFrame()
    if GuildLogFrame then return end

	local frame = AGU:Create("Frame")
	frame:SetTitle(L["Guild Log"])
	frame:SetWidth(650)
	frame:SetHeight(450)
    frame:SetLayout("Flow")
	frame:SetCallback("OnClose", function(widget)
		widget:ReleaseChildren()
		widget:Release()
		GuildLogFrame = nil
	end)

    GuildLogFrame = frame

    local limit = AGU:Create("CheckBox")
    limit:SetLabel("Limit to 50 most recent entries")
    limit:SetValue(true)
    limit:SetFullWidth(true)
    limit:SetCallback("OnValueChanged",
        function(widget, event, value)
            GuildLogFrame.update(value)
        end
    )
    frame:AddChild(limit)

    local spacer = AGU:Create("Label")
    spacer:SetFullWidth(true)
    spacer:SetHeight(50)
    spacer:SetText(" ")
    frame:AddChild(spacer)

    local simple = AGU:Create("SimpleGroup")
    simple:SetLayout("Fill")
    simple:SetFullHeight(true)
    simple:SetFullWidth(true)
    frame:AddChild(simple)

    local scroll = AGU:Create("ScrollFrame")
    simple:AddChild(scroll)
    GuildLogFrame.scroll = scroll

    GuildLogFrame.update = function(value)
        local guildName = GetGuildInfo("player")
        if not guildName then return end
        if not self.db.realm.guildLog[guildName] then return end

        scroll:ReleaseChildren()
        scroll:PauseLayout()
        local count = 0
        local entries = #self.db.realm.guildLog[guildName]
        for i = entries, 1, -1 do
            local text = self.db.realm.guildLog[guildName][i]
            if text then
                local label = AGU:Create("Label")
                label:SetText(text)
                label:SetFullWidth(true)
                scroll:AddChild(label)
                count = count + 1
            end
            
            if value == true and count == 50 then break end
        end
        scroll:ResumeLayout()
        scroll:DoLayout()
        local statusFmt = L["Entries_Displayed"]
        frame:SetStatusText(statusFmt:format(count, entries))
    end
    
    GuildLogFrame.update(true)
end

local GuildExportFrame = nil
function Alts:ShowGuildExportFrame()
	-- Request an update on the guild roster
	GuildRoster()

    if GuildExportFrame then return end

	local frame = AGU:Create("Frame")
	frame:SetTitle(L["Guild Export"])
	frame:SetWidth(650)
	frame:SetHeight(550)
    frame:SetLayout("Flow")
	frame:SetCallback("OnClose", function(widget)
		widget:ReleaseChildren()
		widget:Release()
		GuildExportFrame = nil
	end)

    GuildExportFrame = frame

    local multiline = AGU:Create("MultiLineEditBox")
    multiline:SetLabel(L["GuildExport_ExportLabel"])
    multiline:SetNumLines(10)
    multiline:SetMaxLetters(0)
    multiline:SetFullWidth(true)
    multiline:DisableButton(true)
    frame:AddChild(multiline)
    frame.multiline = multiline

    local fieldsHeading =  AGU:Create("Heading")
    fieldsHeading:SetText("Fields to Export")
    fieldsHeading:SetFullWidth(true)
    frame:AddChild(fieldsHeading)

    local nameOption = AGU:Create("CheckBox")
    nameOption:SetLabel(L["Name"])
    nameOption:SetCallback("OnValueChanged", 
        function(widget, event, value)
            self.db.profile.exportUseName = value
        end
    )
    nameOption:SetValue(self.db.profile.exportUseName)
    frame:AddChild(nameOption)

    local levelOption = AGU:Create("CheckBox")
    levelOption:SetLabel(L["Level"])
    levelOption:SetCallback("OnValueChanged", 
        function(widget, event, value)
            self.db.profile.exportUseLevel = value
        end
    )
    levelOption:SetValue(self.db.profile.exportUseLevel)
    frame:AddChild(levelOption)

    local rankOption = AGU:Create("CheckBox")
    rankOption:SetLabel(L["Rank"])
    rankOption:SetCallback("OnValueChanged", 
        function(widget, event, value)
            self.db.profile.exportUseRank = value
        end
    )
    rankOption:SetValue(self.db.profile.exportUseRank)
    frame:AddChild(rankOption)

    local classOption = AGU:Create("CheckBox")
    classOption:SetLabel(L["Class"])
    classOption:SetCallback("OnValueChanged", 
        function(widget, event, value)
            self.db.profile.exportUseClass = value
        end
    )
    classOption:SetValue(self.db.profile.exportUseClass)
    frame:AddChild(classOption)

    local publicNoteOption = AGU:Create("CheckBox")
    publicNoteOption:SetLabel(L["Public Note"])
    publicNoteOption:SetCallback("OnValueChanged", 
        function(widget, event, value)
            self.db.profile.exportUsePublicNote = value
        end
    )
    publicNoteOption:SetValue(self.db.profile.exportUsePublicNote)
    frame:AddChild(publicNoteOption)

    local officerNoteOption = AGU:Create("CheckBox")
    officerNoteOption:SetLabel(L["Officer Note"])
    officerNoteOption:SetCallback("OnValueChanged", 
        function(widget, event, value)
            self.db.profile.exportUseOfficerNote = value
        end
    )
    officerNoteOption:SetValue(self.db.profile.exportUseOfficerNote)
    frame:AddChild(officerNoteOption)

    local lastOnlineOption = AGU:Create("CheckBox")
    lastOnlineOption:SetLabel(L["Last Online"])
    lastOnlineOption:SetCallback("OnValueChanged", 
        function(widget, event, value)
            self.db.profile.exportUseLastOnline = value
        end
    )
    lastOnlineOption:SetValue(self.db.profile.exportUseLastOnline)
    frame:AddChild(lastOnlineOption)

    local achvPointsOption = AGU:Create("CheckBox")
    achvPointsOption:SetLabel(L["Achievement Points"])
    achvPointsOption:SetCallback("OnValueChanged", 
        function(widget, event, value)
            self.db.profile.exportUseAchvPoints = value
        end
    )
    achvPointsOption:SetValue(self.db.profile.exportUseAchvPoints)
    frame:AddChild(achvPointsOption)

    local weeklyXPOption = AGU:Create("CheckBox")
    weeklyXPOption:SetLabel(L["Weekly XP"])
    weeklyXPOption:SetCallback("OnValueChanged", 
        function(widget, event, value)
            self.db.profile.exportUseWeeklyXP = value
        end
    )
    weeklyXPOption:SetValue(self.db.profile.exportUseWeeklyXP)
    frame:AddChild(weeklyXPOption)

    local totalXPOption = AGU:Create("CheckBox")
    totalXPOption:SetLabel(L["Total XP"])
    totalXPOption:SetCallback("OnValueChanged", 
        function(widget, event, value)
            self.db.profile.exportUseTotalXP = value
        end
    )
    totalXPOption:SetValue(self.db.profile.exportUseTotalXP)
    frame:AddChild(totalXPOption)

    local altsOption = AGU:Create("CheckBox")
    altsOption:SetLabel(L["Alts"])
    altsOption:SetCallback("OnValueChanged", 
        function(widget, event, value)
            self.db.profile.exportUseAlts = value
        end
    )
    altsOption:SetValue(self.db.profile.exportUseAlts)
    frame:AddChild(altsOption)

    local optionsHeading = AGU:Create("Heading")
    optionsHeading:SetText("Options")
    optionsHeading:SetFullWidth(true)
    frame:AddChild(optionsHeading)

    local escapeOption = AGU:Create("CheckBox")
    escapeOption:SetLabel(L["GuildExport_Escape"])
    escapeOption:SetCallback("OnValueChanged", 
        function(widget, event, value)
            self.db.profile.exportEscape = value
        end
    )
    escapeOption:SetValue(self.db.profile.exportEscape)
    frame:AddChild(escapeOption)

    local onlyMains = AGU:Create("CheckBox")
    onlyMains:SetLabel(L["GuildExport_OnlyMains"])
    onlyMains:SetCallback("OnValueChanged", 
        function(widget, event, value)
            self.db.profile.exportOnlyMains = value
        end
    )
    onlyMains:SetValue(self.db.profile.exportOnlyMains)
    frame:AddChild(onlyMains)

    local guildAlts = AGU:Create("CheckBox")
    guildAlts:SetLabel(L["GuildExport_OnlyGuildAlts"])
    guildAlts:SetCallback("OnValueChanged", 
        function(widget, event, value)
            self.db.profile.exportOnlyGuildAlts = value
        end
    )
    guildAlts:SetValue(self.db.profile.exportOnlyGuildAlts)
    frame:AddChild(guildAlts)

    local spacer = AGU:Create("Label")
    spacer:SetText(" ")
    spacer:SetFullWidth(true)
    frame:AddChild(spacer)

    local exportButton = AGU:Create("Button")
    exportButton:SetText(L["Export"])
    exportButton:SetCallback("OnClick",
        function(widget)
            local numChars, guildExportText = Alts:GenerateGuildExport(
                self.db.profile.exportUseName,
                self.db.profile.exportUseLevel,
                self.db.profile.exportUseRank,
                self.db.profile.exportUseClass,
                self.db.profile.exportUsePublicNote,
                self.db.profile.exportUseOfficerNote,
                self.db.profile.exportUseLastOnline,
                self.db.profile.exportUseAchvPoints,
                self.db.profile.exportUseWeeklyXP,
                self.db.profile.exportUseTotalXP,
                self.db.profile.exportUseAlts,
                self.db.profile.exportEscape
            )
			local exportStatusFmt = L["GuildExport_StatusFormat"]
			local clipboardCopy = L["ClipboardCopy_Default"]
			if IsMacClient() then
				clipboardCopy = L["ClipboardCopy_Mac"]
			end
			frame:SetStatusText(
				exportStatusFmt:format(numChars) .. " " .. clipboardCopy)
            frame.multiline:SetText(guildExportText)
			frame.multiline:SetFocus()
        end)
    frame:AddChild(exportButton)
end

function Alts:CreateGuildContribExport(period)
    local table
    local totalXP = 0
    if peroid == "Weekly" then
        table = GuildXP.weekly.sorted
        totalXP = GuildXP.weekly.totalXP
    else
        table = GuildXP.total.sorted
        totalXP = GuildXP.total.totalXP
    end

    local strFmt = "%s,%d"
    local line
    local buffer = {}
    for i, data in ipairs(table) do
        local name = data[1]
        local xp = data[2]
        line = strFmt:format(name,xp)
        buffer[i] = line
    end
    tinsert(buffer, "")
    
    return tconcat(buffer, "\n")
end

function Alts:CreateGuildWeeklyContribExport()
    return Alts:CreateGuildContribExport("Weekly")
end

function Alts:CreateGuildTotalContribExport()
    return Alts:CreateGuildContribExport("Total")
end

local ContribsFrame = nil
function Alts:ShowContribFrame()
	-- Request an update on the guild roster
	GuildRoster()

    if ContribsFrame then return end

	local frame = AGU:Create("Frame")
	frame:SetTitle(L["Guild Contributions By Main"])
	frame:SetWidth(400)
	frame:SetHeight(350)
    frame:SetLayout("Flow")
	frame:SetCallback("OnClose", function(widget)
		widget:ReleaseChildren()
		widget:Release()
		ContribsFrame = nil
	end)

    ContribsFrame = frame
    ContribsFrame.currentPeriod = "Total"

	local periodDropdown = AGU:Create("Dropdown")
	periodDropdown:SetLabel("Period")
	periodDropdown.list = {}
	periodDropdown:AddItem("Weekly", L["Weekly"])
	periodDropdown:AddItem("Total", L["Total"])
	periodDropdown:SetValue("Total")
	periodDropdown:SetWidth(150)
	periodDropdown:SetCallback("OnValueChanged",
        function(widget, event, value)
            ContribsFrame.currentPeriod = value
            ContribsFrame.update(value)
        end
	)
	frame:AddChild(periodDropdown)

    local spacer = AGU:Create("Label")
    spacer:SetText(" ")
    spacer:SetWidth(50)
    frame:AddChild(spacer)

	local exportButton = AGU:Create("Button")
	exportButton:SetText(L["Export"])
	exportButton:SetWidth(100)
	exportButton:SetPoint("RIGHT", -5, 0)
	exportButton:SetCallback("OnClick",
        function(widget, event, value)
            ContribsFrame.frame:Hide()
            if ContribsFrame and ContribsFrame.currentPeriod and 
                ContribsFrame.currentPeriod == "Weekly" then
                Alts:ShowExportFrame(Alts.CreateGuildWeeklyContribExport)
            else
                Alts:ShowExportFrame(Alts.CreateGuildTotalContribExport)
            end
        end
	)
    frame:AddChild(exportButton)

    local spacer = AGU:Create("Label")
    spacer:SetFullWidth(true)
    spacer:SetHeight(50)
    spacer:SetText(" ")
    frame:AddChild(spacer)

    local header = AGU:Create("SimpleGroup")
    header:SetLayout("Flow")
    header:SetFullWidth(true)
    frame:AddChild(header)

    local nameHeader = AGU:Create("Label")
    nameHeader:SetText(L["Main Name"])
    nameHeader:SetRelativeWidth(0.5)
    header:AddChild(nameHeader)
    local xpHeader = AGU:Create("Label")
    xpHeader:SetText(L["XP"])
    xpHeader:SetRelativeWidth(0.3)
    xpHeader.label:SetJustifyH("RIGHT")
    xpHeader:SetCallback("OnRelease",
        function(widget)
            widget.label:SetJustifyH("LEFT")
        end
    )
    header:AddChild(xpHeader)
    local percHeader = AGU:Create("Label")
    percHeader:SetText(L["Percent"])
    percHeader:SetRelativeWidth(0.2)
    percHeader.label:SetJustifyH("RIGHT")
    percHeader:SetCallback("OnRelease",
        function(widget)
            widget.label:SetJustifyH("LEFT")
        end
    )
    header:AddChild(percHeader)

    local line = AGU:Create("Heading")
    line:SetFullWidth(true)
    line:SetText("")
    frame:AddChild(line)

    local simple = AGU:Create("SimpleGroup")
    simple:SetLayout("Fill")
    simple:SetFullHeight(true)
    simple:SetFullWidth(true)
    frame:AddChild(simple)

    local scroll = AGU:Create("ScrollFrame")
    scroll:SetLayout("Flow")
    simple:AddChild(scroll)
    ContribsFrame.scroll = scroll

    ContribsFrame.update = function(value)
        self:GuildContrib()
        scroll:ReleaseChildren()
        scroll:PauseLayout()
        
        local table
        if value == "Weekly" then
            table = GuildXP.weekly.sorted
            totalXP = GuildXP.weekly.totalXP
        else
            table = GuildXP.total.sorted
            totalXP = GuildXP.total.totalXP
        end

        for i, data in ipairs(table) do
            local name = data[1]
            local xp = data[2]

            local nameField = AGU:Create("Label")
            nameField:SetText(name)
            nameField:SetRelativeWidth(0.5)
            scroll:AddChild(nameField)
            local xpField = AGU:Create("Label")
            xpField:SetText(xp)
            xpField:SetRelativeWidth(0.3)
            xpField.label:SetJustifyH("RIGHT")
            xpField:SetCallback("OnRelease",
                function(widget)
                    widget.label:SetJustifyH("LEFT")
                end
            )
            scroll:AddChild(xpField)
            local percFmt = "%.1f%%"
            local percField = AGU:Create("Label")
            local percent = 0
            if totalXP > 0 then
                percent = xp/totalXP*100
            end
            percField:SetText(percFmt:format(percent))
            percField:SetRelativeWidth(0.2)
            percField.label:SetJustifyH("RIGHT")
            percField:SetCallback("OnRelease",
                function(widget)
                    widget.label:SetJustifyH("LEFT")
                end
            )
            scroll:AddChild(percField)
        end
        scroll:ResumeLayout()
        scroll:DoLayout()
        local strFmt = "%s: %d"
        frame:SetStatusText(strFmt:format(L["Total XP"], totalXP))
    end
    
    ContribsFrame.update("Total")
end

local ExportFrame = nil
function Alts:ShowExportFrame(exportFunc)
    if not exportFunc or type(exportFunc) ~= "function" then return end 

    if ExportFrame then return end

    local exportData = exportFunc()
    if not exportData then return end

	local frame = AGU:Create("Frame")
	frame:SetTitle(L["Export"])
	frame:SetWidth(450)
	frame:SetHeight(350)
    frame:SetLayout("Flow")
	frame:SetCallback("OnClose", function(widget)
		widget:ReleaseChildren()
		widget:Release()
		ExportFrame = nil
	end)

    ExportFrame = frame

    local multiline = AGU:Create("MultiLineEditBox")
    multiline:SetLabel(L["GuildExport_ExportLabel"])
    multiline:SetNumLines(13)
    multiline:SetMaxLetters(0)
    multiline:SetFullWidth(true)
    multiline:SetFullHeight(true)
    multiline:SetText(exportData)
    multiline:DisableButton(true)
    frame:AddChild(multiline)
    frame.multiline = multiline
end

function Alts:CreateAddAltFrame()
	local addalt = CreateFrame("Frame", "Alts_AddAltWindow", UIParent)
	addalt:SetFrameStrata("DIALOG")
	addalt:SetToplevel(true)
	addalt:SetWidth(400)
	addalt:SetHeight(200)
	addalt:SetPoint("CENTER", UIParent)
	addalt:SetBackdrop(
		{bgFile="Interface\\ChatFrame\\ChatFrameBackground", 
	    edgeFile="Interface\\DialogFrame\\UI-DialogBox-Border", tile=true,
		tileSize=32, edgeSize=32, insets={left=11, right=12, top=12, bottom=11}})
	addalt:SetBackdropColor(0,0,0,1)
		
	local editbox = CreateFrame("EditBox", nil, addalt, "InputBoxTemplate")
	editbox:SetFontObject(ChatFontNormal)
	editbox:SetWidth(300)
	editbox:SetHeight(35)
	editbox:SetPoint("CENTER", addalt)
	editbox:SetScript("OnShow", function(this) this:SetFocus() end)
	editbox:SetScript("OnEnterPressed",
	    function(this)
	        local frame = this:GetParent()
	        local main = frame.charname:GetText()
	        self:AddAltName(main,frame.editbox:GetText())
	        frame:Hide()
	        self:EditAltsHandler(main)
	    end)
	editbox:SetScript("OnEscapePressed",
	    function(this)
	        this:SetText("")
	        this:GetParent():Hide()
	    end)

	local savebutton = CreateFrame("Button", nil, addalt, "UIPanelButtonTemplate")
	savebutton:SetText(L["Save"])
	savebutton:SetWidth(100)
	savebutton:SetHeight(20)
	savebutton:SetPoint("BOTTOM", addalt, "BOTTOM", -60, 20)
	savebutton:SetScript("OnClick", 
	    function(this)
	        local frame = this:GetParent()
	        local main = frame.charname:GetText()
	        self:AddAltName(main,frame.editbox:GetText())
	        frame:Hide()
	        self:EditAltsHandler(main)
	    end)

	local cancelbutton = CreateFrame("Button", nil, addalt, "UIPanelButtonTemplate")
	cancelbutton:SetText(L["Cancel"])
	cancelbutton:SetWidth(100)
	cancelbutton:SetHeight(20)
	cancelbutton:SetPoint("BOTTOM", addalt, "BOTTOM", 60, 20)
	cancelbutton:SetScript("OnClick", 
	    function(this)
	        this:GetParent():Hide()
	        editAltsFrame:Show()
	    end)

	local headertext = addalt:CreateFontString("Alts_HeaderText", addalt, "GameFontNormalLarge")
	headertext:SetPoint("TOP", addalt, "TOP", 0, -20)
	headertext:SetText(L["Add Alt"])

	local charname = addalt:CreateFontString("Alts_CharName", addalt, "GameFontNormal")
	charname:SetPoint("BOTTOM", headertext, "BOTTOM", 0, -40)
	charname:SetFont(charname:GetFont(), 14)
	charname:SetTextColor(1.0,1.0,1.0,1)

	addalt.charname = charname
	addalt.editbox = editbox

    addalt:SetMovable()
    addalt:RegisterForDrag("LeftButton")
    addalt:SetScript("OnDragStart",
        function(this,button)
        	this:StartMoving()
        end)
    addalt:SetScript("OnDragStop",
        function(this)
            this:StopMovingOrSizing()
        end)
    addalt:EnableMouse(true)

	addalt:Hide()

	return addalt
end

function Alts:CreateAddMainFrame()
	local addmain = CreateFrame("Frame", "Alts_AddMainWindow", UIParent)
	addmain:SetFrameStrata("DIALOG")
	addmain:SetToplevel(true)
	addmain:SetWidth(400)
	addmain:SetHeight(200)
	addmain:SetPoint("CENTER", UIParent)
	addmain:SetBackdrop(
		{bgFile="Interface\\ChatFrame\\ChatFrameBackground", 
	    edgeFile="Interface\\DialogFrame\\UI-DialogBox-Border", tile=true,
		tileSize=32, edgeSize=32, insets={left=11, right=12, top=12, bottom=11}})
	addmain:SetBackdropColor(0,0,0,1)

	local headertext = addmain:CreateFontString("Alts_AddMain_HeaderText", addmain, "GameFontNormalLarge")
	headertext:SetPoint("TOP", addmain, "TOP", 0, -20)
	headertext:SetText(L["Add Main"])

	local mainlabel = addmain:CreateFontString("Alts_AddMain_MainLabel", addmain, "GameFontNormal")
	mainlabel:SetText(L["Main: "])
	mainlabel:SetPoint("TOP", headertext, "BOTTOM", 0, -30)
	mainlabel:SetPoint("LEFT", addmain, "LEFT", 20, 0)

	local mainname = CreateFrame("EditBox", "Alts_AddMain_MainName", addmain, "InputBoxTemplate")
	mainname:SetFontObject(ChatFontNormal)
	mainname:SetWidth(150)
	mainname:SetHeight(35)
	mainname:SetPoint("LEFT", mainlabel, "RIGHT", 30, 0)
	mainname:SetScript("OnShow", function(this) this:SetFocus() end)
	mainname:SetScript("OnEnterPressed",
	    function(this)
	        local frame = this:GetParent()
	        local main = frame.mainname:GetText()
	        local alt = frame.altname:GetText()
	        if main and alt and #main > 0 and #alt > 0 then
    	        self:AddMainName(main,alt)
    	        frame:Hide()
                self:UpdateMainsTable()
                altsFrame.table:SortData()
                altsFrame:Show()
            end
	    end)
	mainname:SetScript("OnEscapePressed",
	    function(this)
	        this:GetParent():Hide()
	    end)

	local altlabel = addmain:CreateFontString("Alts_AddMain_AltLabel", addmain, "GameFontNormal")
	altlabel:SetText(L["Alt: "])
	altlabel:SetPoint("TOPLEFT", mainlabel, "BOTTOMLEFT", 0, -30)

	local altname = CreateFrame("EditBox", "Alts_AddMain_AltName", addmain, "InputBoxTemplate")
	altname:SetFontObject(ChatFontNormal)
	altname:SetWidth(150)
	altname:SetHeight(35)
	altname:SetPoint("LEFT", mainname, "LEFT")
	altname:SetPoint("TOP", altlabel, "TOP")
	altname:SetScript("OnEnterPressed",
	    function(this)
	        local frame = this:GetParent()
	        local main = frame.mainname:GetText()
	        local alt = frame.altname:GetText()
	        if main and alt and #main > 0 and #alt > 0 then
    	        self:AddMainName(main,alt)
    	        frame:Hide()
                self:UpdateMainsTable()
                altsFrame.table:SortData()
                altsFrame:Show()
            end
	    end)
	altname:SetScript("OnEscapePressed",
	    function(this)
	        this:GetParent():Hide()
	    end)

	local savebutton = CreateFrame("Button", nil, addmain, "UIPanelButtonTemplate")
	savebutton:SetText(L["Save"])
	savebutton:SetWidth(100)
	savebutton:SetHeight(20)
	savebutton:SetPoint("BOTTOM", addmain, "BOTTOM", -60, 20)
	savebutton:SetScript("OnClick", 
	    function(this)
	        local frame = this:GetParent()
	        local main = frame.mainname:GetText()
	        local alt = frame.altname:GetText()
	        if main and alt and #main > 0 and #alt > 0 then
    	        self:AddMainName(main,alt)
    	        frame:Hide()
                self:UpdateMainsTable()
                altsFrame.table:SortData()
                altsFrame:Show()
            end
	    end)

	local cancelbutton = CreateFrame("Button", nil, addmain, "UIPanelButtonTemplate")
	cancelbutton:SetText(L["Cancel"])
	cancelbutton:SetWidth(100)
	cancelbutton:SetHeight(20)
	cancelbutton:SetPoint("BOTTOM", addmain, "BOTTOM", 60, 20)
	cancelbutton:SetScript("OnClick", 
	    function(this)
	        this:GetParent():Hide()
	        altsFrame:Show()
	    end)

	addmain.mainname = mainname
	addmain.altname = altname

    addmain:SetMovable()
    addmain:RegisterForDrag("LeftButton")
    addmain:SetScript("OnDragStart",
        function(this,button)
        	this:StartMoving()
        end)
    addmain:SetScript("OnDragStop",
        function(this)
            this:StopMovingOrSizing()
        end)
    addmain:EnableMouse(true)

	addmain:Hide()

	return addmain
end

function Alts:CreateContribFrame()
	local window = CreateFrame("Frame", "Alts_ContribWindow", UIParent)
	window:SetFrameStrata("DIALOG")
	window:SetToplevel(true)
	window:SetWidth(430)
	window:SetHeight(370)
	if self.db.profile.remember_contrib_pos then
        window:SetPoint("CENTER", UIParent, "CENTER",
            self.db.profile.contrib_window_x, self.db.profile.contrib_window_y)
    else
	    window:SetPoint("CENTER", UIParent)
    end
	window:SetBackdrop({bgFile="Interface\\DialogFrame\\UI-DialogBox-Background", 
	    edgeFile="Interface\\DialogFrame\\UI-DialogBox-Border", tile=true,
		tileSize=32, edgeSize=32, insets={left=11, right=12, top=12, bottom=11}})

	local cols = {}
	cols[1] = {
		["name"] = L["Main Name"],
		["width"] = 180,
		["align"] = "LEFT",
		["color"] = {
			["r"] = 1.0,
			["g"] = 1.0,
			["b"] = 1.0,
			["a"] = 1.0
		},
		["colorargs"] = nil,
		["bgcolor"] = {
			["r"] = 0.0,
			["g"] = 0.0,
			["b"] = 0.0,
			["a"] = 1.0
		},
		["DoCellUpdate"] = nil,
	}
	cols[2] = {
		["name"] = L["Experience"],
		["width"] = 150,
		["align"] = "RIGHT",
		["color"] = {
			["r"] = 1.0,
			["g"] = 1.0,
			["b"] = 1.0,
			["a"] = 1.0
		},
		["colorargs"] = nil,
		["bgcolor"] = {
			["r"] = 0.0,
			["g"] = 0.0,
			["b"] = 0.0,
			["a"] = 1.0
		},
		["defaultsort"] = "asc",
		["sort"] = "asc",
		["DoCellUpdate"] = nil,
	}

	local table = ScrollingTable:CreateST(cols, 15, nil, nil, window);

	local headertext = window:CreateFontString("Alts_Contrib_HeaderText", window, "GameFontNormalLarge")
	headertext:SetPoint("TOP", window, "TOP", 0, -20)
	headertext:SetText(L["Guild Contribution"])

	table.frame:SetPoint("TOP", headertext, "BOTTOM", 0, -40)
	table.frame:SetPoint("LEFT", window, "LEFT", 40, 0)

	local closebutton = CreateFrame("Button", nil, window, "UIPanelButtonTemplate")
	closebutton:SetText(L["Close"])
	closebutton:SetWidth(90)
	closebutton:SetHeight(20)
	closebutton:SetPoint("BOTTOM", window, "BOTTOM", 0, 20)
	closebutton:SetScript("OnClick", function(this) this:GetParent():Hide(); end)

	window.table = table

    table:RegisterEvents({
		["OnEnter"] = function (rowFrame, cellFrame, data, cols, row, realrow, column, table, ...)
			return true;
		end, 
		["OnLeave"] = function(rowFrame, cellFrame, data, cols, row, realrow, column, table, ...)
			return true;
		end,
    })

	table:EnableSelection(true)
	table:SetData(GuildXP.weekly.sorted, true)

    window.lock = self.db.profile.lock_contrib_window

    window:SetMovable()
    window:RegisterForDrag("LeftButton")
    window:SetScript("OnDragStart",
        function(self,button)
			if not self.lock then
            	self:StartMoving()
			end
        end)
    window:SetScript("OnDragStop",
        function(self)
            self:StopMovingOrSizing()
			if Alts.db.profile.remember_contrib_pos then
    			local scale = self:GetEffectiveScale() / UIParent:GetEffectiveScale()
    			local x, y = self:GetCenter()
    			x, y = x * scale, y * scale
    			x = x - GetScreenWidth()/2
    			y = y - GetScreenHeight()/2
    			x = x / self:GetScale()
    			y = y / self:GetScale()
    			Alts.db.profile.contrib_window_x, 
    			    Alts.db.profile.contrib_window_y = x, y
    			self:SetUserPlaced(false);
            end
        end)
    window:EnableMouse(true)

	window:Hide()
	
	return window
end

function Alts:CreateAltsFrame()
	local altswindow = CreateFrame("Frame", "Alts_AltsWindow", UIParent)
	altswindow:SetFrameStrata("DIALOG")
	altswindow:SetToplevel(true)
	altswindow:SetWidth(630)
	altswindow:SetHeight(430)
	if self.db.profile.remember_main_pos then
        altswindow:SetPoint("CENTER", UIParent, "CENTER",
            self.db.profile.main_window_x, self.db.profile.main_window_y)
    else
	    altswindow:SetPoint("CENTER", UIParent)
    end
	altswindow:SetBackdrop({bgFile="Interface\\DialogFrame\\UI-DialogBox-Background", 
	    edgeFile="Interface\\DialogFrame\\UI-DialogBox-Border", tile=true,
		tileSize=32, edgeSize=32, insets={left=11, right=12, top=12, bottom=11}})

	local cols = {}
	cols[1] = {
		["name"] = L["Main Name"],
		["width"] = 150,
		["align"] = "LEFT",
		["color"] = {
			["r"] = 1.0,
			["g"] = 1.0,
			["b"] = 1.0,
			["a"] = 1.0
		},
		["colorargs"] = nil,
		["bgcolor"] = {
			["r"] = 0.0,
			["g"] = 0.0,
			["b"] = 0.0,
			["a"] = 1.0
		},
		["defaultsort"] = "dsc",
		["sort"] = "dsc",
		["DoCellUpdate"] = nil,
	}
	cols[2] = {
		["name"] = L["Alts"],
		["width"] = 400,
		["align"] = "LEFT",
		["color"] = {
			["r"] = 1.0,
			["g"] = 1.0,
			["b"] = 1.0,
			["a"] = 1.0
		},
		["colorargs"] = nil,
		["bgcolor"] = {
			["r"] = 0.0,
			["g"] = 0.0,
			["b"] = 0.0,
			["a"] = 1.0
		},
		["DoCellUpdate"] = nil,
	}

	local table = ScrollingTable:CreateST(cols, 15, nil, nil, altswindow);

	local headertext = altswindow:CreateFontString("Alts_Notes_HeaderText", altswindow, "GameFontNormalLarge")
	headertext:SetPoint("TOP", altswindow, "TOP", 0, -20)
	headertext:SetText(L["Alts"])

	local searchterm = CreateFrame("EditBox", nil, altswindow, "InputBoxTemplate")
	searchterm:SetFontObject(ChatFontNormal)
	searchterm:SetWidth(300)
	searchterm:SetHeight(35)
	searchterm:SetPoint("TOPLEFT", altswindow, "TOPLEFT", 25, -50)
	searchterm:SetScript("OnShow", function(this) searchterm:SetFocus() end)
	searchterm:SetScript("OnEnterPressed", function(this) this:GetParent().table:SortData() end)
	searchterm:SetScript("OnEscapePressed", function(this) this:SetText(""); this:GetParent():Hide(); end)

	table.frame:SetPoint("TOP", searchterm, "BOTTOM", 0, -20)
	table.frame:SetPoint("LEFT", altswindow, "LEFT", 20, 0)

	local searchbutton = CreateFrame("Button", nil, altswindow, "UIPanelButtonTemplate")
	searchbutton:SetText(L["Search"])
	searchbutton:SetWidth(100)
	searchbutton:SetHeight(20)
	searchbutton:SetPoint("LEFT", searchterm, "RIGHT", 10, 0)
	searchbutton:SetScript("OnClick", function(this) this:GetParent().table:SortData() end)

	local clearbutton = CreateFrame("Button", nil, altswindow, "UIPanelButtonTemplate")
	clearbutton:SetText(L["Clear"])
	clearbutton:SetWidth(100)
	clearbutton:SetHeight(20)
	clearbutton:SetPoint("LEFT", searchbutton, "RIGHT", 10, 0)
	clearbutton:SetScript("OnClick", function(this) this:GetParent().searchterm:SetText(""); this:GetParent().table:SortData(); end)

	local closebutton = CreateFrame("Button", nil, altswindow, "UIPanelButtonTemplate")
	closebutton:SetText(L["Close"])
	closebutton:SetWidth(90)
	closebutton:SetHeight(20)
	closebutton:SetPoint("BOTTOM", altswindow, "BOTTOM", 0, 20)
	closebutton:SetScript("OnClick", function(this) this:GetParent():Hide(); end)

	local addbutton = CreateFrame("Button", nil, altswindow, "UIPanelButtonTemplate")
	addbutton:SetText(L["Add"])
	addbutton:SetWidth(90)
	addbutton:SetHeight(20)
	addbutton:SetPoint("BOTTOM", altswindow, "BOTTOM", -120, 70)
	addbutton:SetScript("OnClick", 
		function(this)
		    addMainFrame.mainname:SetText("")
		    addMainFrame.altname:SetText("")
		    addMainFrame:Show()
		    addMainFrame:Raise()
		end)

	local deletebutton = CreateFrame("Button", nil, altswindow, "UIPanelButtonTemplate")
	deletebutton:SetText(L["Delete"])
	deletebutton:SetWidth(90)
	deletebutton:SetHeight(20)
	deletebutton:SetPoint("BOTTOM", altswindow, "BOTTOM", 0, 70)
	deletebutton:SetScript("OnClick", 
		function(this)
		    local frame = this:GetParent()
			if frame.table:GetSelection() then
				local row = frame.table:GetRow(frame.table:GetSelection())
				if row[1] and #row[1] > 0 then
					confirmMainDeleteFrame.mainname:SetText(row[1])
					confirmMainDeleteFrame:Show()
					confirmMainDeleteFrame:Raise()
					altsFrame:Hide()
				end
			end
		end)

	local editbutton = CreateFrame("Button", nil, altswindow, "UIPanelButtonTemplate")
	editbutton:SetText(L["Edit"])
	editbutton:SetWidth(90)
	editbutton:SetHeight(20)
	editbutton:SetPoint("BOTTOM", altswindow, "BOTTOM", 120, 70)
	editbutton:SetScript("OnClick", 
		function(this)
		    local frame = this:GetParent()
			if frame.table:GetSelection() then
				local row = frame.table:GetRow(frame.table:GetSelection())
				if row[1] and #row[1] > 0 then
				    frame:Hide()
					self:EditAltsHandler(row[1])
				end
			end
		end)

	altswindow.table = table
	altswindow.searchterm = searchterm

    table:RegisterEvents({
		["OnEnter"] = function (rowFrame, cellFrame, data, cols, row, realrow, column, table, ...)
			return true;
		end, 
		["OnLeave"] = function(rowFrame, cellFrame, data, cols, row, realrow, column, table, ...)
			return true;
		end,
    })

	table:EnableSelection(true)
	table:SetData(MainsTable, true)
	table:SetFilter(
		function(self, row)
			local searchterm = searchterm:GetText()
			if searchterm and #searchterm > 0 then
				term = searchterm:lower()
				if row[1]:lower():find(term) or row[2]:lower():find(term) then
					return true
				end

				return false
			else
				return true
			end
		end
	)

    altswindow.lock = self.db.profile.lock_main_window

    altswindow:SetMovable()
    altswindow:RegisterForDrag("LeftButton")
    altswindow:SetScript("OnDragStart",
        function(self,button)
			if not self.lock then
            	self:StartMoving()
			end
        end)
    altswindow:SetScript("OnDragStop",
        function(self)
            self:StopMovingOrSizing()
			if Alts.db.profile.remember_main_pos then
    			local scale = self:GetEffectiveScale() / UIParent:GetEffectiveScale()
    			local x, y = self:GetCenter()
    			x, y = x * scale, y * scale
    			x = x - GetScreenWidth()/2
    			y = y - GetScreenHeight()/2
    			x = x / self:GetScale()
    			y = y / self:GetScale()
    			Alts.db.profile.main_window_x, 
    			    Alts.db.profile.main_window_y = x, y
    			self:SetUserPlaced(false);
            end
        end)
    altswindow:EnableMouse(true)

	altswindow:Hide()
	
	return altswindow
end

function Alts:AltsHandler(input)
	if input and #input > 0 then
		altsFrame.searchterm:SetText(input)
	else
		altsFrame.searchterm:SetText("")
	end

    if #MainsTable == 0 then
        self:UpdateMainsTable()
    end

	altsFrame.table:SortData()

    -- Hide the options frame if it is open.
	local optionsFrame = InterfaceOptionsFrame
    optionsFrame:Hide()

	altsFrame:Show()
	altsFrame:Raise()
end

function Alts:GuildContribHandler(input)
--    self:GuildContrib()

--	contribFrame.table:SortData()

    -- Hide the options frame if it is open.
	local optionsFrame = InterfaceOptionsFrame
    optionsFrame:Hide()

--    contribFrame:Show()
--    contribFrame:Raise()

    self:ShowContribFrame()
end

function Alts:GuildLogHandler(input)
    self:ShowGuildLogFrame()
end

local function escapeField(value, escapeChar)
    local strFmt = "%s%s%s"
    local doubleEscape = escapeChar..escapeChar
    if escapeChar and escapeChar ~= "" then
        local escapedStr = value:gsub(escapeChar, doubleEscape)
        return strFmt:format(escapeChar, escapedStr, escapeChar)
    else
        return value
    end
end

local guildExportBuffer = {}
function Alts:GenerateGuildExport()
	if not IsInGuild() then return 0, "" end

    local guildName = GetGuildInfo("player")
    local source = LibAlts.GUILD_PREFIX..guildName
    local guildExportText = ""

	local count = 0
    local delimiter = ","
    local fields = {}
    local quote = ""
	local escapeChar = "\""
    if self.db.profile.exportEscape == true then
        quote = escapeChar
    end

    local numMembers = GetNumGuildMembers()
    local exportChar

    if not guildName or not numMembers or numMembers == 0 then return 0, "" end

    for i = 1, numMembers do
        local name, rank, rankIndex, level, class, zone, publicnote,  
            officernote, online, status, classFileName, achPts, 
            achRank, isMobile, canSoR = GetGuildRosterInfo(i)
        local weeklyXP, totalXP, weeklyRank, totalRank = GetGuildRosterContribution(i)

        exportChar = true

        if self.db.profile.exportOnlyMains == true then
            -- If this character is an alt for the guild, then skip it.
            if LibAlts:IsAltForSource(name, source) == true then
                exportChar = false
            end
        end

        if name and exportChar == true then
            wipe(fields)
			count = count + 1
            if self.db.profile.exportUseName == true then
                tinsert(fields, tostring(name or ""))
            end
            if self.db.profile.exportUseLevel == true then
                tinsert(fields, tostring(level or ""))
            end
            if self.db.profile.exportUseRank then 
                tinsert(fields, escapeField(tostring(rank or ""), quote))
            end
            if self.db.profile.exportUseClass == true then
                tinsert(fields, tostring(class or ""))
            end
            if self.db.profile.exportUsePublicNote == true then
                tinsert(fields, escapeField(tostring(publicnote or ""), quote))
            end
            if self.db.profile.exportUseOfficerNote == true then
                tinsert(fields, escapeField(tostring(officernote or ""), quote))
            end

            if self.db.profile.exportUseLastOnline == true then
                local years, months, days, hours = GetGuildRosterLastOnline(i)
                local lastOnline = 0
                if online then
                    lastOnline = time()
                elseif years and months and days and hours then
                    local diff = (((years*365)+(months*30)+days)*24+hours)*60*60
                    lastOnline = time() - diff
                end
                tinsert(fields, tostring(date("%Y/%m/%d", lastOnline)) or "")
            end

            if self.db.profile.exportUseAchvPoints == true then
                tinsert(fields, tostring(achPts or ""))
            end
            if self.db.profile.exportUseWeeklyXP == true then
                tinsert(fields, tostring(weeklyXP or ""))
            end
            if self.db.profile.exportUseTotalXP == true then
                tinsert(fields, tostring(totalXP or ""))
            end

            if self.db.profile.exportUseAlts == true then
                local altsStr = ""
                if self.db.profile.exportOnlyGuildAlts == true then
                    altsStr = strjoin(delimiter, LibAlts:GetAltsForSource(name, source)) or ""
                else
                    altsStr = strjoin(delimiter, LibAlts:GetAlts(name)) or ""
                end
                tinsert(fields, escapeField(altsStr or "",escapeChar))
            end

            local line = tconcat(fields, delimiter)
            tinsert(guildExportBuffer, line)
        end
    end

    -- Add a blank line so a final new line is added
    tinsert(guildExportBuffer, "")

    guildExportText = tconcat(guildExportBuffer, "\n")

    wipe(guildExportBuffer)

    return count, guildExportText
end

function Alts:GuildExportHandler(input)
    self:ShowGuildExportFrame()
end

function Alts:CreateEditAltsFrame()
	local editaltswindow = CreateFrame("Frame", "Alts_EditAltsWindow", UIParent)
	editaltswindow:SetFrameStrata("DIALOG")
	editaltswindow:SetToplevel(true)
	editaltswindow:SetWidth(400)
	editaltswindow:SetHeight(300)
	editaltswindow:SetPoint("CENTER", UIParent)
	editaltswindow:SetBackdrop(
		{bgFile="Interface\\ChatFrame\\ChatFrameBackground", 
	    edgeFile="Interface\\DialogFrame\\UI-DialogBox-Border", tile=true,
		tileSize=32, edgeSize=32, insets={left=11, right=12, top=12, bottom=11}})
	editaltswindow:SetBackdropColor(0,0,0,1)

	local headertext = editaltswindow:CreateFontString("Alts_Confirm_HeaderText", editaltswindow, "GameFontNormalLarge")
	headertext:SetPoint("TOP", editaltswindow, "TOP", 0, -20)
	headertext:SetText(L["Edit Alts"])

	local charname = editaltswindow:CreateFontString("Alts_Edit_CharName", editaltswindow, "GameFontNormal")
	charname:SetPoint("BOTTOM", headertext, "BOTTOM", 0, -40)
	charname:SetFont(charname:GetFont(), 14)
	charname:SetTextColor(1.0,1.0,1.0,1)

	local cols = {}
	cols[1] = {
		["name"] = L["Alt Name"],
		["width"] = 100,
		["align"] = "LEFT",
		["color"] = {
			["r"] = 1.0,
			["g"] = 1.0,
			["b"] = 1.0,
			["a"] = 1.0
		},
		["colorargs"] = nil,
		["bgcolor"] = {
			["r"] = 0.0,
			["g"] = 0.0,
			["b"] = 0.0,
			["a"] = 1.0
		},
		["defaultsort"] = "dsc",
		["sort"] = "dsc",
		["DoCellUpdate"] = nil,
	}

	local table = ScrollingTable:CreateST(cols, 5, nil, nil, editaltswindow);

	table.frame:SetPoint("TOP", charname, "BOTTOM", 0, -30)
	table.frame:SetPoint("CENTER", editaltswindow, "CENTER", 0, 0)

	local addbutton = CreateFrame("Button", nil, editaltswindow, "UIPanelButtonTemplate")
	addbutton:SetText(L["Add"])
	addbutton:SetWidth(100)
	addbutton:SetHeight(20)
	addbutton:SetPoint("BOTTOM", editaltswindow, "BOTTOM", -120, 20)
	addbutton:SetScript("OnClick", 
    	function(this)
    	    local frame = this:GetParent()
			self:AddAltHandler(frame.charname:GetText())
			frame:Hide()
    	end)

	local deletebutton = CreateFrame("Button", nil, editaltswindow, "UIPanelButtonTemplate")
	deletebutton:SetText(L["Delete"])
	deletebutton:SetWidth(100)
	deletebutton:SetHeight(20)
	deletebutton:SetPoint("BOTTOM", editaltswindow, "BOTTOM", 0, 20)
	deletebutton:SetScript("OnClick", 
    	function(this)
    	    local frame = this:GetParent()
    		if frame.table:GetSelection() then
    			local row = frame.table:GetRow(frame.table:GetSelection())
    			if row[1] and #row[1] > 0 then
    				confirmDeleteFrame.mainname:SetText(frame.charname:GetText())
    				confirmDeleteFrame.altname:SetText(row[1])
    				confirmDeleteFrame:Show()
    				frame:Hide()
    			end
    		end
    	end)

	local closebutton = CreateFrame("Button", nil, editaltswindow, "UIPanelButtonTemplate")
	closebutton:SetText(L["Close"])
	closebutton:SetWidth(100)
	closebutton:SetHeight(20)
	closebutton:SetPoint("BOTTOM", editaltswindow, "BOTTOM", 120, 20)
	closebutton:SetScript("OnClick",
	    function(this)
	        this:GetParent():Hide()
            self:UpdateMainsTable()
            altsFrame.table:SortData()
            altsFrame:Show()
	    end)

    editaltswindow.table = table
	editaltswindow.charname = charname

	table:EnableSelection(true)
	table:SetData(EditAltsTable, true)

    editaltswindow:SetMovable()
    editaltswindow:RegisterForDrag("LeftButton")
    editaltswindow:SetScript("OnDragStart",
        function(this,button)
        	this:StartMoving()
        end)
    editaltswindow:SetScript("OnDragStop",
        function(this)
            this:StopMovingOrSizing()
        end)
    editaltswindow:EnableMouse(true)

	editaltswindow:Hide()

	return editaltswindow
end

function Alts:CreateSetMainFrame()
	local setmain = CreateFrame("Frame", "Alts_SetMainWindow", UIParent)
	setmain:SetFrameStrata("DIALOG")
	setmain:SetToplevel(true)
	setmain:SetWidth(400)
	setmain:SetHeight(200)
	setmain:SetPoint("CENTER", UIParent)
	setmain:SetBackdrop(
		{bgFile="Interface\\ChatFrame\\ChatFrameBackground", 
	    edgeFile="Interface\\DialogFrame\\UI-DialogBox-Border", tile=true,
		tileSize=32, edgeSize=32, insets={left=11, right=12, top=12, bottom=11}})
	setmain:SetBackdropColor(0,0,0,1)
		
	local editbox = CreateFrame("EditBox", nil, setmain, "InputBoxTemplate")
	editbox:SetFontObject(ChatFontNormal)
	editbox:SetWidth(300)
	editbox:SetHeight(35)
	editbox:SetPoint("CENTER", setmain)
	editbox:SetScript("OnShow", function(this) this:SetFocus() end)
	editbox:SetScript("OnEnterPressed", 
	    function(this)
	        local frame = this:GetParent()
	        self:SaveMainName(frame.charname:GetText(),this:GetText())
	        frame:Hide()
	    end)
	editbox:SetScript("OnEscapePressed",
	    function(this)
	        this:SetText("");
	        this:GetParent():Hide();
	    end)

	local savebutton = CreateFrame("Button", nil, setmain, "UIPanelButtonTemplate")
	savebutton:SetText(L["Save"])
	savebutton:SetWidth(100)
	savebutton:SetHeight(20)
	savebutton:SetPoint("BOTTOM", setmain, "BOTTOM", -60, 20)
	savebutton:SetScript("OnClick",
	    function(this)
	        local frame = this:GetParent()
	        self:SaveMainName(frame.charname:GetText(),frame.editbox:GetText())
	        frame:Hide()
	    end)

	local cancelbutton = CreateFrame("Button", nil, setmain, "UIPanelButtonTemplate")
	cancelbutton:SetText(L["Cancel"])
	cancelbutton:SetWidth(100)
	cancelbutton:SetHeight(20)
	cancelbutton:SetPoint("BOTTOM", setmain, "BOTTOM", 60, 20)
	cancelbutton:SetScript("OnClick", function(this) this:GetParent():Hide(); end)

	local headertext = setmain:CreateFontString("Alts_HeaderText", setmain, "GameFontNormalLarge")
	headertext:SetPoint("TOP", setmain, "TOP", 0, -20)
	headertext:SetText(L["Set Main"])

	local charname = setmain:CreateFontString("Alts_CharName", setmain, "GameFontNormal")
	charname:SetPoint("BOTTOM", headertext, "BOTTOM", 0, -40)
	charname:SetFont(charname:GetFont(), 14)
	charname:SetTextColor(1.0,1.0,1.0,1)

	setmain.charname = charname
	setmain.editbox = editbox

    setmain:SetMovable()
    setmain:RegisterForDrag("LeftButton")
    setmain:SetScript("OnDragStart",
        function(this,button)
        	this:StartMoving()
        end)
    setmain:SetScript("OnDragStop",
        function(this)
            this:StopMovingOrSizing()
        end)
    setmain:EnableMouse(true)

	setmain:Hide()

	return setmain
end

function Alts:CreateConfirmDeleteFrame()
	local deletewindow = CreateFrame("Frame", "Alts_ConfirmDeleteWindow", UIParent)
	deletewindow:SetFrameStrata("DIALOG")
	deletewindow:SetToplevel(true)
	deletewindow:SetWidth(400)
	deletewindow:SetHeight(250)
	deletewindow:SetPoint("CENTER", UIParent)
	deletewindow:SetBackdrop(
		{bgFile="Interface\\ChatFrame\\ChatFrameBackground", 
	    edgeFile="Interface\\DialogFrame\\UI-DialogBox-Border", tile=true,
		tileSize=32, edgeSize=32, insets={left=11, right=12, top=12, bottom=11}})
	deletewindow:SetBackdropColor(0,0,0,1)
    
	local headertext = deletewindow:CreateFontString("Alts_Confirm_HeaderText", deletewindow, "GameFontNormalLarge")
	headertext:SetPoint("TOP", deletewindow, "TOP", 0, -20)
	headertext:SetText(L["Delete Alt"])

	local warningtext = deletewindow:CreateFontString("Alts_Confirm_WarningText", deletewindow, "GameFontNormalLarge")
	warningtext:SetPoint("TOP", headertext, "TOP", 0, -50)
	warningtext:SetText(L["Are you sure you wish to remove"])

	local altname = deletewindow:CreateFontString("Alts_Confirm_CharName", deletewindow, "GameFontNormal")
	altname:SetPoint("BOTTOM", warningtext, "BOTTOM", 0, -30)
	altname:SetFont(altname:GetFont(), 14)
	altname:SetTextColor(1.0,1.0,1.0,1)

	local warningtext2 = deletewindow:CreateFontString("Alts_Confirm_WarningText2", deletewindow, "GameFontNormalLarge")
	warningtext2:SetPoint("TOP", altname, "TOP", 0, -30)
	warningtext2:SetText(L["as an alt of"])

	local mainname = deletewindow:CreateFontString("Alts_Confirm_CharName", deletewindow, "GameFontNormal")
	mainname:SetPoint("BOTTOM", warningtext2, "BOTTOM", 0, -30)
	mainname:SetFont(mainname:GetFont(), 14)
	mainname:SetTextColor(1.0,1.0,1.0,1)

	local deletebutton = CreateFrame("Button", nil, deletewindow, "UIPanelButtonTemplate")
	deletebutton:SetText(L["Delete"])
	deletebutton:SetWidth(100)
	deletebutton:SetHeight(20)
	deletebutton:SetPoint("BOTTOM", deletewindow, "BOTTOM", -60, 20)
	deletebutton:SetScript("OnClick",
	    function(this)
	        if useLibAlts == true then
	            LibAlts:DeleteAlt(mainname:GetText(), altname:GetText())
            else
	            self:DeleteAlt(mainname:GetText(), altname:GetText())
	        end
	        this:GetParent():Hide()
	        self:EditAltsHandler(mainname:GetText())
	    end)

	local cancelbutton = CreateFrame("Button", nil, deletewindow, "UIPanelButtonTemplate")
	cancelbutton:SetText(L["Cancel"])
	cancelbutton:SetWidth(100)
	cancelbutton:SetHeight(20)
	cancelbutton:SetPoint("BOTTOM", deletewindow, "BOTTOM", 60, 20)
	cancelbutton:SetScript("OnClick",
	    function(this)
	        this:GetParent():Hide()
	        editAltsFrame:Show()
	    end)

	deletewindow.mainname = mainname
    deletewindow.altname = altname

    deletewindow:SetMovable()
    deletewindow:RegisterForDrag("LeftButton")
    deletewindow:SetScript("OnDragStart",
        function(this,button)
        	this:StartMoving()
        end)
    deletewindow:SetScript("OnDragStop",
        function(this)
            this:StopMovingOrSizing()
        end)
    deletewindow:EnableMouse(true)

	deletewindow:Hide()

	return deletewindow
end

function Alts:CreateConfirmMainDeleteFrame()
	local deletewindow = CreateFrame("Frame", "Alts_ConfirmMainDeleteWindow", UIParent)
	deletewindow:SetFrameStrata("DIALOG")
	deletewindow:SetToplevel(true)
	deletewindow:SetWidth(400)
	deletewindow:SetHeight(200)
	deletewindow:SetPoint("CENTER", UIParent)
	deletewindow:SetBackdrop(
		{bgFile="Interface\\ChatFrame\\ChatFrameBackground", 
	    edgeFile="Interface\\DialogFrame\\UI-DialogBox-Border", tile=true,
		tileSize=32, edgeSize=32, insets={left=11, right=12, top=12, bottom=11}})
	deletewindow:SetBackdropColor(0,0,0,1)
    
	local headertext = deletewindow:CreateFontString("Alts_ConfirmDelMain_HeaderText", deletewindow, "GameFontNormalLarge")
	headertext:SetPoint("TOP", deletewindow, "TOP", 0, -20)
	headertext:SetText(L["Delete Main"])

	local warningtext = deletewindow:CreateFontString("Alts_ConfirmDelMain_WarningText", deletewindow, "GameFontNormalLarge")
	warningtext:SetPoint("TOP", headertext, "TOP", 0, -50)
	warningtext:SetWordWrap(true)
	warningtext:SetWidth(350)
	warningtext:SetText(L["Are you sure you wish to delete the main and all user-entered alts for:"])

	local mainname = deletewindow:CreateFontString("Alts_ConfirmDelMain_CharName", deletewindow, "GameFontNormal")
	mainname:SetPoint("BOTTOM", warningtext, "BOTTOM", 0, -30)
	mainname:SetFont(mainname:GetFont(), 14)
	mainname:SetTextColor(1.0,1.0,1.0,1)

	local deletebutton = CreateFrame("Button", nil, deletewindow, "UIPanelButtonTemplate")
	deletebutton:SetText(L["Delete"])
	deletebutton:SetWidth(100)
	deletebutton:SetHeight(20)
	deletebutton:SetPoint("BOTTOM", deletewindow, "BOTTOM", -60, 20)
	deletebutton:SetScript("OnClick",
	    function(this)
	        self:DeleteUserMain(mainname:GetText())
	        this:GetParent():Hide()
            self:UpdateMainsTable()
            altsFrame.table:SortData()
            altsFrame:Show()
	    end)

	local cancelbutton = CreateFrame("Button", nil, deletewindow, "UIPanelButtonTemplate")
	cancelbutton:SetText(L["Cancel"])
	cancelbutton:SetWidth(100)
	cancelbutton:SetHeight(20)
	cancelbutton:SetPoint("BOTTOM", deletewindow, "BOTTOM", 60, 20)
	cancelbutton:SetScript("OnClick",
	    function(this)
	        this:GetParent():Hide()
	        altsFrame:Show()
	    end)

	deletewindow.mainname = mainname

    deletewindow:SetMovable()
    deletewindow:RegisterForDrag("LeftButton")
    deletewindow:SetScript("OnDragStart",
        function(this,button)
        	this:StartMoving()
        end)
    deletewindow:SetScript("OnDragStop",
        function(this)
            this:StopMovingOrSizing()
        end)
    deletewindow:EnableMouse(true)

	deletewindow:Hide()

	return deletewindow
end

function Alts:EditAltsHandler(input)
	local name = nil
	local alts
	if input and #input > 0 then
		name = self:TitleCase(input)
		
		editAltsFrame.charname:SetText(name)

        wipe(EditAltsTable)
        
        if useLibAlts == true then
            alts = {LibAlts:GetAlts(name)}
        else
            alts = {self:GetAlts(name)}
        end

        for i, v in ipairs(alts) do
            tinsert(EditAltsTable, {v})
        end

        editAltsFrame.table:SortData()
		editAltsFrame:Show()
		editAltsFrame:Raise()
	end	
end

function Alts:SaveMainName(name, main)
	if name and #name > 0 and main and #main > 0 then
	    if useLibAlts == true then
	        LibAlts:SetAlt(main, name)
	    else
		    self:SetAlt(main, name)
		end
	end

	setMainFrame.charname:SetText("")
	setMainFrame.editbox:SetText("")
end

function Alts:AddAltName(main, alt)
	if main and #main > 0 and alt and #alt > 0 then
	    if useLibAlts == true then
	        LibAlts:SetAlt(main, alt)
	    else
		    self:SetAlt(main, alt)
		end
	end

	addAltFrame.charname:SetText("")
	addAltFrame.editbox:SetText("")
end

function Alts:AddMainName(main, alt)
	if main and #main > 0 and alt and #alt > 0 then
	    if useLibAlts == true then
	        LibAlts:SetAlt(main, alt)
	    else
		    self:SetAlt(main, alt)
		end
	end

	addMainFrame.mainname:SetText("")
	addMainFrame.altname:SetText("")
end

function Alts:OnEnable()
    -- Called when the addon is enabled

    -- Hook the game tooltip so we can add character Notes
    self:HookScript(GameTooltip, "OnTooltipSetUnit")

	-- Hook the friends frame tooltip
	--self:HookScript("FriendsFrameTooltip_Show")

	-- Register to receive the chat messages to watch for logons and who requests
	self:RegisterEvent("CHAT_MSG_SYSTEM")
    -- Watch for combat start and end events.
	self:RegisterEvent("PLAYER_REGEN_ENABLED")
	self:RegisterEvent("PLAYER_REGEN_DISABLED")

    --self:RegisterEvent("BN_FRIEND_ACCOUNT_ONLINE")
    --self:RegisterEvent("BN_FRIEND_TOON_ONLINE")

    -- Build reverse lookup tables for other guilds.
    for k,v in pairs(self.db.realm.altsBySource) do
        local guildName = GetGuildInfo("player")
        if not (k == guildName and self.db.profile.autoGuildImport) then
            MainsBySource[k] = ReverseTable(self.db.realm.altsBySource[k])
        end
    end

	-- Register event and call roster to import guild members and alts
	self:RegisterEvent("GUILD_ROSTER_UPDATE")
    GuildRoster()

	-- Register event to update friends data.
	self:RegisterEvent("FRIENDLIST_UPDATE")
	-- Call ShowFriends to get the friend and ignore data updated.
    ShowFriends()

    -- Populate the MainsTable
    self:UpdateMainsTable()

	-- Create the Alts frame for later use
    altsFrame = self:CreateAltsFrame()

	-- Create the Contributions frame for later use
    contribFrame = self:CreateContribFrame()
	
	-- Create the Set Main frame to use later
	setMainFrame = self:CreateSetMainFrame()
	
	-- Create the Edit Alts frame for later use
	editAltsFrame = self:CreateEditAltsFrame()

	-- Create the Add Alt frame to use later
	addAltFrame = self:CreateAddAltFrame()

	-- Create the Add Main frame to use later
	addMainFrame = self:CreateAddMainFrame()

	-- Create the Confirm Delete Alt frame for later use
	confirmDeleteFrame = self:CreateConfirmDeleteFrame()

	-- Create the Confirm Delete Alt frame for later use
	confirmMainDeleteFrame = self:CreateConfirmMainDeleteFrame()

	-- Add the Edit Note menu item on unit frames
	self:AddSetMainMenuItem()

    -- Hook chat frames so we can edit the messages
    if self.db.profile.showMainsInChat then
        self:HookChatFrames()
    end
end

function Alts:OnDisable()
	self:UnregisterEvent("CHAT_MSG_SYSTEM")
	self:UnregisterEvent("PLAYER_REGEN_ENABLED")
	self:UnregisterEvent("PLAYER_REGEN_DISABLED")
	-- Remove the menu items
	self:RemoveSetMainMenuItem()
    self:UnhookChatFrames()
end

function Alts:AddSetMainMenuItem()
	UnitPopupButtons["SET_MAIN"] = {text = L["Set Main"], dist = 0}

	self:SecureHook("UnitPopup_OnClick", "SetMainMenuClick")

	tinsert(UnitPopupMenus["PLAYER"], (#UnitPopupMenus["PLAYER"])-1, "SET_MAIN")
	tinsert(UnitPopupMenus["PARTY"], (#UnitPopupMenus["PARTY"])-1, "SET_MAIN")
	tinsert(UnitPopupMenus["FRIEND"], (#UnitPopupMenus["FRIEND"])-1, "SET_MAIN")
	tinsert(UnitPopupMenus["FRIEND_OFFLINE"], (#UnitPopupMenus["FRIEND_OFFLINE"])-1, "SET_MAIN")
	tinsert(UnitPopupMenus["RAID_PLAYER"], (#UnitPopupMenus["RAID_PLAYER"])-1, "SET_MAIN")
end

function Alts:RemoveSetMainMenuItem()
	UnitPopupButtons["SET_MAIN"] = nil

	self:unhook("UnitPopup_OnClick")
end

function Alts:SetMainMenuClick(self)
	local menu = UIDROPDOWNMENU_INIT_MENU
	local button = self.value
	if button == "SET_MAIN" then
		local fullname = nil
		local name = menu.name
		local server = menu.server
		if server and #server > 0 then
			local strFormat = "%s - %s"
			fullname = strFormat:format(name, server)
		else
			fullname = name
		end

		Alts:SetMainHandler(fullname)
	end
end

function Alts:IsVisible()
	if altsFrame then
		return altsFrame:IsVisible()
	end
end

function Alts:HideAltsWindow()
	if altsFrame then
		altsFrame:Hide()
	end
end

function Alts:OnTooltipSetUnit(tooltip, ...)
    if not self.db.profile.showMainInTooltip and 
        not self.db.profile.showAltsInTooltip then return end

    local name, unitid = tooltip:GetUnit()

	-- If the unit exists and is a player then check if there is a note for it.
    if UnitExists(unitid) and UnitIsPlayer(unitid) then
		-- Get the unit's name including the realm name
		local nameString = GetUnitName(unitid, true)
        if not nameString then return end

        -- Check if a single line should be displayed for mains and alts
        if self.db.profile.singleLineTooltipDisplay then
            local main = self:GetMain(nameString)
            if main and #main > 0 then
                local alts = { self:GetAlts(main) }

                if alts and #alts > 0 then
                    local altList = strjoin(", ", unpack(alts))
                    if altList and #altList > 0 then
                        if self.db.profile.wrapTooltip then
                            altList = wrap(altList,self.db.profile.wrapTooltipLength,"    ","", 4)
                        end
            	        tooltip:AddLine(YELLOW..main..": "..WHITE..altList, 1, 1, 1, not self.db.profile.wrapTooltip)
                        return
            	    end
        	    end
            end
        end

        -- Check if it's a main
        if self.db.profile.showMainInTooltip then
            local main = self:GetMain(nameString)
            if main and #main > 0 then
            	tooltip:AddLine(YELLOW..L["Main: "]..WHITE..main, 1, 1, 1, true)
            end
        end

        -- Check if it's an alt
        if self.db.profile.showAltsInTooltip then
            local alts = { self:GetAlts(nameString) }

            if alts and #alts > 0 then
                local altList = strjoin(", ", unpack(alts))
                if altList and #altList > 0 then
        			if self.db.profile.wrapTooltip then
        			    altList = wrap(altList,self.db.profile.wrapTooltipLength,"    ","", 4)
        			end
                	tooltip:AddLine(YELLOW..L["Alts: "]..WHITE..altList, 1, 1, 1, not self.db.profile.wrapTooltip)
                end
            end
        end
    end
end

function Alts:DisplayMain(name)
    name = self:TitleCase(name)

	local main = self:GetMain(name)
    --local alts = { self:GetAlts(name) }
    --local altList = strjoin(", ", unpack(alts))

    if self.db.profile.singleLineChatDisplay == true and main and #main > 0 then
        local alts = { self:GetAlts(main) }
        local altList
        local text

        for i, v in ipairs(alts) do
            text = v
            if v == name then
                text = BLUE .. v .. WHITE
            else
                text = v
            end
            
            if i == 1 then
                altList = text
            else
                altList = altList .. ", " .. text
            end
        end

        if altList and #altList > 0 then
            self:Print(YELLOW..main..": "..WHITE..altList)
        end
    else
        local alts = { self:GetAlts(name) }
        local altList = strjoin(", ", unpack(alts))

    	if main and #main > 0 then
    		self:Print(YELLOW..name..": "..WHITE..main)
    	end

        if altList and #altList > 0 then
            self:Print(YELLOW..name..": "..WHITE..altList)
        end
    end
end

function Alts:CHAT_MSG_SYSTEM(event, message)
	local name
	
	if self.db.profile.showInfoOnWho then
	    name = LibDeformat(message, WHO_LIST_FORMAT)
	end
	if self.db.profile.showInfoOnLogon and not name then 
	    name = LibDeformat(message, WHO_LIST_GUILD_FORMAT)
	end
	if self.db.profile.showInfoOnLogon and not name then
	    name = LibDeformat(message, ERR_FRIEND_ONLINE_SS)
	end

	if name then
		self:ScheduleTimer("DisplayMain", 0.1, name)
	end
end

function Alts:PLAYER_REGEN_DISABLED()
    combat = true
    if self.db.profile.disableInCombat then
        monitor = false
    end
    if self.db.profile.disableInCombat then
        self:UnregisterEvent("CHAT_MSG_SYSTEM")
    end
end

function Alts:PLAYER_REGEN_ENABLED()
    combat = false
    monitor = true
    if self.db.profile.disableInCombat then
        self:RegisterEvent("CHAT_MSG_SYSTEM")
    end
end

function Alts:GUILD_ROSTER_UPDATE(event, message)
    self:UnregisterEvent("GUILD_ROSTER_UPDATE")
    self:UpdateGuild()
end

function Alts:FRIENDLIST_UPDATE(event, message)
    self:UnregisterEvent("FRIENDLIST_UPDATE")
    self:CheckAndUpdateFriends()
    self:CheckAndUpdateIgnores()
end

function Alts:BN_FRIEND_ACCOUNT_ONLINE(event, message)
    for i = 1, BNGetNumFriends() do
        local presenceID, givenName, surname, toonName, toonID, client, 
            isOnline, lastOnline, isAFK, isDND, messageText, noteText, 
            isFriend, unknown = BNGetFriendInfo(i)
        if presenceID == message then
            self:Print(presenceID..","..givenName..","..surname..","..toonName..","..
                toonID..","..client..","..isOnline..","..date("%c",lastOnline)..
                ","..isAFK..","
                ..isDND..","..messageText or "nil"..","..noteText or "nil"..","..
                isFriend)
        end
    end
end

function Alts:BN_FRIEND_TOON_ONLINE(event, message)

end

function formatCharName(name)
    local MULTIBYTE_FIRST_CHAR = "^([\192-\255]?%a?[\128-\191]*)"
    if not name then
        return ""
    end
    
    -- Change the string up to a - to lower case.
    -- Limiting it in case a server name is present in the name.
    name = name:gsub("^([^%-]+)", string.lower)
    -- Change the first character to uppercase accounting for multibyte characters.
    name = name:gsub(MULTIBYTE_FIRST_CHAR, string.upper, 1)
    return name
end

function wrap(str, limit, indent, indent1,offset)
	indent = indent or ""
	indent1 = indent1 or indent
	limit = limit or 72
	offset = offset or 0
	local here = 1-#indent1-offset
	return indent1..str:gsub("(%s+)()(%S+)()",
						function(sp, st, word, fi)
							if fi-here > limit then
								here = st - #indent
								return "\n"..indent..word
							end
						end)
end
