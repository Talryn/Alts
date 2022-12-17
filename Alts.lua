local _G = getfenv(0)
local ADDON_NAME, addon = ...

local string = _G.string
local table = _G.table
local pairs = _G.pairs
local ipairs = _G.ipairs
local LibStub = _G.LibStub

local Alts = LibStub("AceAddon-3.0"):NewAddon("Alts", "AceConsole-3.0", "AceHook-3.0", "AceEvent-3.0", "AceTimer-3.0")
local AltsDB = addon.AltsDB
local AGU = LibStub("AceGUI-3.0")
local L = LibStub("AceLocale-3.0"):GetLocale("Alts", true)
local LibDeformat = LibStub("LibDeformat-3.0")
local LDB = LibStub("LibDataBroker-1.1")
local icon = LibStub("LibDBIcon-1.0")
local LibAlts = LibStub("LibAlts-1.0")
local ScrollingTable = LibStub("ScrollingTable")

local DEBUG = false

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
local unpack, next = _G.unpack, _G.next
local select = _G.select
local wipe = _G.wipe
local tostring = _G.tostring

-- Functions defined at the end of the file.
local wrap

local defaults = {
	profile = {
		minimap = {
			hide = true,
		},
		verbose = true,
		debug = false,
		disableInCombat = true,
		autoGuildImport = true,
		showMainInTooltip = true,
		showAltsInTooltip = true,
		showInfoOnLogon = true,
		showInfoOnWho = true,
		showMainsInChat = true,
		useMainNameColor = true,
		mainNameColor = { r = 0.47, g = 0.47, b = 1.0, a = 1.0 },
		singleLineChatDisplay = true,
		singleLineTooltipDisplay = true,
		wrapTooltip = true,
		wrapTooltipLength = 50,
		reportMissingMains = false,
		lock_main_window = false,
		remember_main_pos = true,
		main_window_x = 0,
		main_window_y = 0,
		saveGuild = true,
		exportUseName = true,
		exportUseRank = true,
		exportUseLevel = true,
		exportUseClass = true,
		exportUsePublicNote = true,
		exportUseOfficerNote = true,
		exportUseLastOnline = true,
		exportUseAchvPoints = true,
		exportUseAlts = true,
		exportEscape = true,
		exportOnlyMains = true,
		exportOnlyGuildAlts = true,
		reportRemovedFriends = true,
		reportRemovedIgnores = true,
		reportGuildChanges = true,
		reportTo = "Chat",
		uiModifications = {
			["unitMenusSetMain"] = true,
			["GuildRosterTooltip"] = true,
			["CommunitiesTooltip"] = true,
		},
		-- Rules and config for matching alts
		altMatching = {
			methods = {
				[1] = {
					-- <name>
					regex = "^[ ]*([%a\128-\255-]+)[ ]*$",
					description = "<name>",
					enabled = true,
				},
				[2] = {
					-- <name>'s alt
					regex = "(.-)'s?[ ]+[Aa][Ll][Tt]",
					description = "<name>'s alt",
					enabled = true,
				},
				[3] = {
					-- ALT: <name>
					regex = "[Aa][Ll][Tt]:%s*([%a\128-\255-]+)",
					description = "ALT: <name>",
					enabled = true,
				},
				[4] = {
					-- Alt of <name>
					regex = "[Aa][Ll][Tt][ ]+[Oo][Ff][ ]+([%a\128-\255-]+)",
					description = "Alt of <name>",
					enabled = true,
				},
				[5] = {
					-- AKA: <name>
					regex = "[Aa][Kk][Aa]:%s*([%a\128-\255-]+)",
					description = "AKA: <name>",
					enabled = true,
				},
				[6] = {
					-- [<name>] or (<name>)
					regex = "^[%[(][ ]*([%a\128-\255-]+)[ ]*[)%]]",
					description = "[<name>] or (<name>)",
					enabled = true,
				},
				[7] = {
					-- ALT(<name>)
					regex = "[Aa][Ll][Tt][(][ ]*([%a\128-\255-]+)[ ]*[)]",
					description = "ALT(<name>)",
					enabled = true,
				},
				[8] = {
					-- <name> alt
					regex = "([%a\128-\255-]+)[ ]+[Aa][Ll][Tt]",
					description = "<name> alt",
					enabled = true,
				},
				[9] = {
					-- =<name>
					regex = "^[= ]+([%a\128-\255-]+)",
					description = "=<name>",
					enabled = false,
				},
				[10] = {
					-- A:<name>
					regex = "^%s*[Aa]:%s*([%a\128-\255-]+)",
					description = "A: <name>",
					enabled = false,
				},
				[11] = {
					-- alt-<name>
					regex = "^%s*[Aa][Ll][Tt]-%s*([%a\128-\255-]+)",
					description = "alt-<name>",
					enabled = false,
				},
				[12] = {
					-- @<name>
					regex = "^%s*@%s*([%a\128-\255-]+)",
					description = "@<name>",
					enabled = true,
				},
				[13] = {
					-- ALT <name>
					regex = "[Aa][Ll][Tt]%s*([%a\128-\255-]+)",
					description = "ALT <name>",
					enabled = true,
				},

			},
			customMethods = {},
		},
		battleNet = {
			rememberPos = true,
			browserX = 0,
			browserY = 0,
			lockBrowser = false,
		},
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
	},
	global = {
		battleNet = {
			accounts = {},
			characters = {},
		},
	},
}

local guildUpdateTimer = nil
local combat = false
local monitor = true
local options
local playerName = ""
local playerRealm = ""
local playerRealmAbbr = ""
local altsLDB = nil
local altsFrame = nil
local setMainFrame = nil
local addAltFrame = nil
local addMainFrame = nil
local editAltsFrame = nil
local confirmDeleteFrame = nil
local confirmMainDeleteFrame = nil
local MainsTable = {}
local EditAltsTable = {}

Alts.matchFuncs = {}

function Alts:HookChatFrames()
    for i = 1, _G.NUM_CHAT_WINDOWS do
        local chatFrame = _G["ChatFrame" .. i]
        if chatFrame ~= _G.COMBATLOG then
            self:RawHook(chatFrame, "AddMessage", true)
        end
    end
end

function Alts:UnhookChatFrames()
    for i = 1, _G.NUM_CHAT_WINDOWS do
        local chatFrame = _G["ChatFrame" .. i]
        if chatFrame ~= _G.COMBATLOG then
            self:Unhook(chatFrame, "AddMessage")
        end
    end
end

local ChatColorCodeFmt = "|c%02x%02x%02x%02x"
local function GetChatColorCode(c)
	if not c then return "" end
	return ChatColorCodeFmt:format(c.a * 255, c.r * 255, c.g * 255, c.b * 255)
end

local MainChatColor = ""
function Alts:SetMainChatColorCode()
	if self.db.profile.useMainNameColor then
		MainChatColor = GetChatColorCode(self.db.profile.mainNameColor)
	else
		MainChatColor = ""
	end
end

