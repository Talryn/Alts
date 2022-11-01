local _G = getfenv(0)
local ADDON_NAME, addon = ...

local Alts = LibStub("AceAddon-3.0"):GetAddon(addon.addonName)
local L = LibStub("AceLocale-3.0"):GetLocale(addon.addonName, true)
local icon = LibStub("LibDBIcon-1.0")

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
								addon.altsFrame.lock = val
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
                        headerInterfaceMods = {
                            order = 500,
                            type = "header",
                            name = L["Interface Modifications"],
                        },
                        interfaceModGroupDesc = {
                            order = 501,
                            type = "description",
                            name = L["InterfaceModifications_Desc"],
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
                            --width = "double",
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
                        useMainsNameColor = {
                            order = 106,
                            name = L["Use Main Name Color"],
                            desc = L["UseMainNameColor_OptDesc"],
                            --width = "double",
                            type = "toggle",
                            set = function(info, val)
                                self.db.profile.useMainNameColor = val
                                self:SetMainChatColorCode()
                            end,
                            get = function(info) return self.db.profile.useMainNameColor end,
                        },
                  	    mainsNameColor = {
                            order = 107,
                            name = L["Main Name Color"],
                            desc = L["MainNameColor_OptDesc"],
                            type = "color",
                            hasAlpha = false,
                            --width = "double",
                            set = function(info, r, g, b, a)
                                local c = self.db.profile.mainNameColor
                                c.r, c.g, c.b, c.a = r, g, b, a
                                self:SetMainChatColorCode()
                            end,
                            get = function(info)
                                local c = self.db.profile.mainNameColor
                                return c.r, c.g, c.b, c.a
                            end,
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
                	    reportTo = {
                			order = 115,
                            name = L["Report To"],
                            desc = L["ReportTo_OptionDesc"],
							type = "select",
							values = {
							    ["Chat"] = L["Chat"],
							    ["GuildLog"] = L["Guild Log"]
							},
                            set = function(info, val)
								 self.db.profile.reportTo = val
							end,
                            get = function(info)
								return self.db.profile.reportTo
							end,
                        },
                        guildLogButton = {
                            name = L["Guild Log"],
                            desc = L["GuildLog_OptionDesc"],
                            type = "execute",
                            width = "normal",
                            func = function()
                                addon.HideGameOptions()
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
                                addon.HideGameOptions()
                                self:GuildExportHandler("")
                            end,
                			order = 210
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
                formats = {
                    order = 6,
                    name = L["Note Formats"],
                    type = "group",
                    args = {
                        desc = {
                            order = 1,
                            type = "description",
                            name = L["NoteFormats_Desc"],
                        },
                        hdr = {
                            order = 2,
                            type = "header",
                            name = L["Note Formats"],
                        },
                    },
                },
            }
        }

        if self.db.profile.altMatching.methods then
            for i, v in ipairs(self.db.profile.altMatching.methods) do
                options.args.formats.args["regex"..tostring(i)] = {
                    order = 100 + i,
                    name = v.description,
                    desc = v.description,
                    type = "toggle",
                    width = "double",
                    set = function(info, val)
                        self.db.profile.altMatching.methods[i].enabled = val
                        self:UpdateMatchMethods()
                    end,
                    get = function(info)
                        return self.db.profile.altMatching.methods[i].enabled
                    end,
                }
            end
        end

	    options.args.profile = LibStub("AceDBOptions-3.0"):GetOptionsTable(self.db)
    end

    -- Add in the relevant interface modification options.
    local intModOpts = self:InterfaceModsOptions()
    for k, v in _G.pairs(intModOpts) do
        options.args.core.args[k] = v
    end

    return options
end

function Alts:ShowOptions()
    if Settings and Settings.OpenToCategory and 
        _G.type(Settings.OpenToCategory) == "function" then
        Settings.OpenToCategory(addon.addonTitle)
    else
    	_G.InterfaceOptionsFrame_OpenToCategory(self.optionsFrame.Notes)
	    _G.InterfaceOptionsFrame_OpenToCategory(self.optionsFrame.Main)
    end
end

function Alts:InterfaceModsOptions()
    -- Options for all versions
    local baseOrderAll = 500
    local allOptions = {
      unitMenusSetMain = {
        name = L["Unit Menus-Set Main"],
        desc = L["UnitMenusSetMain_Opt"],
        type = "toggle",
        set = function(info,val) self.db.profile.uiModifications.unitMenusSetMain = val end,
        get = function(info) return self.db.profile.uiModifications.unitMenusSetMain end,
        order = baseOrderAll + 10
      },
    }
  
    -- Options for current retail version.
    local baseOrderCurrent = 600
    local currentOptions = {
    }
  
    -- Options for Classic only.
    local classicOptions = {
    }
  
    -- Options for TBC only.
    local tbcOptions = {
    }
  
    local options = allOptions
  
    if addon.Retail then
      for k, v in _G.pairs(currentOptions) do
        options[k] = v
      end
    end
  
    if addon.TBC then
      for k, v in _G.pairs(tbcOptions) do
        options[k] = v
      end
    end
  
    if addon.Classic then
      for k, v in _G.pairs(classicOptions) do
        options[k] = v
      end
    end
  
    return options
  end
  