local _G = getfenv(0)
local ADDON_NAME, addon = ...

local Alts = LibStub("AceAddon-3.0"):GetAddon(addon.addonName)
local AltsDB = addon.AltsDB
local L = LibStub("AceLocale-3.0"):GetLocale("Alts", true)
local ScrollingTable = LibStub("ScrollingTable")

local tconcat = _G.table.concat

local module = {}
module.name = "BattleNet"
addon:RegisterModule(module.name, module)
module.enabled = false

module.BNetData = {}
module.browserFrame = nil

function module:OnInitialize()
	Alts:RegisterChatCommand("bnetalts", module.BrowserHandler)
end

function module:Enable()
	addon:RegisterCallback("FriendListUpdate", module.name, module.FriendListUpdate)
	self:OnEnable()
end

function module:Disable()
	addon:UnregisterCallback("FriendListUpdate", module.name)
	self:OnDisable()
end

function module:OnEnable()
	self.eventFrame = self.eventFrame or _G.CreateFrame("frame")
	self.eventFrame:RegisterEvent("BN_FRIEND_ACCOUNT_ONLINE")
	self.eventFrame:SetScript("OnEvent", self.EventHandler)
	self.enabled = true
	local frame = module.browserFrame
	if not frame then module.browserFrame = module:CreateBrowser() end
end

function module:OnDisable()
	if self.eventFrame then
		self.eventFrame:UnregisterEvent("BN_FRIEND_ACCOUNT_ONLINE")
		self.eventFrame:SetScript("OnEvent", nil)
	end
	self.enabled = false
end

function module:AddBNetLink(accountInfo)
	if not (accountInfo and accountInfo.gameAccountInfo) then return end

	local battleTag = accountInfo.battleTag
	local isBattleTagFriend = accountInfo.isBattleTagFriend
	local characterName = accountInfo.gameAccountInfo.characterName
	local realmName = accountInfo.gameAccountInfo.realmName
	local client = accountInfo.gameAccountInfo.clientProgram

	if isBattleTagFriend and battleTag then
		if characterName and realmName and client == _G.BNET_CLIENT_WOW then
			AltsDB:AddBNetLink(battleTag, characterName, realmName)
			if addon.db.profile.debug then
				local fmt = "Discovered %s: %s"
				Alts:Print(fmt:format(battleTag, AltsDB:FormatNameWithRealm(characterName, realmName)))
			end
		end
	end
end

function module.FriendListUpdate()
	module:UpdateBNetFriends()
end

function module:UpdateBNetFriends()
	for i = 1, _G.BNGetNumFriends() do
		self:AddBNetLink(C_BattleNet.GetFriendAccountInfo(i))
	end
end

function module:ProcessBNetFriend(id)
	if id then
		self:AddBNetLink(C_BattleNet.GetFriendAccountInfo(id))
	else
		if addon.db.profile.debug then
			Alts:Print("Bad message: ".._G.tostring(id))
		end
	end
end

function module.EventHandler(frame, event, ...)
	if event == "BN_FRIEND_ACCOUNT_ONLINE" then
		module:BN_FRIEND_ACCOUNT_ONLINE(event, ...)
	end
end

function module:BN_FRIEND_ACCOUNT_ONLINE(event, message)
	self:ProcessBNetFriend(message)
end

function module.BrowserHandler()
	local frame = module.browserFrame
	if frame then frame:Show() end
	module:UpdateBNetData()
end