local function AddMainNameForChat(message, name)
		if not (name and #name > 0) then return end
		local lowerName = name:lower()
		if name ~= playerName and lowerName ~= playerFullNameLower then
			local main = AltsDB:GetMainForAlt(name)
			if main and #main > 0 then
				local messageFmt = "%s (%s%s|r)"
				return messageFmt:format(message, MainChatColor,
							AltsDB:FormatUnitName(main, true))
			end
		end

		return message
end

function Alts:AddMessage(frame, text, ...)
    -- If we are monitoring chat and the message is text then try to rewrite it.
    if monitor and text and _G.type(text) == "string" then
        text = text:gsub("(|Hplayer:([^:%]]+).-|h.-|h)", AddMainNameForChat)
    end
    return self.hooks[frame].AddMessage(frame, text, ...)
end

function Alts:CheckAndUpdateFriends()
    local friends = {}
    local numFriends = C_FriendList.GetNumFriends()
    local strFmt = L["FriendsLog_RemovedFriend"]

    for i = 1, numFriends do
        local info = C_FriendList.GetFriendInfoByIndex(i) or {}
		local name = info.name
        if name and name ~= "" then
            friends[name] = (info.note or "")
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
    local numIgnores = C_FriendList.GetNumIgnores()
    local strFmt = L["IgnoreLog_RemovedIgnore"]

    local name, value

    for i = 1, numIgnores do
        name = C_FriendList.GetIgnoreName(i)
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

function Alts:GetCurrentTimestamp()
	return _G.date("%Y/%m/%d %H:%M")
end

function Alts:UpdateMatchMethods()
	wipe(self.matchFuncs)

	if not self.db.profile.altMatching then
		self:Print("Error: No alt matching rules found.")
		return
	end

	if self.db.profile.altMatching.methods then
		for i, v in ipairs(self.db.profile.altMatching.methods) do
			if v.enabled and v.regex and _G.type(v.regex) == "string" then
				local f = v.regex
				tinsert(self.matchFuncs,
					function(val)
				        return val:match(f)
					end
				)
			end
		end
	else
		self:Print("No pre-configured alt matching rules found.")
	end

	if self.db.profile.altMatching.customMethods then
		for i, v in ipairs(self.db.profile.altMatching.customMethods) do
			if v.enabled and v.regex and _G.type(v.regex) == "string" then
				local f = v.regex
				tinsert(self.matchFuncs,
					function(val)
				        return val:match(f)
					end
				)
			end
		end
	end
end

function Alts:UpdateGuild()
	guildUpdateTimer = nil
	if not self.db.profile.autoGuildImport then return end

	local realm = ""
    local guildName, pRank, pRankNum, guildRealm = _G.GetGuildInfo("player")
	if not guildRealm or guildRealm == "" then
		-- The guild is local to this server
		realm = playerRealmAbbr
	else
		realm = guildRealm
	end

    local numMembers = _G.GetNumGuildMembers(true)

    if not guildName or numMembers == 0 then return end

    local source = LibAlts.GUILD_PREFIX..guildName

    AltsDB:RemoveSource(source)

    local guildMembers = {}
    local numAlts = 0
    local numMains = 0

    -- Build a list of the guild members
    -- Using it later to verify that names are in the guild
    for i = 1, numMembers do
        local name, rank, rankIndex, level, class, zone, publicnote,
            officernote, online, status, classFileName, achPts,
            achRank, isMobile, canSoR = _G.GetGuildRosterInfo(i)
        local years, months, days, hours = _G.GetGuildRosterLastOnline(i)

        local lastOnline = 0
        if online then
            lastOnline = _G.time()
        elseif years and months and days and hours then
            local diff = (((years*365)+(months*30)+days)*24+hours)*60*60
            lastOnline = _G.time() - diff
        end
        guildMembers[name] = lastOnline
    end

    -- Save the information if we're tracking the guild.
    if self.db.profile.saveGuild then
        local nameWithMainFmt = "%s (" .. L["Main: "] .. "%s)"
        -- Before updating the saved guild info, check for the differences.
        self.db.realm.guilds[guildName] = self.db.realm.guilds[guildName] or {}
        self.db.realm.guildLog[guildName] = self.db.realm.guildLog[guildName] or {}
		local updates = 0

        if next(self.db.realm.guilds[guildName]) then
			if self.db.profile.debug then self:Print("Checking guild for updates...") end
            -- Compare the new guild roster to the old
            local name, lastOnline
            local joinFmt = "%s "..L["GuildLog_JoinedGuild"]
            local joinLogFmt = "%s  %s "..L["GuildLog_JoinedGuild"]
            for name, lastOnline in pairs(guildMembers) do
                if self.db.realm.guilds[guildName][name] == nil then
                    if self.db.profile.reportGuildChanges == true and
						self.db.profile.reportTo == "Chat" then
                        self:Print(joinFmt:format(name))
                    end
                    tinsert(self.db.realm.guildLog[guildName],
                        joinLogFmt:format(self:GetCurrentTimestamp(), name))
					updates = updates + 1
                end
            end

            local leaveFmt = "%s "..L["GuildLog_LeftGuild"]
            local leaveLogFmt = "%s  %s "..L["GuildLog_LeftGuild"]
            for name, lastOnline in pairs(self.db.realm.guilds[guildName]) do
                if guildMembers[name] == nil then
                    local nameWithMain = name
                    local main = AltsDB:GetMain(name)
                    if main and #main > 0 then
                        nameWithMain = nameWithMainFmt:format(name,
							AltsDB:FormatUnitName(main, true))
                    end
                    if self.db.profile.reportGuildChanges == true and
						self.db.profile.reportTo == "Chat" then
                        self:Print(leaveFmt:format(nameWithMain))
                    end
                    tinsert(self.db.realm.guildLog[guildName],
                        leaveLogFmt:format(self:GetCurrentTimestamp(),
							nameWithMain))
					updates = updates + 1
                end
            end
			if self.db.profile.reportGuildChanges and
				self.db.profile.reportTo == "GuildLog" and updates > 0
				and not _G.UnitAffectingCombat("player") then
				self:ShowGuildLogFrame()
			end
        end

        -- Update the saved guild information
        self.db.realm.guilds[guildName] = guildMembers
    end

    -- Walk through the list and look for alt names
    for i = 1, numMembers do
        local name, rank, rankIndex, level, class, zone, publicnote,
            officernote, online, status, classFileName, achPts,
            achRank, isMobile, canSoR = _G.GetGuildRosterInfo(i)
        local years, months, days, hours = _G.GetGuildRosterLastOnline(i)

        local main
        for i,v in ipairs(self.matchFuncs) do
			main = nil
            local badRefFmt = L["Reference to a non-existent main %s for %s."]

			if officernote and #officernote > 0 then
	            main = AltsDB:FormatUnitName(v(officernote))
	            if main and #main > 0 then
	                if guildMembers[main] then
	                    break
					elseif not AltsDB:HasRealm(main) and
						guildMembers[AltsDB:FormatNameWithRealm(main,realm)] then
						main = AltsDB:FormatNameWithRealm(main,realm)
						break
	                elseif main ~= AltsDB:FormatUnitName(officernote) then
	                    if self.db.profile.reportMissingMains then
	                        self:Print(badRefFmt:format(main, name))
	                    end
	                end
	            end
			end

			if publicnote and #publicnote > 0 then
	            main = AltsDB:FormatUnitName(v(publicnote))
	            if main and #main > 0 then
	                if guildMembers[main] then
	                    break
					elseif not AltsDB:HasRealm(main) and
						guildMembers[AltsDB:FormatNameWithRealm(main,realm)] then
						main = AltsDB:FormatNameWithRealm(main,realm)
						break
	                elseif main ~= AltsDB:FormatUnitName(publicnote) then
	                    if self.db.profile.reportMissingMains then
	                        self:Print(badRefFmt:format(main, name))
	                    end
	                end
	            end
			end
        end

        -- Check if we found a valid alt name
        if main and #main > 0 then
            if guildMembers[main] then
                -- If the main doesn't exist yet, then increase the counter
                if not AltsDB:GetAltsForSource(main, source) then
                    numMains = numMains + 1
                end
                -- Add the main-alt relationship for this guild
                AltsDB:SetAlt(main, name, source)
                numAlts = numAlts + 1
            end
        end
    end

    -- Create the reverse lookup table
	AltsDB:UpdateMainsBySource(source)

    local importFormat = L["Imported the guild '%s'. Mains: %d, Alts: %d."]
    self:Print(importFormat:format(guildName, numMains, numAlts))
end

function Alts:SetAltEvent(event, main, alt, source)
    if main then self:UpdateMainsTable(main) end
end

function Alts:DeleteAltEvent(event, main, alt, source)
    if main then self:UpdateMainsTable(main) end
end

function Alts:RemoveSourceEvent(event, source)
    self:UpdateMainsTable()
end

function Alts:UpdateMainsTable(main)
    local altList
    local alts
    if not main then
        local allMains = {}
        AltsDB:GetAllMains(allMains)
        wipe(MainsTable)
        for i, name in pairs(allMains) do
            altList = AltsDB:FormatUnitList(", ", true, AltsDB:GetAlts(name)) or ""
			if MainsTable[main] then
			else
				tinsert(MainsTable, {AltsDB:FormatUnitName(name, true), altList, AltsDB:FormatUnitName(name, false)})
			end
        end
	else
        main = AltsDB:FormatUnitName(main, false)
		local row
		for i = #MainsTable, 1, -1 do
			row = MainsTable[i]
            if row and row[3] == main then
                -- Remove the existing entry
                tremove(MainsTable, i)
                break
            end
        end

        altList = AltsDB:FormatUnitList(", ", true, AltsDB:GetAlts(main)) or ""
        tinsert(MainsTable, {AltsDB:FormatUnitName(main, true), altList, AltsDB:FormatUnitName(main, false)})
    end

    if altsFrame and altsFrame:IsVisible() then
        altsFrame.table:SortData()
    end
end

function Alts:AltsDebugHandler(input)
	if input and #input > 0 and input == "on" then
		self.db.profile.debug = true
		self:Print("Debugging enabled.")
	elseif input and #input > 0 and input == "off" then
		self.db.profile.debug = false
		self:Print("Debugging disabled.")
	else
		self:Print("Debugging is "..(self.db.profile.debug and "on" or "off"))
	end
end

function Alts:OnInitialize()
    -- Called when the addon is loaded
    self.db = LibStub("AceDB-3.0"):New("AltsDB", defaults, "Default")
	addon.db = self.db

	self.logonTime = self:GetCurrentTimestamp()

	AltsDB:OnInitialize(self)

    -- Register callbacks for LibAlts
	-- Occurs after the AltsDB registration of callbacks so it recieves
	-- the calls after the data has been handled.
    LibAlts.RegisterCallback(self, "LibAlts_SetAlt", "SetAltEvent")
    LibAlts.RegisterCallback(self, "LibAlts_RemoveAlt", "DeleteAltEvent")
    LibAlts.RegisterCallback(self, "LibAlts_RemoveSource", "RemoveSourceEvent")

    -- Register the options table
    local displayName = addon.addonTitle
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
	self.optionsFrame.Formats = ACD:AddToBlizOptions(
	    displayName, L["Note Formats"], displayName, "formats")
	ACD:AddToBlizOptions(
	    displayName, options.args.profile.name, displayName, "profile")

	self:RegisterChatCommand("alts", "AltsHandler")
	self:RegisterChatCommand("altsdebug", "AltsDebugHandler")
	self:RegisterChatCommand("setmain", "SetMainHandler")
	self:RegisterChatCommand("delalt", "DelAltHandler")
	self:RegisterChatCommand("getalts", "GetAltsHandler")
	self:RegisterChatCommand("getmain", "GetMainHandler")
	self:RegisterChatCommand("isalt", "IsAltHandler")
	self:RegisterChatCommand("ismain", "IsMainHandler")
	self:RegisterChatCommand("getallmains", "GetAllMainsHandler")
	self:RegisterChatCommand("guildlog", "GuildLogHandler")
	self:RegisterChatCommand("guildexport", "GuildExportHandler")
	self:RegisterChatCommand("getbnet", "GetBnetHandler")

	-- Create the LDB launcher
	altsLDB = LDB:NewDataObject("Alts",{
		type = "launcher",
		icon = "Interface\\Icons\\Achievement_GuildPerk_EverybodysFriend.blp",
		OnClick = function(clickedframe, button)
    		if button == "RightButton" then
    			if addon.IsGameOptionsVisible() then
    				addon.HideGameOptions()
    			else
    			    self:HideAltsWindow()
    				self:ShowOptions()
    			end
    		elseif button == "LeftButton" then
    			if self:IsVisible() then
    				self:HideAltsWindow()
    			else
					addon.HideGameOptions()
    				self:AltsHandler("")
    			end
            end
		end,
		OnTooltipShow = function(tooltip)
			if tooltip and tooltip.AddLine then
				tooltip:AddLine(GREEN .. L["Alts"].." "..addon.addonVersion)
				tooltip:AddLine(YELLOW .. L["Left click"] .. " " .. WHITE
					.. L["to open/close the window"])
				tooltip:AddLine(YELLOW .. L["Right click"] .. " " .. WHITE
					.. L["to open/close the configuration."])
			end
		end
	})
	icon:Register("AltsLDB", altsLDB, self.db.profile.minimap)

	playerName = _G.UnitName("player")
	playerRealm = _G.GetRealmName()
	playerRealmAbbr = AltsDB:FormatRealmName(playerRealm)
	playerFullName = AltsDB:FormatNameWithRealm(playerName, playerRealm)
	playerFullNameLower = playerFullName:lower()

	for name, obj in pairs(addon.modules) do
		if obj and obj.OnInitialize then
			obj:OnInitialize()
		end
	end
end

function Alts:SetMainHandler(input)
	if input and #input > 0 then
		local alt, main = string.match(input, "^(%S+) *(.*)")
		if main and #main > 0 then
	    	AltsDB:SetAlt(main, alt)

			if self.db.profile.verbose == true then
				local strFormat = L["Set main for %s: %s"]
				self:Print(strFormat:format(AltsDB:FormatUnitName(main), AltsDB:FormatUnitName(alt)))
			end
		else
		    main = AltsDB:GetMain(alt)

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
    _G.StaticPopupDialogs["ALTS_SET_MAIN"] = _G.StaticPopupDialogs["ALTS_SET_MAIN"] or {
        text = "Set the main for %s",
        maintext = "",
        button1 = _G.OKAY,
        button2 = _G.CANCEL,
        hasEditBox = true,
        hasWideEditBox = true,
        enterClicksFirstButton = true,
        OnShow = function(this, data)
            this.wideEditBox:SetText(_G.StaticPopupDialogs["ALTS_SET_MAIN"].maintext or "")
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

    _G.StaticPopupDialogs["ALTS_SET_MAIN"].maintext = main
    _G.StaticPopup_Show("ALTS_SET_MAIN", alt)
end

function Alts:DelAltHandler(input)
	if input and #input > 0 then
		local alt, main = string.match(input, "^(%S+) *(.*)")
		if main and #main > 0 then
		    AltsDB:DeleteAlt(main, alt)

			if self.db.profile.verbose == true then
				local strFormat = L["Deleted alt %s for %s"]
				self:Print(strFormat:format(AltsDB:FormatUnitName(alt), AltsDB:FormatUnitName(main)))
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
        local sourceUsed = ""
		if source and #source > 0 then
            isMain = LibAlts:IsMainForSource(name, source)
            sourceUsed = sourceFmt:format(source)
        else
            isMain = LibAlts:IsMain(name)
        end

        local result = ""
        if not isMain then result = "not " end

        self:Print(outputFmt:format(AltsDB:FormatUnitName(name), result, sourceUsed))
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
        local sourceUsed = ""
		if source and #source > 0 then
            isAlt = LibAlts:IsAltForSource(name, source)
            sourceUsed = sourceFmt:format(source)
        else
            isAlt = LibAlts:IsAlt(name)
        end

        local result = ""
        if not isAlt then result = "not " end

        self:Print(outputFmt:format(AltsDB:FormatUnitName(name), result, sourceUsed))
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
		local main, alts = AltsDB:GetAltsForMain(input, true)
		if alts and #alts > 0 then
            local altList = AltsDB:FormatUnitList(", ", true, unpack(alts))
            local strFormat = L["Alts for %s: %s"]
		    self:Print(strFormat:format(AltsDB:FormatUnitName(main), altList))
		else
		    self:Print(L["No alts found for "]..input)
		end
	else
		self:Print(L["Usage: /getalts <main>"])
	end
end

function Alts:GetMainHandler(input)
	if input and #input > 0 then
		local main, altFound = AltsDB:GetMainForAlt(input)

		if main and #main > 0 then
            local strFormat = L["Main for %s: %s"]
		    self:Print(strFormat:format(AltsDB:FormatUnitName(altFound), AltsDB:FormatUnitName(main)))
		else
		    self:Print(L["No main found for "]..input)
		end
	else
		self:Print(L["Usage: /getmain <alt>"])
	end
end

function Alts:GetBnetHandler(input)
	local fmt = "%s: %s"
	if input and #input > 0 then
		local results = AltsDB:FindBNetAccount(input)
		for i, battleTag in _G.ipairs(results) do
			local account = AltsDB:GetBNetAccount(battleTag) or {}
			local names = addon.getTableKeys(account)
			_G.table.sort(names)
			local list = tconcat(names, ", ")
			self:Print(fmt:format(battleTag or "-", list))
		end
	end
end

function Alts:AddAltHandler(main)
	if main and #main > 0 then
        --self:StaticPopupSetMain(alt, main)
	    addAltFrame.charname:SetText(AltsDB:FormatUnitName(main))
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
        local guildName = _G.GetGuildInfo("player")
        if not guildName then return end
        if not self.db.realm.guildLog[guildName] then return end

        scroll:ReleaseChildren()
        scroll:PauseLayout()
        local count = 0
		local marked = false
        local entries = #self.db.realm.guildLog[guildName]
        for i = entries, 1, -1 do
            local text = self.db.realm.guildLog[guildName][i]
            if text then
				if not marked and text:sub(1,16) < self.logonTime then
					if i < entries then
		                local separator = AGU:Create("Heading")
						separator:SetText("")
		                separator:SetFullWidth(true)
		                scroll:AddChild(separator)
					end
					marked = true
				end
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
	if C_GuildInfo and C_GuildInfo.GuildRoster then
		C_GuildInfo.GuildRoster()
	else
		_G.GuildRoster()
	end

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
                self.db.profile.exportUseAlts,
                self.db.profile.exportEscape
            )
			local exportStatusFmt = L["GuildExport_StatusFormat"]
			local clipboardCopy = L["ClipboardCopy_Default"]
			if _G.IsMacClient() then
				clipboardCopy = L["ClipboardCopy_Mac"]
			end
			frame:SetStatusText(
				exportStatusFmt:format(numChars) .. " " .. clipboardCopy)
            frame.multiline:SetText(guildExportText)
			frame.multiline:SetFocus()
        end)
    frame:AddChild(exportButton)
