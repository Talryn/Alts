local _G = getfenv(0)
local ADDON_NAME, addon = ...

local pairs = _G.pairs
local ipairs = _G.ipairs
local type = _G.type
local strsub = _G.strsub

local wrap = addon.wrap
local Colors = addon.Colors
local Formats = addon.Formats
local GetRatingColor = addon.GetRatingColor

local AltsDB = addon.AltsDB
local Alts = _G.LibStub("AceAddon-3.0"):GetAddon(addon.addonName)
local L = LibStub("AceLocale-3.0"):GetLocale(addon.addonName, true)

function addon.GetMouseFocusFrame()
	if _G.GetMouseFocus then
		return _G.GetMouseFocus()
	elseif _G.GetMouseFoci then
		return _G.GetMouseFoci()
	end
end

local ScrollBoxUtil = {}
function ScrollBoxUtil:OnViewFramesChanged(scrollBox, callback)
	if not scrollBox then return end
	if scrollBox.buttons then
		callback(scrollBox.buttons, scrollBox)
		return
	end
	if scrollBox.RegisterCallback then
		local frames = scrollBox:GetFrames()
		if frames and frames[1] then
			callback(frames, scrollBox)
		end
		scrollBox:RegisterCallback(ScrollBoxListMixin.Event.OnUpdate, function()
			callback(scrollBox:GetFrames(), scrollBox)
		end)
		return
	end
end

function ScrollBoxUtil:OnViewScrollChanged(scrollBox, callback)
	if not scrollBox then return end
	local function wrappedCallback()
		callback(scrollBox)
	end
	if scrollBox.update then
		hooksecurefunc(scrollBox, "update", wrappedCallback)
		return
	end
	if scrollBox.RegisterCallback then
		scrollBox:RegisterCallback(ScrollBoxListMixin.Event.OnScroll, wrappedCallback)
		return
	end
end

local hooked = {}
local function HookAllFrames(frames, functions)
	for _, frame in ipairs(frames) do
		hooked[frame] = hooked[frame] or {}
		local hook = hooked[frame]
		for script, func in pairs(functions) do
			hook[script] = hook[script] or {}
			local fnHook = hook[script]
			if not fnHook[func] then
				frame:HookScript(script, func)
				fnHook[func] = true
			end
		end
	end
end

function Alts:EnableInterfaceModifications()
    -- Works for all versions
    Alts:EnableModule("UnitPopupMenus")

	if addon.Retail then
		Alts:EnableModule("GuildTooltip")
		Alts:EnableModule("CommunitiesTooltip")
	end
end

function addon.GetNameFromPlayerLink(playerLink)
	if not _G.LinkUtil or not _G.ExtractLinkData then return nil end
	local linkString, linkText = _G.LinkUtil.SplitLink(playerLink)
	local linkType, linkData = _G.ExtractLinkData(linkString)
	if linkType == "player" then
		return linkData
	elseif linkType == "BNplayer" then
		local _, bnetIDAccount = _G.strsplit(":", linkData)
		if bnetIDAccount then
			local bnetID = _G.tonumber(bnetIDAccount)
			if bnetID then
				return addon.GetNameForBNetFriend(bnetID)
			end
		end
	end
end

function addon.GetNameForBNetFriend(bnetIDAccount)
	if not C_BattleNet then return nil end
	local index = _G.BNGetFriendIndex(bnetIDAccount)
	if not index then return nil end
	for i = 1, C_BattleNet.GetFriendNumGameAccounts(index), 1 do
		local accountInfo = C_BattleNet.GetFriendGameAccountInfo(index, i)
		if accountInfo and accountInfo.clientProgram == BNET_CLIENT_WOW and (not accountInfo.wowProjectID or accountInfo.wowProjectID ~= WOW_PROJECT_CLASSIC) then
			if accountInfo.realmName then
				accountInfo.characterName = accountInfo.characterName .. "-" .. accountInfo.realmName:gsub("%s+", "")
			end
			return accountInfo.characterName
		end
	end
	return nil
end

