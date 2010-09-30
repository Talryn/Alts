Alts = LibStub("AceAddon-3.0"):NewAddon("Alts", "AceConsole-3.0", "AceHook-3.0", "AceEvent-3.0", "AceTimer-3.0")

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
local tconcat = table.concat
local pairs, ipairs, unpack = pairs, ipairs, unpack

-- Functions defined at the end of the file
local formatCharName
local wrap

local defaults = {
	profile = {
		minimap = {
			hide = true,
		},
		verbose = true,
		autoGuildImport = true,
		showMainInTooltip = true,
		showAltsInTooltip = true,
        showInfoOnLogon = true,
        showInfoOnWho = true,
        singleLineChatDisplay = true,
        singleLineTooltipDisplay = true,
		wrapTooltip = true,
		wrapTooltipLength = 50,
	},
	realm = {
	    alts = {},
	    altsBySource = {}
	}
}

local options
local useLibAlts = false
local altsLDB = nil
local altsFrame = nil
local setMainFrame = nil
local addAltFrame = nil
local editAltsFrame = nil
local confirmDeleteFrame = nil
local Mains = {}
local MainsBySource = {}
local AllMains = {}
local MainsTable = {}
local EditAltsTable = {}

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

function Alts:UpdateGuildAlts()
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
        local name = GetGuildRosterInfo(i)
        guildMembers[LibAlts:TitleCase(name)] = true
    end

    -- Walk through the list and look for alt names
    for i = 1, numMembers do
        local name, rank, rankIndex, level, class, zone, publicnote, officernote, 
            online, status = GetGuildRosterInfo(i)
        
        name = self:TitleCase(name)

        local main
        -- Look for the following patterns in public and officer notes:
        --   * <name>'s alt
        --   * ALT: <name>
        --   * Alt of <name>
        --   * <name>
        local altMatch1 = "(.-)'s? [Aa][Ll][Tt]"
        local altMatch2 = "[Aa][Ll][Tt]:%s*(%a+)"
        local altMatch3 = "[Aa][Ll][Tt] [Oo][Ff] (%a+)"

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
            -- Check if the note is just a name
            function(val)
                return val
            end,     
        }

        for i,v in ipairs(funcs) do
            main = self:TitleCase(v(officernote))
            if main and guildMembers[main] then break end
            
            main = self:TitleCase(v(publicnote))
            if main and guildMembers[main] then break end
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
    if not self.db.realm.altsBySource[source] then return nil end

    main = self:TitleCase(main)
    
    if not self.db.realm.altsBySource[source][main] or
        #self.db.realm.altsBySource[source][main] == 0 then
        return nil
    end
    
    return unpack(self.db.realm.altsBySource[source][main])
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
        		displayheader = {
        			order = 0,
        			type = "header",
        			name = "General Options",
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
        	    verbose = {
                    name = L["Verbose"],
                    desc = L["Toggles the display of informational messages"],
                    type = "toggle",
                    set = function(info, val) self.db.profile.verbose = val end,
                    get = function(info) return self.db.profile.verbose end,
        			order = 15
                },
        		displayheaderGuild = {
        			order = 20,
        			type = "header",
        			name = L["Guild Import Options"],
        		},
        	    autoImportGuild = {
                    name = L["Auto Import Guild"],
                    desc = L["Toggles if main/alt data should be automaticall imported from guild notes."],
                    type = "toggle",
                    set = function(info, val) self.db.profile.autoGuildImport = val end,
                    get = function(info) return self.db.profile.autoGuildImport end,
        			order = 30
                },
        		displayheaderDisplay = {
        			order = 100,
        			type = "header",
        			name = L["Display Options"],
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
        		displayheaderTooltip = {
        			order = 200,
        			type = "header",
        			name = L["Tooltip Options"],
        		},
                wrapTooltip = {
                    name = L["Wrap Tooltips"],
                    desc = L["Wrap notes in tooltips"],
                    type = "toggle",
                    set = function(info,val) self.db.profile.wrapTooltip = val end,
                    get = function(info) return self.db.profile.wrapTooltip end,
        			order = 210
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
        			order = 220
                },
            }
        }
    end

    return options
end

