-- luacheck configuration for pfQuest-Reborn (WoW 3.3.5a, Lua 5.1).
-- Usage: luacheck .   (CI runs luac5.1 -p + tests separately)
--
-- Design: `std` stays lua51 so standard built-ins keep working. `std.wow335`
-- is additive and declares the client API / UI globals the addon may read,
-- plus the implicit frame-handler upvalues (this, arg1..arg4, event).
-- Writable `globals` are the addon's own cross-file tables plus the small
-- set of Blizzard entry points this addon legitimately hooks/overwrites.

std = "lua51+wow335"

stds.wow335 = {
  read_globals = {
    -- implicit frame-script upvalues (OnUpdate/OnEvent pass bare argN/event).
    -- NOTE: `this` can't live here: handlers also ASSIGN fields on it
    -- (this.tick etc.), and read_globals are read-only (W122). It is
    -- declared writable in `globals` below instead.
    "event", "arg1", "arg2", "arg3", "arg4",

    -- Lua 5.1 / WoW compat aliases used bare across the codebase
    "strfind", "strsub", "strlower", "strupper", "strlen",
    "getglobal", "getfenv", "setfenv",
    "format", "gsub", "ceil", "floor", "min", "max", "mod", "abs",
    "sqrt", "sin", "cos", "atan2", "date", "time",
    "bit",
    "hooksecurefunc", "debugstack",

    -- core client API
    "CreateFrame", "GetBuildInfo", "GetLocale", "GetTime",
    "GetCVar", "SetCVar", "ReloadUI", "ForceQuit",
    "GetAddOnInfo", "GetNumAddOns", "GetAddOnMetadata", "IsAddOnLoaded",
    "GetScreenWidth", "GetScreenHeight", "GetFramerate",
    "GetMouseFocus", "MouseIsOver",
    "PlaySound", "ToggleDropDownMenu", "CloseDropDownMenus",
    "UIDropDownMenu_Initialize", "UIDropDownMenu_AddButton",
    "UIDropDownMenu_SetWidth", "UIDropDownMenu_SetButtonWidth",
    "UIDropDownMenu_SetSelectedID", "UIDropDownMenu_JustifyText",
    "FauxScrollFrame_GetOffset", "FauxScrollFrame_Update",
    "ShowUIPanel", "HideUIPanel", "ToggleWorldMap",
    "StaticPopup_Show", "StaticPopup_EditBoxOnTextChanged",
    "SendChatMessage", "SendAddonMessage",
    "GetItemInfo", "GetItemIcon", "SetItemRef",
    "GetContainerNumSlots", "GetContainerItemLink",
    "GetInventoryItemLink",
    "IsShiftKeyDown", "IsControlKeyDown", "IsAltKeyDown",
    "IsInInstance", "UnitOnTaxi",
    "UnitName", "UnitLevel", "UnitXP", "UnitRace", "UnitClass",
    "UnitFactionGroup", "UnitSex", "UnitIsPlayer",
    "UnitInParty", "UnitInRaid",
    "GetNumPartyMembers", "GetNumRaidMembers",
    "GetPlayerFacing", "GetPlayerMapPosition",
    "GetRealZoneText", "GetSubZoneText", "GetZoneText", "GetMapInfo",
    "GetMapZones", "GetMapContinents", "SetMapZoom", "SetMapToCurrentZone",
    "GetCurrentMapZone", "GetCurrentMapContinent",
    "GetMinimapShape",
    "GetNumSkillLines", "GetSkillLineInfo",
    "SecondsToTime",

    -- quest log / quest frame API
    "GetNumQuestLogEntries", "GetQuestLogTitle", "GetQuestLink",
    "GetNumQuestLeaderBoards", "GetQuestLogLeaderBoard",
    "GetQuestLogSelection", "SelectQuestLogEntry", "GetQuestLogQuestText",
    "GetNumQuestChoices", "GetQuestReward", "GetTitleText",
    "IsQuestCompletable", "IsQuestWatched", "AddQuestWatch",
    "RemoveQuestWatch", "GetQuestLogRewardXP", "GetQuestLogRewardMoney",
    "GetQuestLogRewardHonor", "GetNumQuestLogRewards",
    "GetNumQuestLogChoices", "GetQuestLogChoiceInfo",
    "GetQuestLogRewardInfo", "GetQuestItemInfo", "GetQuestItemLink",
    "GetNumGossipAvailableQuests", "GetGossipAvailableQuests",
    "GetNumGossipActiveQuests", "GetGossipActiveQuests",
    "GetNumAvailableQuests", "GetAvailableQuestInfo",
    "GetNumActiveQuests", "GetActiveTitle", "GetAvailableTitle",
    "SelectGossipAvailableQuest", "SelectGossipActiveQuest",
    "SelectAvailableQuest", "SelectActiveQuest",
    "AcceptQuest", "CompleteQuest", "GetAbandonQuestName", "AbandonQuest",
    "CollapseQuestHeader", "ExpandQuestHeader",
    "QuestLog_Update", "QuestLog_SetSelection",
    "QuestLog_UpdateQuestDetails", "QuestLogTitleButton_OnClick",
    "QuestLogTitleButton_Resize",
    "GetQuestsCompleted", "QueryQuestsCompleted",
    "GetQuestDifficultyColor", "GetDifficultyColor",
    "GameTooltip_SetDefaultAnchor",
    "GetUnitName",

    -- root frames / UI objects provided by FrameXML
    "UIParent", "WorldFrame", "Minimap", "MiniMapCompassRing",
    "GameTooltip", "ItemRefTooltip",
    "DEFAULT_CHAT_FRAME", "ChatFrameEditBox", "NUM_CHAT_WINDOWS",
    "WorldMapFrame", "WorldMapButton", "WorldMapDetailFrame",
    "WorldMapTooltip", "WorldMapPOIFrame", "WorldMapBlobFrame",
    "WorldMapScrollFrame", "WorldMapLevelDropDown",
    "WorldMapQuestFrame_OnMouseUp",
    "QuestLogFrame", "QuestLogScrollFrame", "QuestLogListScrollFrame",
    "WorldMapFrame_ClearQuestPOIs",
    "QuestLogDetailScrollFrame", "QuestLogDetailScrollChildFrame",
    "QuestLogQuestTitle", "QuestLogObjectivesText",
    "QuestLogQuestDescription", "QuestLogDescriptionTitle",
    "QuestInfoTitleHeader", "QuestInfoObjectivesText",
    "QuestInfoDescriptionText", "QuestInfoDescriptionHeader",
    "QuestFrameRewardPanel",
    "QuestWatchFrame", "WatchFrame",
    "EQL3_QuestLogListScrollFrame", "EQL3_QuestLogDetailScrollFrame",
    "EQL3_QuestLogDetailScrollChildFrame",
    "EQL3_QuestLogQuestTitle", "EQL3_QuestLogObjectivesText",
    "EQL3_QuestLogQuestDescription", "EQL3_QuestLogDescriptionTitle",
    "ShaguQuest_QuestLogListScrollFrame",
    "ShaguQuest_QuestLogDetailScrollChildFrame",
    "ShaguQuest_QuestLogDescriptionTitle",
    "WORLDMAP_SETTINGS", "WORLDMAP_POI_FRAMELEVEL",
    "QUESTS_DISPLAYED", "QUEST_MONSTERS_KILLED", "QUEST_OBJECTS_FOUND",
    "UNKNOWN", "NONE", "YES", "NO", "OK", "CANCEL", "QUIT_NOW",
    "RETRIEVING_ITEM_INFO", "STANDARD_TEXT_FONT",
    "ANCHOR_BOTTOMLEFT",
    "RAID_CLASS_COLORS", "ITEM_QUALITY_COLORS",
    "UISpecialFrames", "UIMenus", "UIErrorsFrame",
    "GameFontNormal", "GameFontWhite", "ItemRefTooltipTextLeft1",
    "ElvUI",

    -- optional integrations / compat shims (nil-checked at runtime)
    "CT_QuestLevels_oldGetQuestLogTitle",
  },
}