do
	local module = Alts:NewModule("UnitPopupMenus")
	module.enabled = false

	local function IsEnabled()
    	return addon.db.profile.uiModifications.unitMenusSetMain
  	end

	local dropDownTypes = {
        ARENAENEMY = true,
        BN_FRIEND = true,
        CHAT_ROSTER = true,
        COMMUNITIES_GUILD_MEMBER = true,
        COMMUNITIES_WOW_MEMBER = true,
        FOCUS = true,
        FRIEND = true,
        GUILD = true,
        GUILD_OFFLINE = true,
        PARTY = true,
        PLAYER = true,
        RAID = true,
        RAID_PLAYER = true,
        SELF = true,
        TARGET = true,
        WORLD_STATE_SCORE = true
    }

	local function IsUnitDropDown(dropdown)
		return type(dropdown.which) == "string" and dropDownTypes[dropdown.which]
	end

	local function GetName(dropdown)
		local unit = dropdown.unit
		if _G.UnitExists(unit) and _G.UnitIsPlayer(unit) then
			return _G.GetUnitName(unit, true)
		end
		if dropdown.bnetIDAccount then
			local name = addon.GetNameForBNetFriend(dropdown.bnetIDAccount)
			if name then return name end
		end
		if dropdown.menuList then
            for _, whisperButton in ipairs(dropdown.menuList) do
                if whisperButton and (whisperButton.text == _G.WHISPER_LEADER or whisperButton.text == _G.WHISPER) then
                    if whisperButton.arg1 then
						return whisperButton.arg1
					end
                end
            end
        end
		if dropdown.quickJoinButton or dropdown.quickJoinMember then
			local memberInfo = dropdown.quickJoinMember or quickJoinButton.Members[1]
			if memberInfo.playerLink then
				local name = addon.GetNameFromPlayerLink(memberInfo.playerLink)
				if name then return name end
			end
		end
		if dropdown.name and not dropdown.bnetIDAccount then
			local name = AltsDB:FormatNameWithRealm(dropdown.name, dropdown.server)
			if name then return name end
		end
		return nil
	end

	local function OnToggle(dropdown, event, options, level, data)
		if not addon.db.profile.uiModifications.unitMenusSetMain then return end
        if event == "OnShow" then
            if not IsUnitDropDown(dropdown) then return end
            local name = GetName(dropdown)
            if not name then return end
			module.name = name

			local added = false
			for key, unitOption in pairs(data.unitOptionsLookup) do
				local found = false
				for _, option in ipairs(options) do
					if option.text == key then
						found = true
						break
					end
				end
				if not found then
					_G.table.insert(options, unitOption)
					added = true
				end
			end

			if added then
                return true
            end
        elseif event == "OnHide" then
			_G.wipe(options)
			return true
        end
    end

    ---@type LibDropDownExtension
    local LibDropDownExtension = LibStub and LibStub:GetLibrary("LibDropDownExtension-1.0", true)

	function module:HasMenu()
		return Menu and Menu.ModifyMenu
	end

	local function GetNameForContext(contextData)
		local contextName = contextData.name
		if not contextName then return nil end
		if strsub(contextName, 1, 1) == "|" then
			return nil
		else
			local name = AltsDB:FormatNameWithRealm(contextData.name, contextData.server)
			return name
		end
	end

	local function IsValidName(contextData)
		return contextData.name and strsub(contextData.name, 1, 1) ~= "|"
	end

	-- contextData.accountInfo.battleTag
	function module:MenuHandler(owner, rootDescription, contextData)
		if not IsValidName(contextData) then return end
		rootDescription:CreateDivider();
		rootDescription:CreateTitle(addon.addonTitle);
		rootDescription:CreateButton(L["Set Main"], function()
			local name = GetNameForContext(contextData)
			if name then
				Alts:SetMainHandler(name)
			end
		end)
	end

	function module:AddItemsWithMenu()
		if not self:HasMenu() then return end

		-- Find via /run Menu.PrintOpenMenuTags()
		local menuTags = {
			["MENU_UNIT_PLAYER"] = true,
			["MENU_UNIT_PARTY"] = true,
			["MENU_UNIT_RAID_PLAYER"] = true,
			["MENU_UNIT_FRIEND"] = true,
			["MENU_UNIT_COMMUNITIES_GUILD_MEMBER"] = true,
			["MENU_UNIT_COMMUNITIES_MEMBER"] = true,
		}

		for tag, enabled in pairs(menuTags) do
			Menu.ModifyMenu(tag, GenerateClosure(self.MenuHandler, self))
		end
	end

	function module:AddItemsWithDDE()
		if not LibDropDownExtension then return end
		self.unitOptions = {
			{
				text = L["Set Main"],
				func = function()
					Alts:SetMainHandler(module.name)
				end
			}
		}

		self.unitOptionsLookup = {}
		for _, option in ipairs(self.unitOptions) do
			self.unitOptionsLookup[option.text] = option
		end

		LibDropDownExtension:RegisterEvent("OnShow OnHide", OnToggle, 1, self)
	end

	function module:Setup()
		if not IsEnabled() then return end

		if self:HasMenu() then
			self:AddItemsWithMenu()
		else
			self:AddItemsWithDDE()
		end
		self.enabled = true
	end

	function module:OnEnable()
		self:Setup()
	end