function Alts:OnInitialize()
    -- Called when the addon is loaded
    self.db = LibStub("AceDB-3.0"):New("AltsDB", defaults, "Default")
    Mains = ReverseTable(self.db.realm.alts)

    -- Register the options table
    LibStub("AceConfig-3.0"):RegisterOptionsTable("Alts", self:GetOptions())
	self.optionsFrame = LibStub("AceConfigDialog-3.0"):AddToBlizOptions(
	    "Alts", ADDON_NAME)

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

	self:RegisterChatCommand("setmain", "SetMainHandler")
	self:RegisterChatCommand("delalt", "DelAltHandler")
	self:RegisterChatCommand("getalts", "GetAltsHandler")
	self:RegisterChatCommand("getmain", "GetMainHandler")

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
    				InterfaceOptionsFrame_OpenToCategory(self.optionsFrame)
    			end
    		elseif button == "LeftButton" then
    			if self:IsVisible() then
    				self:HideAltsWindow()
    			else
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
		local main = self:GetMain(alt)
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
	cancelbutton:SetScript("OnClick", function() cancelbutton:GetParent():Hide(); end)

	local headertext = addalt:CreateFontString("Alts_HeaderText", addalt, "GameFontNormalLarge")
	headertext:SetPoint("TOP", addalt, "TOP", 0, -20)
	headertext:SetText(L["Add Alt"])

	local charname = addalt:CreateFontString("Alts_CharName", addalt, "GameFontNormal")
	charname:SetPoint("BOTTOM", headertext, "BOTTOM", 0, -40)
	charname:SetFont(charname:GetFont(), 14)
	charname:SetTextColor(1.0,1.0,1.0,1)

	addalt.charname = charname
	addalt.editbox = editbox

	addalt:Hide()

	return addalt
end

function Alts:CreateAltsFrame()
	local altswindow = CreateFrame("Frame", "Alts_AltsWindow", UIParent)
	altswindow:SetFrameStrata("DIALOG")
	altswindow:SetToplevel(true)
	altswindow:SetWidth(630)
	altswindow:SetHeight(430)
	altswindow:SetPoint("CENTER", UIParent)
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

	local deletebutton = CreateFrame("Button", nil, altswindow, "UIPanelButtonTemplate")
	deletebutton:SetText(L["Delete"])
	deletebutton:SetWidth(90)
	deletebutton:SetHeight(20)
	deletebutton:SetPoint("BOTTOM", altswindow, "BOTTOM", -60, 70)
	deletebutton:SetScript("OnClick", 
		function(this)
--[[
		    local frame = this:GetParent()
			if frame.table:GetSelection() then
				local row = frame.table:GetRow(frame.table:GetSelection())
				if row[1] and #row[1] > 0 then
					confirmDeleteFrame.charname:SetText(row[1])
					confirmDeleteFrame:Show()
				end
			end
]]--
		end)

	local editbutton = CreateFrame("Button", nil, altswindow, "UIPanelButtonTemplate")
	editbutton:SetText(L["Edit"])
	editbutton:SetWidth(90)
	editbutton:SetHeight(20)
	editbutton:SetPoint("BOTTOM", altswindow, "BOTTOM", 60, 70)
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
	altsFrame:Show()
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

function Alts:OnEnable()
    -- Called when the addon is enabled

    -- Hook the game tooltip so we can add character Notes
    self:HookScript(GameTooltip, "OnTooltipSetUnit")

	-- Hook the friends frame tooltip
	--self:HookScript("FriendsFrameTooltip_Show")

	-- Register to receive the chat messages to watch for logons and who requests
	self:RegisterEvent("CHAT_MSG_SYSTEM")

    self:RegisterEvent("BN_FRIEND_ACCOUNT_ONLINE")
    self:RegisterEvent("BN_FRIEND_TOON_ONLINE")

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

    -- Populate the MainsTable
    self:UpdateMainsTable()

	-- Create the Alts frame for later use
    altsFrame = self:CreateAltsFrame()
	
	-- Create the Set Main frame to use later
	setMainFrame = self:CreateSetMainFrame()
	
	-- Create the Edit Alts frame for later use
	editAltsFrame = self:CreateEditAltsFrame()

	-- Create the Add Alt frame to use later
	addAltFrame = self:CreateAddAltFrame()

	-- Create the Confirm Delete Alt frame for later use
	confirmDeleteFrame = self:CreateConfirmDeleteFrame()
	
	-- Add the Edit Note menu item on unit frames
	self:AddSetMainMenuItem()
end

function Alts:OnDisable()
    -- Called when the addon is disabled
	self:UnregisterEvent("CHAT_MSG_SYSTEM")
	
	-- Remove the menu items
	self:RemoveSetMainMenuItem()
end

function Alts:AddSetMainMenuItem()
	UnitPopupButtons["SET_MAIN"] = {text = L["Set Main"], dist = 0}

	self:SecureHook("UnitPopup_OnClick", "SetMainMenuClick")

	tinsert(UnitPopupMenus["PLAYER"], (#UnitPopupMenus["PLAYER"])-1, "SET_MAIN")
	tinsert(UnitPopupMenus["PARTY"], (#UnitPopupMenus["PARTY"])-1, "SET_MAIN")
	tinsert(UnitPopupMenus["FRIEND"], (#UnitPopupMenus["FRIEND"])-1, "SET_MAIN")
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
		nameString = GetUnitName(unitid, true)
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
    local alts = { self:GetAlts(name) }
    local altList = strjoin(", ", unpack(alts))

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

function Alts:GUILD_ROSTER_UPDATE(event, message)
    self:UnregisterEvent("GUILD_ROSTER_UPDATE")
    self:UpdateGuildAlts()
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