end

local ExportFrame = nil
function Alts:ShowExportFrame(exportFunc)
    if not exportFunc or _G.type(exportFunc) ~= "function" then return end

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
	local addalt = _G.CreateFrame("Frame", "Alts_AddAltWindow", _G.UIParent, BackdropTemplateMixin and "BackdropTemplate")
	addalt:SetFrameStrata("DIALOG")
	addalt:SetToplevel(true)
	addalt:SetWidth(400)
	addalt:SetHeight(200)
	addalt:SetPoint("CENTER", _G.UIParent)
	addalt:SetBackdrop(
		{bgFile="Interface\\ChatFrame\\ChatFrameBackground",
	    edgeFile="Interface\\DialogFrame\\UI-DialogBox-Border", tile=true,
		tileSize=32, edgeSize=32, insets={left=11, right=12, top=12, bottom=11}})
	addalt:SetBackdropColor(0,0,0,1)

	local editbox = _G.CreateFrame("EditBox", nil, addalt, "AutoCompleteEditBoxTemplate")
	editbox.autoCompleteParams = _G.AUTOCOMPLETE_LIST.ALL
	editbox:SetFontObject(_G.ChatFontNormal)
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

	local savebutton = _G.CreateFrame("Button", nil, addalt, "UIPanelButtonTemplate")
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

	local cancelbutton = _G.CreateFrame("Button", nil, addalt, "UIPanelButtonTemplate")
	cancelbutton:SetText(L["Cancel"])
	cancelbutton:SetWidth(100)
	cancelbutton:SetHeight(20)
	cancelbutton:SetPoint("BOTTOM", addalt, "BOTTOM", 60, 20)
	cancelbutton:SetScript("OnClick",
	    function(this)
	        this:GetParent():Hide()
	        editAltsFrame:Show()
	    end)

	local headertext = addalt:CreateFontString("Alts_HeaderText", "OVERLAY", "GameFontNormalLarge")
	headertext:SetPoint("TOP", addalt, "TOP", 0, -20)
	headertext:SetText(L["Add Alt"])

	local charname = addalt:CreateFontString("Alts_CharName", "OVERLAY", "GameFontNormal")
	charname:SetPoint("BOTTOM", headertext, "BOTTOM", 0, -40)
	charname:SetFont(charname:GetFont(), 14)
	charname:SetTextColor(1.0,1.0,1.0,1)

	addalt.charname = charname
	addalt.editbox = editbox

    addalt:SetMovable(true)
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
	local addmain = _G.CreateFrame("Frame", "Alts_AddMainWindow", _G.UIParent, BackdropTemplateMixin and "BackdropTemplate")
	addmain:SetFrameStrata("DIALOG")
	addmain:SetToplevel(true)
	addmain:SetWidth(400)
	addmain:SetHeight(200)
	addmain:SetPoint("CENTER", _G.UIParent)
	addmain:SetBackdrop(
		{bgFile="Interface\\ChatFrame\\ChatFrameBackground",
	    edgeFile="Interface\\DialogFrame\\UI-DialogBox-Border", tile=true,
		tileSize=32, edgeSize=32, insets={left=11, right=12, top=12, bottom=11}})
	addmain:SetBackdropColor(0,0,0,1)

	local headertext = addmain:CreateFontString("Alts_AddMain_HeaderText", "OVERLAY", "GameFontNormalLarge")
	headertext:SetPoint("TOP", addmain, "TOP", 0, -20)
	headertext:SetText(L["Add Main"])

	local mainlabel = addmain:CreateFontString("Alts_AddMain_MainLabel", "OVERLAY", "GameFontNormal")
	mainlabel:SetText(L["Main: "])
	mainlabel:SetPoint("TOP", headertext, "BOTTOM", 0, -30)
	mainlabel:SetPoint("LEFT", addmain, "LEFT", 20, 0)

	local mainname = _G.CreateFrame("EditBox", "Alts_AddMain_MainName", addmain, "AutoCompleteEditBoxTemplate")
	mainname.autoCompleteParams = _G.AUTOCOMPLETE_LIST.ALL
	mainname:SetFontObject(_G.ChatFontNormal)
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

	local altlabel = addmain:CreateFontString("Alts_AddMain_AltLabel", "OVERLAY", "GameFontNormal")
	altlabel:SetText(L["Alt: "])
	altlabel:SetPoint("TOPLEFT", mainlabel, "BOTTOMLEFT", 0, -30)

	local altname = _G.CreateFrame("EditBox", "Alts_AddMain_AltName", addmain, "AutoCompleteEditBoxTemplate")
	altname.autoCompleteParams = _G.AUTOCOMPLETE_LIST.ALL
	altname:SetFontObject(_G.ChatFontNormal)
	altname:SetWidth(150)
	altname:SetHeight(35)
	altname:SetPoint("TOP", altlabel, "TOP")
	altname:SetPoint("LEFT", mainname, "LEFT")
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

	local savebutton = _G.CreateFrame("Button", nil, addmain, "UIPanelButtonTemplate")
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

	local cancelbutton = _G.CreateFrame("Button", nil, addmain, "UIPanelButtonTemplate")
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

    addmain:SetMovable(true)
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