end

do
	local module = Alts:NewModule("GuildTooltip")
	module.enabled = false

	local function IsEnabled()
    	if not addon.Retail then
      		return false
    	end
    	return addon.db.profile.uiModifications.GuildRosterTooltip
	end

	local function OnEnter(self)
	    if not IsEnabled() then return end
    	if not self.guildIndex then return end
    	local name = _G.GetGuildRosterInfo(self.guildIndex)

		if Alts:AddDataToTooltip(GameTooltip, self, name) then
			GameTooltip:Show()
		end
	end

	local function OnLeave(self)
	    if not IsEnabled() then return end
    	if not self.guildIndex then return end
    	GameTooltip:Hide()
	end

	local function OnScroll()
    	if not IsEnabled() then return end
		GameTooltip:Hide()
		pcall(addon.GetMouseFocusFrame(), "OnEnter")
	end

	function module:Setup()
		if not IsEnabled() or self.enabled then return end
		if not _G.GuildFrame then
			-- If enabled, keep trying until the guild frame is loaded.
			C_Timer.After(1, function()
				self:Setup()
			end)
			return
		end
		local hooks = { ["OnEnter"] = OnEnter, ["OnLeave"] = OnLeave }
		ScrollBoxUtil:OnViewFramesChanged(_G.GuildRosterContainer, function(frames) HookAllFrames(frames, hooks) end)
		ScrollBoxUtil:OnViewScrollChanged(_G.GuildRosterContainer, OnScroll)
		self.enabled = true
	end

	function module:OnEnable()
		self:Setup()
	end
end