function module:UpdateBNetData()
	_G.wipe(module.BNetData)
	local accounts = AltsDB:GetAllBNetAccounts()
	for i, battleTag in _G.ipairs(accounts) do
		local characters = AltsDB:GetBNetAccount(battleTag)
		local names = addon.getTableKeys(characters)
		_G.table.sort(names)
		local list = tconcat(names, ", ")
		module.BNetData[#module.BNetData + 1] = {battleTag, list}
	end
	
	local frame = module.browserFrame
	if frame and frame:IsVisible() then
		frame.table:SortData()
	end
end

function module:CreateBrowser()
	local frame = _G.CreateFrame("Frame", "Alts_BnetBrowserWindow", _G.UIParent, BackdropTemplateMixin and "BackdropTemplate")
	frame:SetFrameStrata("DIALOG")
	frame:SetToplevel(true)
	frame:SetWidth(630)
	frame:SetHeight(400)
	if addon.db.profile.battleNet.rememberPos then
        frame:SetPoint("CENTER", _G.UIParent, "CENTER",
            addon.db.profile.battleNet.browserX, addon.db.profile.battleNet.browserY)
    else
	    frame:SetPoint("CENTER", _G.UIParent)
    end
	frame:SetBackdrop({bgFile="Interface\\DialogFrame\\UI-DialogBox-Background", 
	    edgeFile="Interface\\DialogFrame\\UI-DialogBox-Border", tile=true,
		tileSize=32, edgeSize=32, insets={left=11, right=12, top=12, bottom=11}})

	local cols = {}
	cols[1] = {
		["name"] = L["Battle Tag"],
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

	local table = ScrollingTable:CreateST(cols, 15, nil, nil, frame);

	local headertext = frame:CreateFontString("Alts_BNet_HeaderText", frame, "GameFontNormalLarge")
	headertext:SetPoint("TOP", frame, "TOP", 0, -20)
	headertext:SetText(L["Battle.net Alts"])

	local searchterm = _G.CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
	searchterm:SetFontObject(_G.ChatFontNormal)
	searchterm:SetWidth(300)
	searchterm:SetHeight(35)
	searchterm:SetPoint("TOPLEFT", frame, "TOPLEFT", 25, -50)
	searchterm:SetScript("OnShow", function(this) searchterm:SetFocus() end)
	searchterm:SetScript("OnEnterPressed", function(this) this:GetParent().table:SortData() end)
	searchterm:SetScript("OnEscapePressed", function(this) this:SetText(""); this:GetParent():Hide(); end)

	table.frame:SetPoint("TOP", searchterm, "BOTTOM", 0, -20)
	table.frame:SetPoint("LEFT", frame, "LEFT", 20, 0)

	local searchbutton = _G.CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
	searchbutton:SetText(L["Search"])
	searchbutton:SetWidth(100)
	searchbutton:SetHeight(20)
	searchbutton:SetPoint("LEFT", searchterm, "RIGHT", 10, 0)
	searchbutton:SetScript("OnClick", function(this) this:GetParent().table:SortData() end)

	local clearbutton = _G.CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
	clearbutton:SetText(L["Clear"])
	clearbutton:SetWidth(100)
	clearbutton:SetHeight(20)
	clearbutton:SetPoint("LEFT", searchbutton, "RIGHT", 10, 0)
	clearbutton:SetScript("OnClick", function(this)
		this:GetParent().searchterm:SetText("");
		this:GetParent().table:SortData(); end)

	local closebutton = _G.CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
	closebutton:SetText(L["Close"])
	closebutton:SetWidth(90)
	closebutton:SetHeight(20)
	closebutton:SetPoint("BOTTOM", frame, "BOTTOM", 0, 20)
	closebutton:SetScript("OnClick", function(this) this:GetParent():Hide(); end)

	local deletebutton = _G.CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
	deletebutton:SetText(L["Delete"])
	deletebutton:SetWidth(90)
	deletebutton:SetHeight(20)
	deletebutton:SetPoint("BOTTOM", frame, "BOTTOM", 0, 70)
	deletebutton:SetScript("OnClick", 
		function(this)
		    local frame = this:GetParent()
			if frame.table:GetSelection() then
				local row = frame.table:GetRow(frame.table:GetSelection())
				if row[1] and #row[1] > 0 then
					-- confirmMainDeleteFrame.mainname:SetText(row[3])
					-- confirmMainDeleteFrame:Show()
					-- confirmMainDeleteFrame:Raise()
					-- altsFrame:Hide()
				end
			end
		end)

	local editbutton = _G.CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
	editbutton:SetText(L["Edit"])
	editbutton:SetWidth(90)
	editbutton:SetHeight(20)
	editbutton:SetPoint("BOTTOM", frame, "BOTTOM", 120, 70)
	editbutton:SetScript("OnClick", 
		function(this)
		    local frame = this:GetParent()
			if frame.table:GetSelection() then
				local row = frame.table:GetRow(frame.table:GetSelection())
				if row[1] and #row[1] > 0 then
				    frame:Hide()
					--self:EditAltsHandler(row[3])
				end
			end
		end)

	frame.table = table
	frame.searchterm = searchterm

    table:RegisterEvents({
		["OnEnter"] = function (rowFrame, cellFrame, data, cols, row, realrow, column, table, ...)
			return true;
		end, 
		["OnLeave"] = function(rowFrame, cellFrame, data, cols, row, realrow, column, table, ...)
			return true;
		end,
    })

	table:EnableSelection(true)
	table:SetData(module.BNetData, true)
	table:SetFilter(
		function(self, row)
			local searchterm = searchterm:GetText()
			if searchterm and #searchterm > 0 then
				local term = searchterm:lower()
				if row[1]:lower():find(term) or row[2]:lower():find(term) then
					return true
				end

				return false
			else
				return true
			end
		end
	)

    frame.lock = addon.db.profile.battleNet.lockBrowser

    frame:SetMovable(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart",
        function(self,button)
			if not self.lock then
            	self:StartMoving()
			end
        end)
    frame:SetScript("OnDragStop",
        function(self)
            self:StopMovingOrSizing()
			if addon.db.profile.battleNet.rememberPos then
    			local scale = self:GetEffectiveScale() / _G.UIParent:GetEffectiveScale()
    			local x, y = self:GetCenter()
    			x, y = x * scale, y * scale
    			x = x - _G.GetScreenWidth()/2
    			y = y - _G.GetScreenHeight()/2
    			x = x / self:GetScale()
    			y = y / self:GetScale()
    			addon.db.profile.battleNet.browserX, 
    			    addon.db.profile.battleNet.browserY = x, y
    			self:SetUserPlaced(false);
            end
        end)
    frame:EnableMouse(true)

	frame:Hide()
	
	return frame
end
