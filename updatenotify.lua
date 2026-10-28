-- Split helper lives in compat (compat/pfUI.lua); don't duplicate it here.
local strsplit = pfUI and pfUI.api and pfUI.api.strsplit

local lastBroadcast = 0
local version, remote, major, minor, fix, displayed, available
local versioncheck = CreateFrame("Frame")
versioncheck:RegisterEvent("ADDON_LOADED")
versioncheck:RegisterEvent("CHAT_MSG_ADDON")
versioncheck:RegisterEvent("PARTY_MEMBERS_CHANGED")
versioncheck:RegisterEvent("RAID_ROSTER_UPDATE")
versioncheck:RegisterEvent("PLAYER_ENTERING_WORLD")
versioncheck:SetScript("OnEvent", function()
  if event == "ADDON_LOADED" then
    if strsub(tostring(arg1), 1, 7) == "pfQuest" then
      local vstr = string.gsub(tostring(GetAddOnMetadata(arg1, "Version")), "^v", "")
      major, minor, fix = strsplit(".", vstr)
      major = tonumber(major) or 0
      minor = tonumber(minor) or 0
      fix = tonumber(fix) or 0

      version = major * 10000 + minor * 100 + fix
    end

    return
  elseif event == "CHAT_MSG_ADDON" and arg1 == "pfQReborn" then
    local v, remoteversion = strsplit(":", arg2)
    local remoteversion = tonumber(remoteversion)
    if v == "VERSION" and remoteversion then
      -- Only trust group members: anyone on the addon channel could
      -- otherwise pin latest=999999 and trigger a bogus update notice.
      -- (arg4 is the sender; nil in unit tests counts as trusted.)
      local sender = arg4
      local trusted = (sender == nil)
      if not trusted and sender then
        local me = UnitName("player")
        if sender == me then
          trusted = true
        elseif GetNumRaidMembers and GetNumRaidMembers() > 0 and UnitInRaid then
          trusted = UnitInRaid(sender) ~= nil
        elseif GetNumPartyMembers and GetNumPartyMembers() > 0 and UnitInParty then
          trusted = UnitInParty(sender)
        end
      end
      if trusted then
        remote = remote and max(remote, remoteversion) or remoteversion
        if version and remote > version then
          pfQuest_config.latest = remote
        end
      end
    end
    return
  elseif event == "CHAT_MSG_ADDON" then
    return
  end

  -- abort here without local version
  if not version then
    return
  end

  -- send updates only on initial login or group join
  if version and (event == "PLAYER_ENTERING_WORLD" or event == "PARTY_MEMBERS_CHANGED" or event == "RAID_ROSTER_UPDATE") then
    local now = (GetTime and GetTime()) or 0
    if now - lastBroadcast >= 10 then
      lastBroadcast = now
      local chan = (GetNumRaidMembers and GetNumRaidMembers() > 0) and "RAID" or ((GetNumPartyMembers and GetNumPartyMembers() > 0) and "PARTY" or nil)
      if chan then SendAddonMessage("pfQReborn", "VERSION:" .. version, chan) end
    end
  end

  -- abort here on group member events
  if event == "PARTY_MEMBERS_CHANGED" or event == "RAID_ROSTER_UPDATE" then
    return
  end

  -- display available update
  if version and version > 0 and pfQuest_config.latest and pfQuest_config.latest > version and not displayed then
    DEFAULT_CHAT_FRAME:AddMessage(
      "|cff33ffccpf|cffffffffQuest |cff888888[Reborn]|r: " .. pfQuest_Loc["New version available!"]
    )
    displayed = true
  end
end)