do
	local module = Alts:NewModule("CommunitiesTooltip")
	module.enabled = false

	local function IsEnabled()
    	if not addon.Retail then
      		return false
    	end
    	return addon.db.profile.uiModifications.CommunitiesTooltip
	end

	local function IsCharacter(clubType)
		return clubType and (clubType == Enum.ClubType.Guild or
			clubType == Enum.ClubType.Character)
	end

	local function OnEnter(self)
	    if not IsEnabled() then return end
		local name
    	if type(self.GetMemberInfo) == "function" then
    		local info = self:GetMemberInfo()
			if not IsCharacter(info.clubType) then return end
    		name = info.name
    	elseif type(self.cardInfo) == "table" then
      		name = self.cardInfo.guildLeader
    	else
      		return
    	end
		if not name then return end

		if Alts:AddDataToTooltip(GameTooltip, self, name) then
			GameTooltip:Show()
		end
	end

	local function OnLeave(self)
	    if not IsEnabled() then return end
    	if not self.guildIndex then return end
    	GameTooltip:Hide()
  	end

	local function OnScroll()
	    if not IsEnabled() then return end
		GameTooltip:Hide()
		pcall(addon.GetMouseFocusFrame(), "OnEnter")
	end

	local hooked = {}
	local function HookFrames(frames)
		if not frames then return end
		for _, frame in pairs(frames) do
			if not hooked[frame] then
				frame:HookScript("OnEnter", OnEnter)
				frame:HookScript("OnLeave", OnLeave)
        		if type(frame.OnEnter) == "function" then hooksecurefunc(frame, "OnEnter", OnEnter) end
        		if type(frame.OnLeave) == "function" then hooksecurefunc(frame, "OnLeave", OnLeave) end
				hooked[frame] = true
			end
		end
	end

	local function OnRefreshLayout()
	    if not IsEnabled() then return end
		HookFrames(_G.ClubFinderGuildFinderFrame.GuildCards.Cards)
        HookFrames(_G.ClubFinderGuildFinderFrame.PendingGuildCards.Cards)
        HookFrames(_G.ClubFinderCommunityAndGuildFinderFrame.GuildCards.Cards)
        HookFrames(_G.ClubFinderCommunityAndGuildFinderFrame.PendingGuildCards.Cards)
		return true
	end

	function module:Setup()
    	if not IsEnabled() then return end
		if self.enabled then return end
		if not (_G.CommunitiesFrame and _G.ClubFinderGuildFinderFrame and _G.ClubFinderCommunityAndGuildFinderFrame) then
			-- If enabled, keep trying until the guild frame is loaded.
			C_Timer.After(1, function()
				self:Setup()
			end)
			return
		end

        ScrollBoxUtil:OnViewFramesChanged(_G.CommunitiesFrame.MemberList.ListScrollFrame or _G.CommunitiesFrame.MemberList.ScrollBox, HookFrames)
        ScrollBoxUtil:OnViewScrollChanged(_G.CommunitiesFrame.MemberList.ListScrollFrame or _G.CommunitiesFrame.MemberList.ScrollBox, OnScroll)
        ScrollBoxUtil:OnViewFramesChanged(_G.ClubFinderGuildFinderFrame.CommunityCards.ListScrollFrame or _G.ClubFinderGuildFinderFrame.CommunityCards.ScrollBox, HookFrames)
        ScrollBoxUtil:OnViewScrollChanged(_G.ClubFinderGuildFinderFrame.CommunityCards.ListScrollFrame or _G.ClubFinderGuildFinderFrame.CommunityCards.ScrollBox, OnScroll)
        ScrollBoxUtil:OnViewFramesChanged(_G.ClubFinderGuildFinderFrame.PendingCommunityCards.ListScrollFrame or _G.ClubFinderGuildFinderFrame.PendingCommunityCards.ScrollBox, HookFrames)
        ScrollBoxUtil:OnViewScrollChanged(_G.ClubFinderGuildFinderFrame.PendingCommunityCards.ListScrollFrame or _G.ClubFinderGuildFinderFrame.PendingCommunityCards.ScrollBox, OnScroll)
        ScrollBoxUtil:OnViewFramesChanged(_G.ClubFinderCommunityAndGuildFinderFrame.CommunityCards.ListScrollFrame or _G.ClubFinderCommunityAndGuildFinderFrame.CommunityCards.ScrollBox, HookFrames)
        ScrollBoxUtil:OnViewScrollChanged(_G.ClubFinderCommunityAndGuildFinderFrame.CommunityCards.ListScrollFrame or _G.ClubFinderCommunityAndGuildFinderFrame.CommunityCards.ScrollBox, OnScroll)
        ScrollBoxUtil:OnViewFramesChanged(_G.ClubFinderCommunityAndGuildFinderFrame.PendingCommunityCards.ListScrollFrame or _G.ClubFinderCommunityAndGuildFinderFrame.PendingCommunityCards.ScrollBox, HookFrames)
        ScrollBoxUtil:OnViewScrollChanged(_G.ClubFinderCommunityAndGuildFinderFrame.PendingCommunityCards.ListScrollFrame or _G.ClubFinderCommunityAndGuildFinderFrame.PendingCommunityCards.ScrollBox, OnScroll)
        hooksecurefunc(_G.ClubFinderGuildFinderFrame.GuildCards, "RefreshLayout", OnRefreshLayout)
        hooksecurefunc(_G.ClubFinderGuildFinderFrame.PendingGuildCards, "RefreshLayout", OnRefreshLayout)
        hooksecurefunc(_G.ClubFinderCommunityAndGuildFinderFrame.GuildCards, "RefreshLayout", OnRefreshLayout)
        hooksecurefunc(_G.ClubFinderCommunityAndGuildFinderFrame.PendingGuildCards, "RefreshLayout", OnRefreshLayout)
		self.enabled = true
	end

	function module:OnEnable()
		self:Setup()
	end
end
