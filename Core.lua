local _G = getfenv(0)
local ADDON_NAME, addon = ...

local string = _G.string
local pairs = _G.pairs
local floor, abs = _G.math.floor, _G.math.abs
local tonumber = _G.tonumber
local tostring = _G.tostring

addon.addonName = "Alts"

-- Try to remove the Git hash at the end, otherwise return the passed in value.
local function cleanupVersion(version)
	local iter = string.gmatch(version, "(.*)-[a-z0-9]+$")
	if iter then
		local ver = iter()
		if ver and #ver >= 3 then
			return ver
		end
	end
	return version
end

local function versionInRange(version, start, finish)
	if _G.type(version) ~= "number" then return false end
	local start = start or 0
	local finish = finish or 100000000
	if _G.type(start) ~= "number" or _G.type(finish) ~= "number" then return false end
	return version >= start and version < finish
  end
  
addon.addonTitle = _G.GetAddOnMetadata(ADDON_NAME,"Title")
addon.addonVersion = cleanupVersion("@project-version@")

addon.CURRENT_BUILD, addon.CURRENT_INTERNAL, 
    addon.CURRENT_BUILD_DATE, addon.CURRENT_UI_VERSION = _G.GetBuildInfo()
addon.Classic = versionInRange(addon.CURRENT_UI_VERSION, 0, 20000)
addon.TBC = versionInRange(addon.CURRENT_UI_VERSION, 20000, 30000)
addon.Retail = versionInRange(addon.CURRENT_UI_VERSION, 90000)

addon.modules = {}
function addon:RegisterModule(name, obj)
	addon.modules[name] = obj
end
function addon:UnregisterModule(name)
	addon.modules[name] = nil
end

addon.callbacks = {
	["FriendListUpdate"] = {},
}

function addon:RegisterCallback(event, name, func)
	local callbacks = addon.callbacks[event]
	if not callbacks then return end
	if name and func and _G.type(func) == "function" then
		callbacks[name] = func
	end
end
function addon:UnregisterCallback(event, name)
	local callbacks = addon.callbacks[event]
	if not callbacks then return end
	if name then
		callbacks[name] = nil
	end
end
function addon:FireCallback(event)
	local callbacks = addon.callbacks[event]
	if not callbacks then return end
	for name, func in pairs(callbacks) do
		if func then func() end
	end
end

function addon.getTableKeys(t)
	local keys = {}
	for k, v in _G.pairs(t or {}) do
		keys[#keys + 1] = k
	end
	return keys
end

function addon.IsGameOptionsVisible()
	local optionsFrame = _G.SettingsPanel or _G.InterfaceOptionsFrame
    return optionsFrame and optionsFrame:IsVisible() or false
end

function addon.ShowGameOptions()
	local optionsFrame = _G.SettingsPanel or _G.InterfaceOptionsFrame
    optionsFrame:Show()
end

function addon.HideGameOptions()
	local optionsFrame = _G.SettingsPanel or _G.InterfaceOptionsFrame
	if _G.SettingsPanel then
		if not _G.UnitAffectingCombat("player") then
			_G.HideUIPanel(optionsFrame)
		end
	else
		optionsFrame:Hide()
	end
end