function Alts:CreateAltsFrame()
	local altswindow = _G.CreateFrame("Frame", "Alts_AltsWindow", _G.UIParent, BackdropTemplateMixin and "BackdropTemplate")
	altswindow:SetFrameStrata("DIALOG")
	altswindow:SetToplevel(true)
	altswindow:SetWidth(630)
	altswindow:SetHeight(430)
	if self.db.profile.remember_main_pos then
        altswindow:SetPoint("CENTER", _G.UIParent, "CENTER",
            self.db.profile.main_window_x, self.db.profile.main_window_y)
    else
	    altswindow:SetPoint("CENTER", _G.UIParent)
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

	local headertext = altswindow:CreateFontString("Alts_Notes_HeaderText", "OVERLAY", "GameFontNormalLarge")
	headertext:SetPoint("TOP", altswindow, "TOP", 0, -20)
	headertext:SetText(L["Alts"])

	local searchterm = _G.CreateFrame("EditBox", nil, altswindow, "InputBoxTemplate")
	searchterm:SetFontObject(_G.ChatFontNormal)
	searchterm:SetWidth(300)
	searchterm:SetHeight(35)
	searchterm:SetPoint("TOPLEFT", altswindow, "TOPLEFT", 25, -50)
	searchterm:SetScript("OnShow", function(this) searchterm:SetFocus() end)
	searchterm:SetScript("OnEnterPressed", function(this) this:GetParent().table:SortData() end)
	searchterm:SetScript("OnEscapePressed", function(this) this:SetText(""); this:GetParent():Hide(); end)

	table.frame:SetPoint("TOP", searchterm, "BOTTOM", 0, -20)
	table.frame:SetPoint("LEFT", altswindow, "LEFT", 20, 0)

	local searchbutton = _G.CreateFrame("Button", nil, altswindow, "UIPanelButtonTemplate")
	searchbutton:SetText(L["Search"])
	searchbutton:SetWidth(100)
	searchbutton:SetHeight(20)
	searchbutton:SetPoint("LEFT", searchterm, "RIGHT", 10, 0)
	searchbutton:SetScript("OnClick", function(this) this:GetParent().table:SortData() end)

	local clearbutton = _G.CreateFrame("Button", nil, altswindow, "UIPanelButtonTemplate")
	clearbutton:SetText(L["Clear"])
	clearbutton:SetWidth(100)
	clearbutton:SetHeight(20)
	clearbutton:SetPoint("LEFT", searchbutton, "RIGHT", 10, 0)
	clearbutton:SetScript("OnClick", function(this) this:GetParent().searchterm:SetText(""); this:GetParent().table:SortData(); end)

	local closebutton = _G.CreateFrame("Button", nil, altswindow, "UIPanelButtonTemplate")
	closebutton:SetText(L["Close"])
	closebutton:SetWidth(90)
	closebutton:SetHeight(20)
	closebutton:SetPoint("BOTTOM", altswindow, "BOTTOM", 0, 20)
	closebutton:SetScript("OnClick", function(this) this:GetParent():Hide(); end)

	local addbutton = _G.CreateFrame("Button", nil, altswindow, "UIPanelButtonTemplate")
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

	local deletebutton = _G.CreateFrame("Button", nil, altswindow, "UIPanelButtonTemplate")
	deletebutton:SetText(L["Delete"])
	deletebutton:SetWidth(90)
	deletebutton:SetHeight(20)
	deletebutton:SetPoint("BOTTOM", altswindow, "BOTTOM", 0, 70)
	deletebutton:SetScript("OnClick",
		function(this)
		    local frame = this:GetParent()
			if frame.table:GetSelection() then
				local row = frame.table:GetRow(frame.table:GetSelection())
				if row[3] and #row[3] > 0 then
					confirmMainDeleteFrame.mainname:SetText(row[3])
					confirmMainDeleteFrame:Show()
					confirmMainDeleteFrame:Raise()
					altsFrame:Hide()
				end
			end
		end)

	local editbutton = _G.CreateFrame("Button", nil, altswindow, "UIPanelButtonTemplate")
	editbutton:SetText(L["Edit"])
	editbutton:SetWidth(90)
	editbutton:SetHeight(20)
	editbutton:SetPoint("BOTTOM", altswindow, "BOTTOM", 120, 70)
	editbutton:SetScript("OnClick",
		function(this)
		    local frame = this:GetParent()
			if frame.table:GetSelection() then
				local row = frame.table:GetRow(frame.table:GetSelection())
				if row[3] and #row[3] > 0 then
				    frame:Hide()
					self:EditAltsHandler(row[3])
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
				local term = searchterm:lower()
				if row[1]:lower():find(term) or row[2]:lower():find(term) or
					row[3]:lower():find(term) then
					return true
				end

				return false
			else
				return true
			end
		end
	)

    altswindow.lock = self.db.profile.lock_main_window

    altswindow:SetMovable(true)
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
    			local scale = self:GetEffectiveScale() / _G.UIParent:GetEffectiveScale()
    			local x, y = self:GetCenter()
    			x, y = x * scale, y * scale
    			x = x - _G.GetScreenWidth()/2
    			y = y - _G.GetScreenHeight()/2
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
	addon.HideGameOptions()

	altsFrame:Show()
	altsFrame:Raise()
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
	if not _G.IsInGuild() then return 0, "" end

    local guildName = _G.GetGuildInfo("player")
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

    local numMembers = _G.GetNumGuildMembers()
    local exportChar

    if not guildName or not numMembers or numMembers == 0 then return 0, "" end

    for i = 1, numMembers do
        local name, rank, rankIndex, level, class, zone, publicnote,
            officernote, online, status, classFileName, achPts,
            achRank, isMobile, canSoR = _G.GetGuildRosterInfo(i)

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
                tinsert(fields, tostring(AltsDB:FormatUnitName(name, false) or ""))
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
                local years, months, days, hours = _G.GetGuildRosterLastOnline(i)
                local lastOnline = 0
                if online then
                    lastOnline = _G.time()
                elseif years and months and days and hours then
                    local diff = (((years*365)+(months*30)+days)*24+hours)*60*60
                    lastOnline = _G.time() - diff
                end
                tinsert(fields, tostring(_G.date("%Y/%m/%d", lastOnline)) or "")
            end

            if self.db.profile.exportUseAchvPoints == true then
                tinsert(fields, tostring(achPts or ""))
            end

            if self.db.profile.exportUseAlts == true then
                local altsStr = ""
                if self.db.profile.exportOnlyGuildAlts == true then
                    altsStr = AltsDB:FormatUnitList(delimiter, false, LibAlts:GetAltsForSource(name, source)) or ""
                else
                    altsStr = AltsDB:FormatUnitList(delimiter, false, LibAlts:GetAlts(name)) or ""
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
	local editaltswindow = _G.CreateFrame("Frame", "Alts_EditAltsWindow", _G.UIParent, BackdropTemplateMixin and "BackdropTemplate")
	editaltswindow:SetFrameStrata("DIALOG")
	editaltswindow:SetToplevel(true)
	editaltswindow:SetWidth(400)
	editaltswindow:SetHeight(300)
	editaltswindow:SetPoint("CENTER", _G.UIParent)
	editaltswindow:SetBackdrop(
		{bgFile="Interface\\ChatFrame\\ChatFrameBackground",
	    edgeFile="Interface\\DialogFrame\\UI-DialogBox-Border", tile=true,
		tileSize=32, edgeSize=32, insets={left=11, right=12, top=12, bottom=11}})
	editaltswindow:SetBackdropColor(0,0,0,1)

	local headertext = editaltswindow:CreateFontString("Alts_Confirm_HeaderText", "OVERLAY", "GameFontNormalLarge")
	headertext:SetPoint("TOP", editaltswindow, "TOP", 0, -20)
	headertext:SetText(L["Edit Alts"])

	local charname = editaltswindow:CreateFontString("Alts_Edit_CharName", "OVERLAY", "GameFontNormal")
	charname:SetPoint("BOTTOM", headertext, "BOTTOM", 0, -40)
	charname:SetFont(charname:GetFont(), 14)
	charname:SetTextColor(1.0,1.0,1.0,1)

	local cols = {}
	cols[1] = {
		["name"] = L["Alt Name"],
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
		["defaultsort"] = "dsc",
		["sort"] = "dsc",
		["DoCellUpdate"] = nil,
	}

	local table = ScrollingTable:CreateST(cols, 5, nil, nil, editaltswindow);

	table.frame:SetPoint("TOP", charname, "BOTTOM", 0, -30)
	table.frame:SetPoint("CENTER", editaltswindow, "CENTER", 0, 0)

	local addbutton = _G.CreateFrame("Button", nil, editaltswindow, "UIPanelButtonTemplate")
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

	local deletebutton = _G.CreateFrame("Button", nil, editaltswindow, "UIPanelButtonTemplate")
	deletebutton:SetText(L["Delete"])
	deletebutton:SetWidth(100)
	deletebutton:SetHeight(20)
	deletebutton:SetPoint("BOTTOM", editaltswindow, "BOTTOM", 0, 20)
	deletebutton:SetScript("OnClick",
    	function(this)
    	    local frame = this:GetParent()
    		if frame.table:GetSelection() then
    			local row = frame.table:GetRow(frame.table:GetSelection())
    			if row[2] and #row[2] > 0 then
    				confirmDeleteFrame.mainname:SetText(AltsDB:FormatUnitName(frame.charname:GetText()))
    				confirmDeleteFrame.altname:SetText(AltsDB:FormatUnitName(row[2], false))
    				confirmDeleteFrame:Show()
    				frame:Hide()
    			end
    		end
    	end)

	local closebutton = _G.CreateFrame("Button", nil, editaltswindow, "UIPanelButtonTemplate")
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

    editaltswindow:SetMovable(true)
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
	local setmain = _G.CreateFrame("Frame", "Alts_SetMainWindow", _G.UIParent, BackdropTemplateMixin and "BackdropTemplate")
	setmain:SetFrameStrata("DIALOG")
	setmain:SetToplevel(true)
	setmain:SetWidth(400)
	setmain:SetHeight(200)
	setmain:SetPoint("CENTER", _G.UIParent)
	setmain:SetBackdrop(
		{bgFile="Interface\\ChatFrame\\ChatFrameBackground",
	    edgeFile="Interface\\DialogFrame\\UI-DialogBox-Border", tile=true,
		tileSize=32, edgeSize=32, insets={left=11, right=12, top=12, bottom=11}})
	setmain:SetBackdropColor(0,0,0,1)

	local editbox = _G.CreateFrame("EditBox", nil, setmain, "AutoCompleteEditBoxTemplate")
	editbox.autoCompleteParams = _G.AUTOCOMPLETE_LIST.ALL
	--local editbox = _G.CreateFrame("EditBox", nil, setmain, "InputBoxTemplate")
	editbox:SetFontObject(_G.ChatFontNormal)
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

	local savebutton = _G.CreateFrame("Button", nil, setmain, "UIPanelButtonTemplate")
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

	local cancelbutton = _G.CreateFrame("Button", nil, setmain, "UIPanelButtonTemplate")
	cancelbutton:SetText(L["Cancel"])
	cancelbutton:SetWidth(100)
	cancelbutton:SetHeight(20)
	cancelbutton:SetPoint("BOTTOM", setmain, "BOTTOM", 60, 20)
	cancelbutton:SetScript("OnClick", function(this) this:GetParent():Hide(); end)

	local headertext = setmain:CreateFontString("Alts_HeaderText", "OVERLAY", "GameFontNormalLarge")
	headertext:SetPoint("TOP", setmain, "TOP", 0, -20)
	headertext:SetText(L["Set Main"])

	local charname = setmain:CreateFontString("Alts_CharName", "OVERLAY", "GameFontNormal")
	charname:SetPoint("BOTTOM", headertext, "BOTTOM", 0, -40)
	charname:SetFont(charname:GetFont(), 14)
	charname:SetTextColor(1.0,1.0,1.0,1)

	setmain.charname = charname
	setmain.editbox = editbox

    setmain:SetMovable(true)
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
	local deletewindow = _G.CreateFrame("Frame", "Alts_ConfirmDeleteWindow", _G.UIParent, BackdropTemplateMixin and "BackdropTemplate")
	deletewindow:SetFrameStrata("DIALOG")
	deletewindow:SetToplevel(true)
	deletewindow:SetWidth(400)
	deletewindow:SetHeight(250)
	deletewindow:SetPoint("CENTER", _G.UIParent)
	deletewindow:SetBackdrop(
		{bgFile="Interface\\ChatFrame\\ChatFrameBackground",
	    edgeFile="Interface\\DialogFrame\\UI-DialogBox-Border", tile=true,
		tileSize=32, edgeSize=32, insets={left=11, right=12, top=12, bottom=11}})
	deletewindow:SetBackdropColor(0,0,0,1)

	local headertext = deletewindow:CreateFontString("Alts_Confirm_HeaderText", "OVERLAY", "GameFontNormalLarge")
	headertext:SetPoint("TOP", deletewindow, "TOP", 0, -20)
	headertext:SetText(L["Delete Alt"])

	local warningtext = deletewindow:CreateFontString("Alts_Confirm_WarningText", "OVERLAY", "GameFontNormalLarge")
	warningtext:SetPoint("TOP", headertext, "TOP", 0, -50)
	warningtext:SetText(L["Are you sure you wish to remove"])

	local altname = deletewindow:CreateFontString("Alts_Confirm_CharName", "OVERLAY", "GameFontNormal")
	altname:SetPoint("BOTTOM", warningtext, "BOTTOM", 0, -30)
	altname:SetFont(altname:GetFont(), 14)
	altname:SetTextColor(1.0,1.0,1.0,1)

	local warningtext2 = deletewindow:CreateFontString("Alts_Confirm_WarningText2", "OVERLAY", "GameFontNormalLarge")
	warningtext2:SetPoint("TOP", altname, "TOP", 0, -30)
	warningtext2:SetText(L["as an alt of"])

	local mainname = deletewindow:CreateFontString("Alts_Confirm_CharName", "OVERLAY", "GameFontNormal")
	mainname:SetPoint("BOTTOM", warningtext2, "BOTTOM", 0, -30)
	mainname:SetFont(mainname:GetFont(), 14)
	mainname:SetTextColor(1.0,1.0,1.0,1)

	local deletebutton = _G.CreateFrame("Button", nil, deletewindow, "UIPanelButtonTemplate")
	deletebutton:SetText(L["Delete"])
	deletebutton:SetWidth(100)
	deletebutton:SetHeight(20)
	deletebutton:SetPoint("BOTTOM", deletewindow, "BOTTOM", -60, 20)
	deletebutton:SetScript("OnClick",
	    function(this)
            AltsDB:DeleteAlt(mainname:GetText(), altname:GetText())
	        this:GetParent():Hide()
	        self:EditAltsHandler(mainname:GetText())
	    end)

	local cancelbutton = _G.CreateFrame("Button", nil, deletewindow, "UIPanelButtonTemplate")
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

    deletewindow:SetMovable(true)
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
	local deletewindow = _G.CreateFrame("Frame", "Alts_ConfirmMainDeleteWindow", _G.UIParent, BackdropTemplateMixin and "BackdropTemplate")
	deletewindow:SetFrameStrata("DIALOG")
	deletewindow:SetToplevel(true)
	deletewindow:SetWidth(400)
	deletewindow:SetHeight(200)
	deletewindow:SetPoint("CENTER", _G.UIParent)
	deletewindow:SetBackdrop(
		{bgFile="Interface\\ChatFrame\\ChatFrameBackground",
	    edgeFile="Interface\\DialogFrame\\UI-DialogBox-Border", tile=true,
		tileSize=32, edgeSize=32, insets={left=11, right=12, top=12, bottom=11}})
	deletewindow:SetBackdropColor(0,0,0,1)

	local headertext = deletewindow:CreateFontString("Alts_ConfirmDelMain_HeaderText", "OVERLAY", "GameFontNormalLarge")
	headertext:SetPoint("TOP", deletewindow, "TOP", 0, -20)
	headertext:SetText(L["Delete Main"])

	local warningtext = deletewindow:CreateFontString("Alts_ConfirmDelMain_WarningText", "OVERLAY", "GameFontNormalLarge")
	warningtext:SetPoint("TOP", headertext, "TOP", 0, -50)
	warningtext:SetWordWrap(true)
	warningtext:SetWidth(350)
	warningtext:SetText(L["Are you sure you wish to delete the main and all user-entered alts for:"])

	local mainname = deletewindow:CreateFontString("Alts_ConfirmDelMain_CharName", "OVERLAY", "GameFontNormal")
	mainname:SetPoint("BOTTOM", warningtext, "BOTTOM", 0, -30)
	mainname:SetFont(mainname:GetFont(), 14)
	mainname:SetTextColor(1.0,1.0,1.0,1)

	local deletebutton = _G.CreateFrame("Button", nil, deletewindow, "UIPanelButtonTemplate")
	deletebutton:SetText(L["Delete"])
	deletebutton:SetWidth(100)
	deletebutton:SetHeight(20)
	deletebutton:SetPoint("BOTTOM", deletewindow, "BOTTOM", -60, 20)
	deletebutton:SetScript("OnClick",
	    function(this)
	        AltsDB:DeleteUserMain(mainname:GetText())
	        this:GetParent():Hide()
            self:UpdateMainsTable()
            altsFrame.table:SortData()
            altsFrame:Show()
	    end)

	local cancelbutton = _G.CreateFrame("Button", nil, deletewindow, "UIPanelButtonTemplate")
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

    deletewindow:SetMovable(true)
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
		name = input
		editAltsFrame.charname:SetText(AltsDB:FormatUnitName(name))

        wipe(EditAltsTable)

        alts = { AltsDB:GetAlts(name) }

        for i, v in ipairs(alts) do
            tinsert(EditAltsTable, {AltsDB:FormatUnitName(v, true), AltsDB:FormatUnitName(v, false)})
        end

        editAltsFrame.table:SortData()
		editAltsFrame:Show()
		editAltsFrame:Raise()
	end
