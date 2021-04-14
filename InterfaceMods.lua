local _G = getfenv(0)
local ADDON_NAME, addon = ...

local pairs = _G.pairs
local ipairs = _G.ipairs
local type = _G.type

local wrap = addon.wrap
local Colors = addon.Colors
local Formats = addon.Formats
local GetRatingColor = addon.GetRatingColor

local AltsDB = addon.AltsDB
local Alts = _G.LibStub("AceAddon-3.0"):GetAddon(addon.addonName)
local L = LibStub("AceLocale-3.0"):GetLocale(addon.addonName, true)

function Alts:EnableInterfaceModifications()
    -- Works for all versions
    Alts:EnableModule("UnitPopupMenus")
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

	function module:Setup()
		if not LibDropDownExtension then return end
		if not IsEnabled() then return end

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
		self.enabled = true
	end

	function module:OnEnable()
		self:Setup()
	end
end