-- Cross-file addon tables and entry points (declared writable).
-- Keep sorted; add new shared tables here instead of scattering
-- inline `globals` comments through logic files.
-- Lua 5.0 compat calls still shipped (and used) in the 3.3.5a client.
-- table.getn/maxn/foreach, string.gfind, math.mod were removed upstream
-- in 5.1 but exist in WoW's Lua. Declared as writable-any so both reads
-- and the local-alias pattern (local getn = table.getn) pass.
globals = {
  "table.getn", "table.maxn", "table.foreach", "table.foreachi",
  "string.gfind", "math.mod",

  -- implicit 3.3.5a frame-handler globals (handlers read AND assign fields)
  "this", "tracker",

  -- addon namespaces (see init/addon.xml load order)
  "pfQuest", "pfMap", "pfDB", "pfDatabase",
  "pfQuest_config", "pfQuest_defconfig", "pfQuest_Loc", "pfQuestInit",
  "pfQuestConfig", "pfQuestContinent", "pfQuestCompat",
  "pfQuest_questcache", "pfQuest_history", "pfQuest_colors",
  "pfQuest_server", "pfQuest_track", "pfBrowser", "pfBrowser_fav",
  "pfBrowserIcon", "pfJournal", "pfQuestIcon", "pfQuestLoot",
  "pfQuestMenu", "pfQuestTheme", "pfQuestNameplates",
  "pfQuestAnnounce", "pfQuestAutomation", "pfQuestEpochLoot",

  -- pfUI shim (compat/pfUI.lua builds the fallback when absent).
  -- Writable: the real pfUI owns these when present.
  "pfUI", "pfUI_config",

  -- Blizzard function hooks (assignment = the hook, see quest.lua, map.lua)
  "AbandonQuest", "AddQuestWatch", "RemoveQuestWatch",
  "SetItemRef", "QuestLog_Update", "QuestLogTitleButton_OnClick",
  "ExpandQuestHeader", "CollapseQuestHeader",
  "WorldMapQuestFrame_OnMouseUp",

  -- Blizzard globals the addon extends
  "SlashCmdList",
  "SLASH_PFDB1", "SLASH_PFDB2", "SLASH_PFDB3", "SLASH_PFDB4",
  "SLASH_PFQUESTAPI1", "SLASH_PFQUESTDEBUG1", "SLASH_PFQUESTFIND1",
  "SLASH_PFQUESTNP1", "SLASH_PFQUEREBUILD1",
  "StaticPopupDialogs",
  "QuestLogScrollFrame",
  "WorldMapButton", "WorldMapDetailFrame", "WorldMapFrame",
  "WorldMapPOIFrame", "ItemRefTooltip",

  -- shared tuning global (map.lua documents cross-file read)
  "mainmap_inversescale",
}

-- False positives not worth fixing in hot paths:
-- 211/212 unused vars/args (frame scripts, hook signatures), 213 unused
-- loop vars, 311/312 unused values (defensive assignments), 542 empty
-- if branches (version-gated stubs), 581 negation complexity.
ignore = { "211", "212", "213", "311", "312", "542", "581" }

-- 120-col cap holds for hand-written code; db/*.lua and locales.lua are
-- generated/localization data with long single-line rows.
-- db/ is generated by tools: skip linting it entirely.
exclude_files = { "db/**" }
files["locales.lua"] = { ignore = { "631" } }

-- compat/client.lua unwraps tbc/wotlk API returns down to the vanilla
-- shape: group/daily are read positionally and intentionally dropped.
files["compat/client.lua"] = { ignore = { "231" } }