end

function Alts:SaveMainName(name, main)
	if name and #name > 0 and main and #main > 0 then
	    AltsDB:SetAlt(main, name)
	end

	setMainFrame.charname:SetText("")
	setMainFrame.editbox:SetText("")
end

function Alts:AddAltName(main, alt)
	if main and #main > 0 and alt and #alt > 0 then
	    AltsDB:SetAlt(main, alt)
	end

	addAltFrame.charname:SetText("")
	addAltFrame.editbox:SetText("")
end

function Alts:AddMainName(main, alt)
	if main and #main > 0 and alt and #alt > 0 then
	    AltsDB:SetAlt(main, alt)
	end

	addMainFrame.mainname:SetText("")
	addMainFrame.altname:SetText("")
end

local function OnTooltipSetUnit(tooltip, data, ...)
	Alts:OnTooltipSetUnit(tooltip, data, ...)
end

function Alts:OnEnable()
	AltsDB:OnEnable()

	self:SetMainChatColorCode()

	self:UpdateMatchMethods()

	-- Hook the game tooltip so we can add lines
	if TooltipDataProcessor then
		TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, OnTooltipSetUnit)
	else
		self:HookScript(_G.GameTooltip, "OnTooltipSetUnit")
	end

	-- Hook the friends frame tooltip
	--self:HookScript("FriendsFrameTooltip_Show")

	-- Register to receive the chat messages to watch for logons and who requests
	self:RegisterEvent("CHAT_MSG_SYSTEM")
	-- Watch for combat start and end events.
	self:RegisterEvent("PLAYER_REGEN_ENABLED")
	self:RegisterEvent("PLAYER_REGEN_DISABLED")

	-- Register event and call roster to import guild members and alts
	self:RegisterEvent("GUILD_ROSTER_UPDATE")
	if C_GuildInfo and C_GuildInfo.GuildRoster then
		C_GuildInfo.GuildRoster()
	else
		_G.GuildRoster()
	end

	-- Register event to update friends data.
	self:RegisterEvent("FRIENDLIST_UPDATE")
	self:RegisterEvent("IGNORELIST_UPDATE")
	-- Call ShowFriends to get the friend and ignore data updated.
	C_FriendList.ShowFriends()

	-- Populate the MainsTable
	self:UpdateMainsTable()

	-- Create the Alts frame for later use
	altsFrame = self:CreateAltsFrame()
	addon.altsFrame = altsFrame

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

	-- Hook chat frames so we can edit the messages
	if self.db.profile.showMainsInChat then
		self:HookChatFrames()
	end

	for name, obj in pairs(addon.modules) do
		if obj and obj.Enable then
			obj:Enable()
		end
	end
end

function Alts:OnDisable()
	self:UnregisterEvent("CHAT_MSG_SYSTEM")
	self:UnregisterEvent("PLAYER_REGEN_ENABLED")
	self:UnregisterEvent("PLAYER_REGEN_DISABLED")
    self:UnhookChatFrames()

	for name, obj in pairs(addon.modules) do
		if obj and obj.Disable then
			obj:Disable()
		end
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

function Alts:SetupTooltip(tooltip, owner, anchor, spacer)
	if not tooltip then return end

	local anchorPoint = anchor or "ANCHOR_LEFT"

	if tooltip:GetOwner() == nil and owner then
		tooltip:SetOwner(owner, anchorPoint)
	elseif spacer or spacer == nil then
		tooltip:AddLine(" ")
	end
end

function Alts:AddDataToTooltip(tooltip, owner, name, anchor, spacer)
	if not (tooltip and name) then return false end

	-- Check if a single line should be displayed for mains and alts
	if addon.db.profile.singleLineTooltipDisplay then
		local main = AltsDB:GetMainForAlt(name)
		if main and #main > 0 then
			local alts = { AltsDB:GetAlts(main) }

			if alts and #alts > 0 then
				local altList = AltsDB:FormatUnitList(", ", true, unpack(alts))
				if altList and #altList > 0 then
					if addon.db.profile.wrapTooltip then
						altList = wrap(altList, addon.db.profile.wrapTooltipLength,"    ","", 4)
					end
					self:SetupTooltip(tooltip, owner, anchor, spacer)
					tooltip:AddLine(YELLOW..AltsDB:FormatUnitName(main, true)..": "..WHITE..altList, 1, 1, 1, not addon.db.profile.wrapTooltip)
					return true
				end
			end
		end
	end

	local added = false

	-- Check if it's a main
	if addon.db.profile.showMainInTooltip then
		local main = AltsDB:GetMainForAlt(name)
		if main and #main > 0 then
			if not added then
				self:SetupTooltip(tooltip, owner, anchor, not added)
				added = true
			end
			tooltip:AddLine(YELLOW..L["Main: "]..WHITE..AltsDB:FormatUnitName(main, true), 1, 1, 1, true)
		end
	end
	-- Check if it's an alt
	if self.db.profile.showAltsInTooltip then
		local main, alts = AltsDB:GetAltsForMain(name, true)
		if alts and #alts > 0 then
			local altList = AltsDB:FormatUnitList(", ", true, unpack(alts))
			if altList and #altList > 0 then
				if addon.db.profile.wrapTooltip then
					altList = wrap(altList, addon.db.profile.wrapTooltipLength,"    ","", 4)
				end
				if not added then
					self:SetupTooltip(tooltip, owner, anchor, not added)
					added = true
				end
				tooltip:AddLine(YELLOW..L["Alts: "]..WHITE..altList, 1, 1, 1, not addon.db.profile.wrapTooltip)
			end
		end
	end
	return added
end

function Alts:OnTooltipSetUnit(tooltip, ...)
	if tooltip ~= _G.GameTooltip then return end
    if not self.db.profile.showMainInTooltip and
        not self.db.profile.showAltsInTooltip then return end

    local name, unitid = tooltip:GetUnit()

	-- If the unit exists and is a player then check if for main/alts.
    if _G.UnitExists(unitid) and _G.UnitIsPlayer(unitid) then
		-- Get the unit's name including the realm name
		local nameString = _G.GetUnitName(unitid, true)
        if not nameString then return end
		self:AddDataToTooltip(tooltip, nil, name)
    end
end

function Alts:DisplayMain(name)
	local main = AltsDB:GetMainForAlt(name)

    if self.db.profile.singleLineChatDisplay == true and main and #main > 0 then
        local mainFound, alts = AltsDB:GetAltsForMain(main, true)
        local altList
        local text

        for i, v in ipairs(alts) do
            text = v
            if v == name then
                text = BLUE .. AltsDB:FormatUnitName(v, true) .. WHITE
            else
                text = AltsDB:FormatUnitName(v, true)
            end

            if i == 1 then
                altList = text
            else
                altList = altList .. ", " .. text
            end
        end

        if altList and #altList > 0 then
            self:Print(YELLOW..AltsDB:FormatUnitName(mainFound, true)..": "..WHITE..altList)
        end
    else
        local mainFound, alts = AltsDB:GetAltsForMain(name, true)
        local altList = AltsDB:FormatUnitList(", ", true, unpack(alts))
    	if main and #main > 0 then
    		self:Print(YELLOW..AltsDB:FormatUnitName(name, true)..": "..WHITE..AltsDB:FormatUnitName(main, true))
    	end

        if altList and #altList > 0 then
            self:Print(YELLOW..AltsDB:FormatUnitName(name, true)..": "..WHITE..altList)
        end
    end
	if name then
		local tag = AltsDB:GetBNetAccountForName(name) or AltsDB:GetBNetAccountForName(main)
		if tag then
			local fmt = "%s: %s"
			self:Print(fmt:format(name, tag))
		end
	end
end

function Alts:CHAT_MSG_SYSTEM(event, message)
	local name

	if self.db.profile.showInfoOnWho then
	    name = LibDeformat(message, _G.WHO_LIST_FORMAT)
	end
	if self.db.profile.showInfoOnLogon and not name then
	    name = LibDeformat(message, _G.WHO_LIST_GUILD_FORMAT)
	end
	if self.db.profile.showInfoOnLogon and not name then
	    name = LibDeformat(message, _G.ERR_FRIEND_ONLINE_SS)
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
	if self.db.profile.debug then self:Print("Guild roster updated.") end
	if not guildUpdateTimer then
		guildUpdateTimer = self:ScheduleTimer("UpdateGuild", 5)
	end
end

function Alts:FRIENDLIST_UPDATE(event, message)
    self:UnregisterEvent("FRIENDLIST_UPDATE")
	if self.db.profile.debug then self:Print("Friend list updated.") end
    self:CheckAndUpdateFriends()
	addon:FireCallback("FriendListUpdate")
end

function Alts:IGNORELIST_UPDATE(event, message)
    self:UnregisterEvent("IGNORELIST_UPDATE")
	if self.db.profile.debug then self:Print("Ignore list updated.") end
    self:CheckAndUpdateIgnores()
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
