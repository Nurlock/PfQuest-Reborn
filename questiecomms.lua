-- Reforged: Questie group quest following compatibility
-- Implements bidirectional comms with Questie (prefixes "questie" and "QuestieV1")
-- Allows Questie players and pfQuest-Reforged players in a party to share quest
-- progress, view party members' tracked quest objectives on the map/minimap,
-- and see party members' progress on monster, item and object tooltips.

local compat = pfQuestCompat
pfQuest_Loc = pfQuest_Loc or {}
local L = pfQuest_Loc
pfQuest_config = pfQuest_config or {}

-- Performance: cache frequently-used globals
local pairs, ipairs, next, type = pairs, ipairs, next, type
local tostring, tonumber = tostring, tonumber
local floor, ceil, abs = math.floor, math.ceil, math.abs
local frexp, ldexp = math.frexp, math.ldexp
local strsub, strfind, stringchar, stringbyte, stringlen = string.sub, string.find, string.char, string.byte, string.len
local tinsert, tremove, tconcat = table.insert, table.remove, table.concat
local band, lshift, rshift = bit.band, bit.lshift, bit.rshift
local GetTime = GetTime
local UnitName = function(u) return _G.UnitName and _G.UnitName(u) end
local UnitClass = function(u) return _G.UnitClass and _G.UnitClass(u) end
local GetNumPartyMembers = function() return _G.GetNumPartyMembers and _G.GetNumPartyMembers() or 0 end
local GetNumRaidMembers = function() return _G.GetNumRaidMembers and _G.GetNumRaidMembers() or 0 end
local IsQuestWatched = function(q) return _G.IsQuestWatched and _G.IsQuestWatched(q) end
local SendAddonMessage = function(...) if _G.SendAddonMessage then return _G.SendAddonMessage(...) end end

local COMM_MESSAGE_VERSION = 5.0
local ADDON_VERSION_STR = "10.0.1" -- reports compatible version to Questie
local COMM_PREFIX = "questie"
local VISIBILITY_PREFIX = "QuestieV1"

local MSG_MULTI_FIRST = "\001"
local MSG_MULTI_NEXT = "\002"
local MSG_MULTI_LAST = "\003"
local MAX_MSG_LENGTH = 254

-- Message IDs matching QuestieComms
local QC_ID_BROADCAST_QUEST_UPDATE = 1
local QC_ID_BROADCAST_QUEST_REMOVE = 2
local QC_ID_BROADCAST_FULL_QUESTLIST = 10
local QC_ID_REQUEST_FULL_QUESTLIST = 11
local QC_ID_BROADCAST_FULL_QUESTLISTV2 = 12
local QC_ID_YELL_PROGRESS = 13
local QC_ID_BROADCAST_QUEST_UPDATEV2 = 14

local _classToIndex = {
  ["DRUID"] = 1,
  ["HUNTER"] = 2,
  ["MAGE"] = 3,
  ["PRIEST"] = 4,
  ["ROGUE"] = 5,
  ["SHAMAN"] = 6,
  ["WARLOCK"] = 7,
  ["WARRIOR"] = 8,
  ["PALADIN"] = 9,
  ["DEATHKNIGHT"] = 10,
}

local _indexToClass = {}
for class, idx in pairs(_classToIndex) do
  _indexToClass[idx] = class
end

-- ---------------------------------------------------------------------------
-- Binary Stream implementation for b89 and 1short encodings
-- ---------------------------------------------------------------------------
local MAX_TABLE_SIZE = 524288
local LOAD_BYTE_CHUNK = 4096

local realmList = string.lower(GetCVar and GetCVar("realmList") or "")
local isWarmane = strfind(realmList, "warmane", 1, true) ~= nil
local quoteEscapeByte = isWarmane and stringbyte("~") or stringbyte("|")

local QSL_dltab = {}
QSL_dltab[stringbyte("x")] = 0
QSL_dltab[stringbyte("y")] = 1
QSL_dltab[stringbyte("z")] = 2

local QSL_dttab = {}
QSL_dttab[123] = 1
QSL_dttab[quoteEscapeByte] = 6
QSL_dttab[125] = 59

local QSL_ltab = {}
local QSL_ttab = {}
QSL_ltab[0] = stringbyte("x")
QSL_ltab[1] = stringbyte("y")
QSL_ltab[2] = stringbyte("z")
QSL_ttab[34] = 123
QSL_ttab[39] = quoteEscapeByte
QSL_ttab[92] = 125

local _1short_control = 237
local _1short_zero = 238
local _1short_control_table = { _1short_control, _1short_zero }
local _1short_control_table_reversed = {}
for k, v in pairs(_1short_control_table) do
  _1short_control_table_reversed[v] = k
end

local function _pack(a, b, c, d)
  return lshift(a, 24) + lshift(b, 16) + lshift(c, 8) + d
end

local function _unpack(val)
  return (rshift(val, 24) % 256),
    (rshift(val, 16) % 256),
    (rshift(val, 8) % 256),
    (val % 256)
end

local function floatBitsToInt(n)
  local sign = 0
  if n < 0.0 then
    sign = 0x80
    n = -n
  end
  local mant, expo = frexp(n)
  if mant ~= mant then
    return _pack(0xFF, 0x88, 0x00, 0x00)
  elseif mant == math.huge or expo > 0x80 then
    if sign == 0 then
      return _pack(0x7F, 0x80, 0x00, 0x00)
    else
      return _pack(0xFF, 0x80, 0x00, 0x00)
    end
  elseif (mant == 0.0 and expo == 0) or expo < -0x7E then
    return _pack(sign, 0x00, 0x00, 0x00)
  else
    expo = expo + 0x7E
    mant = floor((mant * 2.0 - 1.0) * ldexp(0.5, 24))
    return _pack(sign + floor(expo / 0x2), (expo % 0x2) * 0x80 + floor(mant / 0x10000), floor(mant / 0x100) % 0x100, mant % 0x100)
  end
end

local function intBitsToFloat(int)
  local b1, b2, b3, b4 = _unpack(int)
  local sign = b1 > 0x7F
  local expo = (b1 % 0x80) * 0x2 + floor(b2 / 0x80)
  local mant = ((b2 % 0x80) * 0x100 + b3) * 0x100 + b4
  sign = sign and -1 or 1
  if mant == 0 and expo == 0 then
    return sign * 0.0
  elseif expo == 0xFF then
    if mant == 0 then
      return sign * math.huge
    else
      return 0.0 / 0.0
    end
  else
    return sign * ldexp(1.0 + mant / 0x800000, expo - 0x7F)
  end
end

local Stream = {}
Stream.__index = Stream

function Stream:New(mode)
  local o = setmetatable({}, Stream)
  o._mode = mode or "1short"
  o:Reset()
  return o
end

function Stream:Reset()
  self._pointer = 1
  self._bin = {}
  self._level = 0
end

function Stream:_writeByte(val)
  local subIndex = ceil(self._pointer / MAX_TABLE_SIZE)
  local index = self._pointer - (subIndex - 1) * MAX_TABLE_SIZE
  self._bin[subIndex] = self._bin[subIndex] or {}
  self._bin[subIndex][index] = stringchar(val)
  self._pointer = self._pointer + 1
end

function Stream:_readByte()
  local subIndex = ceil(self._pointer / MAX_TABLE_SIZE)
  local index = self._pointer - (subIndex - 1) * MAX_TABLE_SIZE
  self._pointer = self._pointer + 1
  return self._bin[subIndex] and self._bin[subIndex][index]
end

function Stream:WriteByte(e)
  if self._mode == "1short" then
    if _1short_control_table_reversed[e] then
      self:_writeByte(_1short_control)
      self:_writeByte(_1short_control_table_reversed[e])
    elseif e == 0 then
      self:_writeByte(_1short_zero)
    else
      self:_writeByte(e)
    end
  else -- b89
    if not e then return end
    local level = floor(e / 86)
    if self._level ~= level then
      self._level = level
      self:_writeByte(QSL_ltab[level])
    end
    local chr = (e % 86) + 33
    if QSL_ttab[chr] then
      self:_writeByte(QSL_ttab[chr])
    else
      self:_writeByte(chr)
    end
  end
end

function Stream:ReadByte()
  if self._mode == "1short" then
    local v = self:_readByte()
    if v == _1short_zero then
      return 0
    elseif v == _1short_control then
      v = self:_readByte()
      return _1short_control_table[v]
    end
    return v
  else -- b89
    local v = self:_readByte()
    if not v then return 0 end
    if QSL_dltab[v] then
      self._level = QSL_dltab[v]
      v = self:_readByte()
    end
    if QSL_dttab[v] then
      return self._level * 86 + QSL_dttab[v]
    else
      return self._level * 86 + v - 33
    end
  end
end

function Stream:WriteShort(val)
  self:WriteByte(rshift(val, 8) % 256)
  self:WriteByte(val % 256)
end

function Stream:ReadShort()
  return lshift(self:ReadByte(), 8) + self:ReadByte()
end

function Stream:WriteInt(val)
  self:WriteByte(rshift(val, 24) % 256)
  self:WriteByte(rshift(val, 16) % 256)
  self:WriteByte(rshift(val, 8) % 256)
  self:WriteByte(val % 256)
end

function Stream:ReadInt()
  return lshift(self:ReadByte(), 24) + lshift(self:ReadByte(), 16) + lshift(self:ReadByte(), 8) + self:ReadByte()
end

function Stream:WriteLong(val)
  self:WriteByte(floor(val / 72057594037927936) % 256) -- 2^56
  self:WriteByte(floor(val / 281474976710656) % 256)   -- 2^48
  self:WriteByte(floor(val / 1099511627776) % 256)     -- 2^40
  self:WriteByte(floor(val / 4294967296) % 256)        -- 2^32
  self:WriteByte(floor(val / 16777216) % 256)          -- 2^24
  self:WriteByte(floor(val / 65536) % 256)             -- 2^16
  self:WriteByte(floor(val / 256) % 256)               -- 2^8
  self:WriteByte(val % 256)
end

function Stream:ReadLong()
  local b7 = self:ReadByte() or 0
  local b6 = self:ReadByte() or 0
  local b5 = self:ReadByte() or 0
  local b4 = self:ReadByte() or 0
  local b3 = self:ReadByte() or 0
  local b2 = self:ReadByte() or 0
  local b1 = self:ReadByte() or 0
  local b0 = self:ReadByte() or 0
  return b7 * 72057594037927936
    + b6 * 281474976710656
    + b5 * 1099511627776
    + b4 * 4294967296
    + b3 * 16777216
    + b2 * 65536
    + b1 * 256
    + b0
end

function Stream:WriteTinyString(val)
  local length = stringlen(val)
  self:WriteByte(length)
  if self._mode == "b89" then
    for i = 1, length do
      self:_writeByte(stringbyte(val, i))
    end
  else
    for i = 1, length do
      self:WriteByte(stringbyte(val, i))
    end
  end
end

function Stream:ReadTinyString()
  local length = self:ReadByte()
  local ret = {}
  if self._mode == "b89" then
    for i = 1, length do
      tinsert(ret, self:_readByte())
    end
  else
    for i = 1, length do
      tinsert(ret, self:ReadByte())
    end
  end
  return stringchar(unpack(ret))
end

function Stream:WriteShortString(val)
  local length = stringlen(val)
  self:WriteShort(length)
  for i = 1, length do
    self:WriteByte(stringbyte(val, i))
  end
end

function Stream:ReadShortString()
  local length = self:ReadShort()
  local ret = {}
  for i = 1, length do
    tinsert(ret, self:ReadByte())
  end
  return stringchar(unpack(ret))
end

function Stream:Save()
  local chunks = {}
  for i = 1, #self._bin do
    chunks[i] = tconcat(self._bin[i])
  end
  return tconcat(chunks)
end

function Stream:Load(bin)
  self._pointer = 1
  self._bin = {}
  local len = stringlen(bin)
  local pointer = 1
  for startPos = 1, len, LOAD_BYTE_CHUNK do
    local endPos = startPos + LOAD_BYTE_CHUNK - 1
    if endPos > len then endPos = len end
    local bytes = { stringbyte(bin, startPos, endPos) }
    for i = 1, #bytes do
      local subIndex = ceil(pointer / MAX_TABLE_SIZE)
      local index = pointer - (subIndex - 1) * MAX_TABLE_SIZE
      self._bin[subIndex] = self._bin[subIndex] or {}
      self._bin[subIndex][index] = bytes[i]
      pointer = pointer + 1
    end
  end
  self._level = 0
end

-- ---------------------------------------------------------------------------
-- Questie Serializer implementation
-- ---------------------------------------------------------------------------
pfQuestieSerializer = {}
local Serializer = pfQuestieSerializer

Serializer.HashDB = {}
Serializer.HashDBReversed = {}

local function Hash(value)
  if not value or type(value) ~= "string" or stringlen(value) <= 0 then
    return 0
  end
  local h = 5381
  for i = 1, stringlen(value) do
    h = band((31 * h + stringbyte(value, i)), 4294967295)
  end
  return h
end

local function addHash(str)
  local hash = Hash(str)
  if Serializer.HashDBReversed[hash] then
    return
  end
  Serializer.HashDB[str] = hash
  Serializer.HashDBReversed[hash] = str
end

local function clearHashes()
  Serializer.HashDB = {}
  Serializer.HashDBReversed = {}
end

local function isArray(arr)
  local i = 0
  for e in pairs(arr) do
    i = i + 1
    if i ~= e then
      return false
    end
  end
  return true
end

local _ReadObject, _ReadTable, _ReadArray

_ReadObject = function(self)
  local typ = self.stream:ReadByte()
  if not typ then return nil end
  if typ > 31 then
    return typ - 32
  end
  local reader = Serializer.ReaderTable[typ]
  if reader then
    return reader(self)
  end
  return nil
end

_ReadTable = function(self, entryCount)
  local ret = {}
  for i = 1, entryCount do
    local key = _ReadObject(self)
    if type(key) == "string" then addHash(key) end
    local value = _ReadObject(self)
    if type(value) == "string" then addHash(value) end
    ret[key] = value
  end
  return ret
end

_ReadArray = function(self, entryCount)
  local ret = {}
  for i = 1, entryCount do
    local value = _ReadObject(self)
    if type(value) == "string" then addHash(value) end
    ret[i] = value
  end
  return ret
end

Serializer.ReaderTable = {
  [1] = function(self) return nil end,
  [2] = function(self) return self.stream:ReadInt() end,
  [3] = function(self) return -self.stream:ReadInt() end,
  [4] = function(self) return self.stream:ReadLong() end,
  [5] = function(self) return -self.stream:ReadLong() end,
  [6] = function(self) return intBitsToFloat(self.stream:ReadInt()) end,
  [7] = function(self) return self.stream:ReadTinyString() end,
  [8] = function(self) return self.stream:ReadShortString() end,
  [9] = function(self) return Serializer.HashDBReversed[self.stream:ReadInt()] end,
  [10] = function(self) return _ReadTable(self, self.stream:ReadByte()) end,
  [11] = function(self) return _ReadTable(self, self.stream:ReadShort()) end,
  [12] = function(self) return self.stream:ReadByte() end,
  [13] = function(self) return -self.stream:ReadByte() end,
  [14] = function(self) return self.stream:ReadShort() end,
  [15] = function(self) return -self.stream:ReadShort() end,
  [16] = function(self) return false end,
  [17] = function(self) return true end,
  [18] = function(self) return nil end,
  [19] = function(self) return nil end,
  [20] = function(self) return _ReadArray(self, self.stream:ReadByte()) end,
  [21] = function(self) return _ReadArray(self, self.stream:ReadShort()) end,
  [22] = function(self) return _ReadArray(self, self.stream:ReadInt()) end,
}

Serializer.WriterTable = {
  ["number"] = function(self, value)
    local _, fract = math.modf(value)
    if fract ~= 0 then
      Serializer.WriterTable["float"](self, value)
    else
      local sign = 0
      if value < 0 then
        value = abs(value)
        sign = 1
      end
      if value > 2147483646 then
        self.stream:WriteByte(4 + sign)
        self.stream:WriteLong(value)
      elseif value < 222 and sign == 0 then
        self.stream:WriteByte(32 + value)
      elseif value < 255 then
        self.stream:WriteByte(12 + sign)
        self.stream:WriteByte(value)
      elseif value < 65530 then
        self.stream:WriteByte(14 + sign)
        self.stream:WriteShort(value)
      else
        self.stream:WriteByte(2 + sign)
        self.stream:WriteInt(value)
      end
    end
  end,
  ["float"] = function(self, value)
    self.stream:WriteByte(6)
    self.stream:WriteInt(floatBitsToInt(value))
  end,
  ["string"] = function(self, value)
    if Serializer.HashDB[value] and stringlen(value) > 4 then
      self.stream:WriteByte(9)
      self.stream:WriteInt(Serializer.HashDB[value])
    elseif stringlen(value) > 254 then
      self.stream:WriteByte(8)
      self.stream:WriteShortString(value)
    else
      self.stream:WriteByte(7)
      self.stream:WriteTinyString(value)
    end
  end,
  ["table"] = function(self, value, depth)
    local count = 0
    depth = depth or 0
    if depth > 100 then return end
    for key, v in pairs(value) do
      if key ~= nil and v ~= nil then count = count + 1 end
    end
    if isArray(value) then
      if count > 65530 then
        self.stream:WriteByte(22)
        self.stream:WriteInt(count)
      elseif count > 254 then
        self.stream:WriteByte(21)
        self.stream:WriteShort(count)
      else
        self.stream:WriteByte(20)
        self.stream:WriteByte(count)
      end
      for _, v in pairs(value) do
        local t = type(v)
        local writer = Serializer.WriterTable[t]
        if writer then
          writer(self, v, depth)
          if t == "string" then addHash(v) end
        end
      end
    else
      if count > 254 then
        self.stream:WriteByte(11)
        self.stream:WriteShort(count)
      else
        self.stream:WriteByte(10)
        self.stream:WriteByte(count)
      end
      for key, v in pairs(value) do
        if key ~= nil and v ~= nil then
          Serializer:WriteKeyValuePair(key, v, depth + 1)
        end
      end
    end
  end,
  ["boolean"] = function(self, value)
    self.stream:WriteByte(value and 17 or 16)
  end,
  ["function"] = function(self, value)
    self.stream:WriteByte(1)
  end,
}

function Serializer:WriteKeyValuePair(key, value, depth)
  if value == nil or key == nil then return end
  depth = depth or 0
  local keyType = type(key)
  local valueType = type(value)
  local writeKey = Serializer.WriterTable[keyType]
  local writeValue = Serializer.WriterTable[valueType]
  if writeKey and writeValue then
    writeKey(self, key, depth)
    if keyType == "string" then addHash(key) end
    writeValue(self, value, depth)
    if valueType == "string" then addHash(value) end
  end
end

function Serializer:SetupStream(encoding)
  encoding = encoding or "1short"
  if self.stream and self.stream._mode == encoding then
    self.stream:Reset()
  else
    self.stream = Stream:New(encoding)
  end
  clearHashes()
end

function Serializer:Serialize(tab, encoding)
  self:SetupStream(encoding)
  Serializer:WriteKeyValuePair(1, tab)
  return self.stream:Save()
end

function Serializer:Deserialize(data, encoding)
  self:SetupStream(encoding)
  self.stream:Load(data)
  local retData = _ReadTable(self, 1)
  return retData and retData[1]
end

-- ---------------------------------------------------------------------------
-- pfQuestieComms Module
-- ---------------------------------------------------------------------------
pfQuest = pfQuest or CreateFrame("Frame")
pfQuestieComms = CreateFrame("Frame")
local comms = pfQuestieComms

-- Remote state storage
pfQuest.partyQuests = pfQuest.partyQuests or {}
pfQuest.partyVisibility = pfQuest.partyVisibility or {}
pfQuest.partyPlayerClasses = pfQuest.partyPlayerClasses or {}

-- Pre-indexed lookups for instant O(1) tooltip resolution
local partyObjectivesByMob = {}
local partyObjectivesByItem = {}
local partyObjectivesByObject = {}
local partyObjectivesByQuest = {}

-- Multipart spool for AceComm chunking
local multipartSpool = {}

function comms:ResetSpool()
  multipartSpool = {}
end

function comms:IsEnabled()
  if pfQuest_config["experimental"] ~= "1" then return false end
  if pfQuest_config["questiegroup"] == "0" then return false end
  return true
end

-- Splits text into chunks compliant with AceComm
function comms:ChunkMessage(prefix, text)
  local textlen = #text
  local maxtextlen = MAX_MSG_LENGTH - #prefix
  local chunks = {}

  if textlen <= maxtextlen then
    tinsert(chunks, { prefix = prefix, text = text })
  else
    maxtextlen = maxtextlen - 1 -- reserve 1 byte for part indicator in prefix
    -- first part
    tinsert(chunks, { prefix = prefix .. MSG_MULTI_FIRST, text = strsub(text, 1, maxtextlen) })
    -- continuation
    local pos = 1 + maxtextlen
    local prefixNext = prefix .. MSG_MULTI_NEXT
    while pos + maxtextlen <= textlen do
      tinsert(chunks, { prefix = prefixNext, text = strsub(text, pos, pos + maxtextlen - 1) })
      pos = pos + maxtextlen
    end
    -- final part
    tinsert(chunks, { prefix = prefix .. MSG_MULTI_LAST, text = strsub(text, pos) })
  end
  return chunks
end

local sendQueue = {}
local sendFrame = CreateFrame("Frame")
sendFrame:Hide()
local lastSendTime = 0
sendFrame:SetScript("OnUpdate", function()
  if #sendQueue == 0 then
    this:Hide()
    return
  end
  local now = GetTime()
  if now - lastSendTime < 0.05 then return end
  lastSendTime = now

  local msg = table.remove(sendQueue, 1)
  if msg then
    SendAddonMessage(msg.prefix, msg.text, msg.distribution, msg.target)
  end

  if #sendQueue == 0 then
    this:Hide()
  end
end)

function comms:SendComm(prefix, text, distribution, target)
  if not text or text == "" then return end
  local chunks = self:ChunkMessage(prefix, text)
  local CTL = _G.ChatThrottleLib
  if CTL and CTL.SendAddonMessage then
    for _, chunk in ipairs(chunks) do
      CTL:SendAddonMessage("NORMAL", chunk.prefix, chunk.text, distribution, target)
    end
  else
    if #sendQueue == 0 and #chunks == 1 then
      SendAddonMessage(chunks[1].prefix, chunks[1].text, distribution, target)
    elseif #sendQueue == 0 then
      -- Multi-chunk burst protection: send first chunk immediately, throttle subsequent chunks
      SendAddonMessage(chunks[1].prefix, chunks[1].text, distribution, target)
      for i = 2, #chunks do
        tinsert(sendQueue, {
          prefix = chunks[i].prefix,
          text = chunks[i].text,
          distribution = distribution,
          target = target,
        })
      end
      sendFrame:Show()
    else
      -- Pending queue exists: enqueue all chunks to preserve strict FIFO packet ordering
      for i = 1, #chunks do
        tinsert(sendQueue, {
          prefix = chunks[i].prefix,
          text = chunks[i].text,
          distribution = distribution,
          target = target,
        })
      end
      sendFrame:Show()
    end
  end
end

function comms:HandleMultipartChunk(prefix, message, distribution, sender)
  local ctrl = strsub(prefix, -1)
  local realPrefix = strsub(prefix, 1, -2)
  local key = realPrefix .. "\t" .. distribution .. "\t" .. sender

  if ctrl == MSG_MULTI_FIRST then
    multipartSpool[key] = { message }
    return nil
  elseif ctrl == MSG_MULTI_NEXT then
    if multipartSpool[key] then
      tinsert(multipartSpool[key], message)
    end
    return nil
  elseif ctrl == MSG_MULTI_LAST then
    if multipartSpool[key] then
      tinsert(multipartSpool[key], message)
      local full = tconcat(multipartSpool[key], "")
      multipartSpool[key] = nil
      return full
    else
      return message
    end
  end
  return message
end

-- ---------------------------------------------------------------------------
-- Objective Indexing & Cache
-- ---------------------------------------------------------------------------
local function addLookupEntry(tbl, key, entry)
  tbl[key] = tbl[key] or {}
  for _, existing in ipairs(tbl[key]) do
    if existing.playerName == entry.playerName and existing.questId == entry.questId and existing.objIndex == entry.objIndex then
      return
    end
  end
  tinsert(tbl[key], entry)
end

local function RebuildObjectiveLookups()
  partyObjectivesByMob = {}
  partyObjectivesByItem = {}
  partyObjectivesByObject = {}
  partyObjectivesByQuest = {}

  local pfDB = _G.pfDB
  for playerName, quests in pairs(pfQuest.partyQuests) do
    for questId, questData in pairs(quests) do
      partyObjectivesByQuest[questId] = partyObjectivesByQuest[questId] or {}
      partyObjectivesByQuest[questId][playerName] = questData

      local qData = pfDB and pfDB["quests"] and pfDB["quests"]["loc"] and pfDB["quests"]["loc"][questId]
      local qTitle = qData and qData.T or ("Quest " .. questId)
      local questBase = pfDB and pfDB["quests"] and pfDB["quests"]["data"] and pfDB["quests"]["data"][questId]

      if questData.objectives then
        for objIndex, obj in pairs(questData.objectives) do
          local entry = {
            playerName = playerName,
            questId = questId,
            questTitle = qTitle,
            objIndex = objIndex,
            objId = obj.id,
            objType = obj.type,
            fulfilled = obj.fulfilled or 0,
            required = obj.required or 1,
            finished = obj.finished or (obj.fulfilled and obj.required and obj.fulfilled >= obj.required),
            text = obj.text,
          }

          -- Index by known database names if ID is available
          if obj.id and obj.id > 0 and pfDB then
            if (obj.type == "monster" or obj.type == "m") and pfDB["units"] and pfDB["units"]["loc"] and pfDB["units"]["loc"][obj.id] then
              local name = pfDB["units"]["loc"][obj.id]
              addLookupEntry(partyObjectivesByMob, name, entry)
            elseif (obj.type == "item" or obj.type == "i") and pfDB["items"] and pfDB["items"]["loc"] and pfDB["items"]["loc"][obj.id] then
              local name = pfDB["items"]["loc"][obj.id]
              addLookupEntry(partyObjectivesByItem, name, entry)
            elseif (obj.type == "object" or obj.type == "o") and pfDB["objects"] and pfDB["objects"]["loc"] and pfDB["objects"]["loc"][obj.id] then
              local name = pfDB["objects"]["loc"][obj.id]
              addLookupEntry(partyObjectivesByObject, name, entry)
            end
          end

          -- Also index by quest-compiled objective spawns/names
          if questBase and questBase["obj"] and pfDB then
            if (obj.type == "monster" or obj.type == "m") and questBase["obj"]["U"] and questBase["obj"]["U"][objIndex] then
              local uid = questBase["obj"]["U"][objIndex] or questBase["obj"]["U"][1]
              local name = pfDB["units"] and pfDB["units"]["loc"] and pfDB["units"]["loc"][uid]
              if name then
                addLookupEntry(partyObjectivesByMob, name, entry)
              end
            elseif (obj.type == "item" or obj.type == "i") and questBase["obj"]["I"] and questBase["obj"]["I"][objIndex] then
              local iid = questBase["obj"]["I"][objIndex] or questBase["obj"]["I"][1]
              local name = pfDB["items"] and pfDB["items"]["loc"] and pfDB["items"]["loc"][iid]
              if name then
                addLookupEntry(partyObjectivesByItem, name, entry)
              end
            elseif (obj.type == "object" or obj.type == "o") and questBase["obj"]["O"] and questBase["obj"]["O"][objIndex] then
              local oid = questBase["obj"]["O"][objIndex] or questBase["obj"]["O"][1]
              local name = pfDB["objects"] and pfDB["objects"]["loc"] and pfDB["objects"]["loc"][oid]
              if name then
                addLookupEntry(partyObjectivesByObject, name, entry)
              end
            end
          end
        end
      end
    end
  end
end

-- ---------------------------------------------------------------------------
-- Map Nodes Management for Party Objectives
-- ---------------------------------------------------------------------------
local function UpdatePartyMapNodes(questId, playerName)
  if not comms:IsEnabled() or pfQuest_config["showpartyobjectives"] == "0" then
    return
  end

  local pfMap = _G.pfMap
  local pfDB = _G.pfDB
  local pfDatabase = _G.pfDatabase

  local qData = pfDB and pfDB["quests"] and pfDB["quests"]["loc"] and pfDB["quests"]["loc"][questId]
  local qTitle = qData and qData.T or ("Quest " .. questId)
  local nodeTitle = qTitle .. " (" .. playerName .. ")"

  -- Don't draw party nodes if the local player already has this quest
  if pfQuest.questlog and pfQuest.questlog[questId] then
    if pfMap and pfMap.DeleteNode then
      pfMap:DeleteNode("PARTY", nodeTitle)
      pfMap.queue_update = GetTime()
    end
    return
  end

  -- Check visibility
  local isVisible = comms:IsPartyObjectiveVisible(playerName, questId)
  local playerQuests = pfQuest.partyQuests[playerName]
  local questObj = playerQuests and playerQuests[questId]

  if not isVisible or not questObj then
    if pfMap and pfMap.DeleteNode then
      pfMap:DeleteNode("PARTY", nodeTitle)
      pfMap.queue_update = GetTime()
    end
    return
  end

  -- Check if all objectives are completed
  local allFinished = true
  if questObj.objectives and next(questObj.objectives) then
    for _, obj in pairs(questObj.objectives) do
      if not obj.finished and (not obj.fulfilled or not obj.required or obj.fulfilled < obj.required) then
        allFinished = false
        break
      end
    end
  else
    allFinished = false
  end

  if allFinished then
    if pfMap and pfMap.DeleteNode then
      pfMap:DeleteNode("PARTY", nodeTitle)
      pfMap.queue_update = GetTime()
    end
    return
  end

  -- Re-add node for this party member's quest
  if pfMap and pfMap.DeleteNode and pfDatabase and pfDatabase.SearchQuestID then
    pfMap:DeleteNode("PARTY", nodeTitle)
    local meta = {
      addon = "PARTY",
      partyMember = playerName,
      title = nodeTitle,
      quest = qTitle,
      questid = questId,
      color = playerName, -- gives each party member consistent distinctive coloring
    }

    pfDatabase:SearchQuestID(questId, meta)
    pfMap.queue_update = GetTime()
  end
end

function comms:IsPartyObjectiveVisible(playerName, questId)
  local snap = pfQuest.partyVisibility[playerName]
  if not snap then
    return true -- default visible for compatibility
  end
  return snap[questId] == true
end

-- ---------------------------------------------------------------------------
-- Packet Builders (Local -> Party)
-- ---------------------------------------------------------------------------
function comms:CreateQuestData(questId, qlogid)
  local questData = {
    id = questId,
    status = nil,
    objectives = {}
  }

  if not qlogid then
    return questData
  end

  local compat = _G.pfQuestCompat or _G.compat or _G
  local pfDB = _G.pfDB
  local expectedTitle = pfDB and pfDB["quests"] and pfDB["quests"]["loc"] and pfDB["quests"]["loc"][questId] and pfDB["quests"]["loc"][questId].T
  local title, _, _, _, _, complete = compat.GetQuestLogTitle(qlogid)

  -- Verify qlogid matches expected quest; if quest log shifted, find actual index
  if expectedTitle and title ~= expectedTitle then
    qlogid = nil
    local numEntries = GetNumQuestLogEntries and GetNumQuestLogEntries() or 0
    for qi = 1, numEntries do
      local t = compat.GetQuestLogTitle(qi)
      if t == expectedTitle then
        qlogid = qi
        title, _, _, _, _, complete = compat.GetQuestLogTitle(qlogid)
        break
      end
    end
  end

  if not qlogid then
    return questData
  end

  if complete == -1 then
    questData.status = "F"
  elseif complete == 1 then
    questData.status = "C"
  end

  local numObj = GetNumQuestLeaderBoards(qlogid) or 0
  local qDB = pfDB and pfDB["quests"] and pfDB["quests"]["data"] and pfDB["quests"]["data"][questId]
  local qObjDB = qDB and qDB["obj"]

  for i = 1, numObj do
    local text, objType, done = GetQuestLogLeaderBoard(i, qlogid)
    local cur, req
    if text then
      local _, _, c, r = strfind(text, "([%d]+)%s*/%s*([%d]+)%s*$")
      cur = tonumber(c)
      req = tonumber(r)
    end
    cur = cur or (done and 1 or 0)
    req = req or 1

    local typ = "m"
    if objType == "item" then
      typ = "i"
    elseif objType == "object" then
      typ = "o"
    elseif objType == "event" then
      typ = "e"
    end

    local rawId = 0
    if qObjDB then
      if typ == "m" and qObjDB["U"] then
        rawId = qObjDB["U"][i] or qObjDB["U"][1] or 0
      elseif typ == "i" and qObjDB["I"] then
        rawId = qObjDB["I"][i] or qObjDB["I"][1] or 0
      elseif typ == "o" and qObjDB["O"] then
        rawId = qObjDB["O"][i] or qObjDB["O"][1] or 0
      end
    end

    local desc = text and (string.match(text, "^(.-)%s*:%s*[%d]+%s*/%s*[%d]+") or text) or nil

    questData.objectives[i] = {
      index = i,
      id = rawId,
      typ = typ,
      type = typ,
      fin = done and true or (cur >= req),
      finished = done and true or (cur >= req),
      ful = cur,
      fulfilled = cur,
      req = req,
      required = req,
      text = desc,
    }
  end

  return questData
end

function comms:BroadcastQuestUpdate(questId)
  if not self:IsEnabled() then return end
  if not self:IsInGroup() then return end

  local data = pfQuest.questlog and pfQuest.questlog[questId]
  if not data or not data.qlogid then return end

  local questObj = self:CreateQuestData(questId, data.qlogid)
  local packet = {
    ver = ADDON_VERSION_STR,
    msgVer = COMM_MESSAGE_VERSION,
    msgId = QC_ID_BROADCAST_QUEST_UPDATE,
    quest = questObj,
  }

  local serialized = Serializer:Serialize(packet, "b89")
  local dist = self:GetGroupDistribution()
  if dist then
    self:SendComm(COMM_PREFIX, serialized, dist)
  end
end

function comms:BroadcastQuestRemove(questId)
  if not self:IsEnabled() then return end
  if not self:IsInGroup() then return end

  local packet = {
    ver = ADDON_VERSION_STR,
    msgVer = COMM_MESSAGE_VERSION,
    msgId = QC_ID_BROADCAST_QUEST_REMOVE,
    id = questId,
  }

  local serialized = Serializer:Serialize(packet, "b89")
  local dist = self:GetGroupDistribution()
  if dist then
    self:SendComm(COMM_PREFIX, serialized, dist)
  end
end

function comms:BroadcastFullQuestList(targetPlayer)
  if not self:IsEnabled() then return end
  local dist = targetPlayer and "WHISPER" or self:GetGroupDistribution()
  if not dist then return end

  local rawQuestList = {}
  if pfQuest.questlog then
    for questId, data in pairs(pfQuest.questlog) do
      if type(questId) == "number" and data.qlogid then
        rawQuestList[questId] = self:CreateQuestData(questId, data.qlogid)
      end
    end
  end

  local packet = {
    ver = ADDON_VERSION_STR,
    msgVer = COMM_MESSAGE_VERSION,
    msgId = QC_ID_BROADCAST_FULL_QUESTLIST,
    rawQuestList = rawQuestList,
  }

  local serialized = Serializer:Serialize(packet, "b89")
  self:SendComm(COMM_PREFIX, serialized, dist, targetPlayer)
end

function comms:SendVisibilitySnapshot(targetPlayer)
  if not self:IsEnabled() then return end
  local dist = targetPlayer and "WHISPER" or self:GetGroupDistribution()
  if not dist then return end

  local snapshot = {}
  if pfQuest.questlog then
    for questId, data in pairs(pfQuest.questlog) do
      if type(questId) == "number" and data.qlogid then
        if IsQuestWatched(data.qlogid) then
          snapshot[questId] = true
        end
      end
    end
  end

  local serialized = Serializer:Serialize(snapshot, "1short")
  self:SendComm(VISIBILITY_PREFIX, serialized, dist, targetPlayer)
end

function comms:RequestFullQuestList()
  if not self:IsEnabled() then return end
  local dist = self:GetGroupDistribution()
  if not dist then return end

  local packet = {
    ver = ADDON_VERSION_STR,
    msgVer = COMM_MESSAGE_VERSION,
    msgId = QC_ID_REQUEST_FULL_QUESTLIST,
  }

  local serialized = Serializer:Serialize(packet, "b89")
  self:SendComm(COMM_PREFIX, serialized, dist)
end

-- ---------------------------------------------------------------------------
-- Inbound Packet Handlers (Party -> Local)
-- ---------------------------------------------------------------------------
function comms:OnCommReceived(prefix, message, distribution, sender)
  if not message or not sender or sender == UnitName("player") then
    return
  end
  if not comms:IsEnabled() then
    return
  end

  if prefix == VISIBILITY_PREFIX then
    local success, snapshot = pcall(Serializer.Deserialize, Serializer, message, "1short")
    if success and type(snapshot) == "table" then
      pfQuest.partyVisibility[sender] = snapshot
      if pfQuest.partyQuests[sender] then
        for questId in pairs(pfQuest.partyQuests[sender]) do
          UpdatePartyMapNodes(questId, sender)
        end
      end
    end
    return
  end

  if prefix == COMM_PREFIX then
    local success, packet = pcall(Serializer.Deserialize, Serializer, message, "b89")
    if not success or type(packet) ~= "table" then
      return
    end

    if packet.msgVer and floor(packet.msgVer) ~= floor(COMM_MESSAGE_VERSION) then
      return
    end

    local msgId = packet.msgId
    if not msgId then return end

    pfQuest.partyQuests[sender] = pfQuest.partyQuests[sender] or {}

    local function NormalizeObjectives(rawObjectives)
      local normalized = {}
      if rawObjectives then
        for i, obj in pairs(rawObjectives) do
          local typ = obj.type or obj.typ or "m"
          local ful = obj.fulfilled or obj.ful or 0
          local req = obj.required or obj.req or 1
          local fin = (obj.finished ~= nil) and obj.finished or ((obj.fin ~= nil) and obj.fin or (ful >= req))
          normalized[i] = {
            index = i,
            id = obj.id,
            type = typ,
            typ = typ,
            fulfilled = ful,
            ful = ful,
            required = req,
            req = req,
            finished = fin,
            fin = fin,
            text = obj.text or obj.desc or obj.name,
          }
        end
      end
      return normalized
    end

    if msgId == QC_ID_BROADCAST_QUEST_UPDATE then
      if packet.quest and packet.quest.id then
        local qId = packet.quest.id
        pfQuest.partyQuests[sender][qId] = {
          id = qId,
          status = packet.quest.status,
          objectives = NormalizeObjectives(packet.quest.objectives)
        }
        RebuildObjectiveLookups()
        UpdatePartyMapNodes(qId, sender)
      end

    elseif msgId == QC_ID_BROADCAST_QUEST_REMOVE then
      if packet.id then
        local qId = packet.id
        pfQuest.partyQuests[sender][qId] = nil
        RebuildObjectiveLookups()
        local pfDB = _G.pfDB
        local pfMap = _G.pfMap
        local qData = pfDB and pfDB["quests"] and pfDB["quests"]["loc"] and pfDB["quests"]["loc"][qId]
        local qTitle = qData and qData.T or ("Quest " .. qId)
        if pfMap and pfMap.DeleteNode then
          pfMap:DeleteNode("PARTY", qTitle .. " (" .. sender .. ")")
          pfMap.queue_update = GetTime()
        end
      end

    elseif msgId == QC_ID_BROADCAST_FULL_QUESTLIST then
      if packet.rawQuestList then
        for qId, questData in pairs(packet.rawQuestList) do
          pfQuest.partyQuests[sender][qId] = {
            id = qId,
            status = questData.status,
            objectives = NormalizeObjectives(questData.objectives)
          }
          UpdatePartyMapNodes(qId, sender)
        end
        RebuildObjectiveLookups()
      end

    elseif msgId == QC_ID_REQUEST_FULL_QUESTLIST then
      self:BroadcastFullQuestList(sender)
      self:SendVisibilitySnapshot(sender)

    elseif msgId == QC_ID_BROADCAST_FULL_QUESTLISTV2 then
      -- Flat array v2 packet
      local block = packet[1]
      if block and type(block) == "table" then
        local failedQuests = {}
        if packet[2] then
          for _, qId in pairs(packet[2]) do
            failedQuests[qId] = true
          end
        end

        local count = block[1] or 0
        local offset = 2
        for _ = 1, count do
          local qId = block[offset]
          local objCount = block[offset + 1] or 0
          offset = offset + 2
          local objectives = {}
          for oIdx = 1, objCount do
            local rawId = block[offset]
            local typChar = block[offset + 1] and stringchar(block[offset + 1]) or "m"
            local ful = block[offset + 2] or 0
            local req = block[offset + 3] or 1
            objectives[oIdx] = {
              index = oIdx,
              id = rawId ~= 0 and rawId or nil,
              type = typChar,
              fulfilled = ful,
              required = req,
              finished = (ful >= req),
            }
            offset = offset + 4
          end
          pfQuest.partyQuests[sender][qId] = {
            id = qId,
            status = failedQuests[qId] and "F" or nil,
            objectives = objectives,
          }
          UpdatePartyMapNodes(qId, sender)
        end
        RebuildObjectiveLookups()
      end

    elseif msgId == QC_ID_BROADCAST_QUEST_UPDATEV2 then
      local block = packet[1]
      if block and type(block) == "table" then
        local qId = block[1]
        local objCount = block[2] or 0
        local offset = 3
        local objectives = {}
        for oIdx = 1, objCount do
          local rawId = block[offset]
          local typChar = block[offset + 1] and stringchar(block[offset + 1]) or "m"
          local ful = block[offset + 2] or 0
          local req = block[offset + 3] or 1
          objectives[oIdx] = {
            index = oIdx,
            id = rawId ~= 0 and rawId or nil,
            type = typChar,
            fulfilled = ful,
            required = req,
            finished = (ful >= req),
          }
          offset = offset + 4
        end
        pfQuest.partyQuests[sender][qId] = {
          id = qId,
          objectives = objectives,
        }
        RebuildObjectiveLookups()
        UpdatePartyMapNodes(qId, sender)
      end
    end
  end
end

-- ---------------------------------------------------------------------------
-- Group State & Utilities
-- ---------------------------------------------------------------------------
function comms:IsInGroup()
  return (GetNumRaidMembers() > 0) or (GetNumPartyMembers() > 0)
end

function comms:GetGroupDistribution()
  if GetNumRaidMembers() > 0 then
    return "RAID"
  elseif GetNumPartyMembers() > 0 then
    return "PARTY"
  end
  return nil
end

function comms:GetPlayerColor(playerName)
  local numParty = GetNumPartyMembers()
  for i = 1, numParty do
    if UnitName("party" .. i) == playerName then
      local _, class = UnitClass("party" .. i)
      if class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class] then
        local c = RAID_CLASS_COLORS[class]
        return string.format("|cff%02x%02x%02x", c.r * 255, c.g * 255, c.b * 255)
      end
      break
    end
  end
  return "|cff33ffcc"
end

function comms:PrunePartyMembers()
  local active = {}
  local numRaid = GetNumRaidMembers()
  if numRaid > 0 then
    for i = 1, numRaid do
      local name = UnitName("raid" .. i)
      if name then active[name] = true end
    end
  else
    local numParty = GetNumPartyMembers()
    for i = 1, numParty do
      local name = UnitName("party" .. i)
      if name then active[name] = true end
    end
  end

  for sender in pairs(pfQuest.partyQuests) do
    if not active[sender] then
      pfQuest.partyQuests[sender] = nil
      pfQuest.partyVisibility[sender] = nil
      if pfMap and pfMap.nodes and pfMap.nodes["PARTY"] then
        for map, coords in pairs(pfMap.nodes["PARTY"]) do
          for coord, titles in pairs(coords) do
            for title, node in pairs(titles) do
              if node.partyMember == sender then
                titles[title] = nil
              end
            end
          end
        end
        pfMap.queue_update = GetTime()
      end
    end
  end
  for k in pairs(multipartSpool) do
    local sender = string.match(k, "\t([^\t]+)$")
    if sender and not active[sender] then
      multipartSpool[k] = nil
    end
  end
  RebuildObjectiveLookups()
end

function comms:ClearAllPartyData()
  pfQuest.partyQuests = {}
  pfQuest.partyVisibility = {}
  multipartSpool = {}
  if pfMap and pfMap.nodes and pfMap.nodes["PARTY"] then
    pfMap.nodes["PARTY"] = {}
    pfMap.queue_update = GetTime()
  end
  RebuildObjectiveLookups()
end

-- ---------------------------------------------------------------------------
-- Tooltip Integration
-- ---------------------------------------------------------------------------
function comms:AddPartyTooltipLines(questTitle, tooltip)
  if not self:IsEnabled() or pfQuest_config["showpartytooltips"] == "0" then
    return
  end
  tooltip = tooltip or GameTooltip

  for playerName, quests in pairs(pfQuest.partyQuests) do
    for questId, questData in pairs(quests) do
      local qData = pfDB["quests"] and pfDB["quests"]["loc"] and pfDB["quests"]["loc"][questId]
      local title = qData and qData.T or ("Quest " .. questId)
      if title == questTitle and questData.objectives then
        local pColor = self:GetPlayerColor(playerName)
        local numObjs = 0
        for _ in pairs(questData.objectives) do numObjs = numObjs + 1 end
        for _, obj in pairs(questData.objectives) do
          local cur = obj.fulfilled or 0
          local req = obj.required or 1
          local status = obj.finished and (" |cff00ff00(" .. (pfQuest_Loc["Complete"] or "Complete") .. ")|r") or ""
          local objLabel = ""
          if numObjs > 1 then
            if obj.text and obj.text ~= "" then
              objLabel = " (" .. obj.text .. ")"
            elseif obj.index then
              objLabel = " (#" .. obj.index .. ")"
            end
          end
          tooltip:AddLine("  " .. pColor .. playerName .. "|r" .. objLabel .. ": " .. cur .. "/" .. req .. status, 0.8, 0.8, 0.8)
        end
      end
    end
  end
end

function comms:ShowWorldTooltip(name, tooltip)
  if not self:IsEnabled() or pfQuest_config["showpartytooltips"] == "0" then
    return
  end
  if not name or name == "__NONE__" then return end
  tooltip = tooltip or GameTooltip

  if tooltip._pfQuestieTooltipName == name then
    return
  end

  local entries = partyObjectivesByMob[name] or partyObjectivesByObject[name] or partyObjectivesByItem[name]
  if not entries or #entries == 0 then return end

  tooltip._pfQuestieTooltipName = name

  local shownQuests = {}
  for _, entry in ipairs(entries) do
    local pColor = self:GetPlayerColor(entry.playerName)
    if not shownQuests[entry.questTitle] then
      shownQuests[entry.questTitle] = true
      tooltip:AddLine("|cff555555[|cff33ffcc!|cff555555]|r " .. entry.questTitle .. " (" .. pColor .. (pfQuest_Loc["Party: "] or "Party: ") .. entry.playerName .. "|r)", 1, 1, 0.7)
    end
    local status = entry.finished and (" |cff00ff00(" .. (pfQuest_Loc["Complete"] or "Complete") .. ")|r") or ""
    local objDesc = (entry.text and entry.text ~= "") and (" (" .. entry.text .. ")") or ""
    tooltip:AddLine("  " .. pColor .. entry.playerName .. "|r" .. objDesc .. ": " .. entry.fulfilled .. "/" .. entry.required .. status, 0.8, 0.8, 0.8)
  end
  tooltip:Show()
end

-- ---------------------------------------------------------------------------
-- Event Handlers & Hooks
-- ---------------------------------------------------------------------------
comms:RegisterEvent("ADDON_LOADED")
comms:RegisterEvent("CHAT_MSG_ADDON")
comms:RegisterEvent("PARTY_MEMBERS_CHANGED")
comms:RegisterEvent("RAID_ROSTER_UPDATE")
comms:RegisterEvent("PLAYER_ENTERING_WORLD")
comms:RegisterEvent("QUEST_WATCH_UPDATE")

local wasInGroup = false

comms:SetScript("OnEvent", function()
  if event == "CHAT_MSG_ADDON" then
    local prefix, message, distribution, sender = arg1, arg2, arg3, arg4
    if prefix and (strsub(prefix, 1, #COMM_PREFIX) == COMM_PREFIX or strsub(prefix, 1, #VISIBILITY_PREFIX) == VISIBILITY_PREFIX) then
      local full = comms:HandleMultipartChunk(prefix, message, distribution, sender)
      if full then
        local realPrefix = (strsub(prefix, 1, #COMM_PREFIX) == COMM_PREFIX) and COMM_PREFIX or VISIBILITY_PREFIX
        comms:OnCommReceived(realPrefix, full, distribution, sender)
      end
    end

  elseif event == "PARTY_MEMBERS_CHANGED" or event == "RAID_ROSTER_UPDATE" then
    local inGroup = comms:IsInGroup()
    if inGroup and not wasInGroup then
      -- Just joined a group
      wasInGroup = true
      if comms:IsEnabled() then
        comms:RequestFullQuestList()
        comms:BroadcastFullQuestList()
        comms:SendVisibilitySnapshot()
      end
    elseif not inGroup and wasInGroup then
      -- Left the group
      wasInGroup = false
      comms:ClearAllPartyData()
    elseif inGroup then
      comms:PrunePartyMembers()
    end

  elseif event == "PLAYER_ENTERING_WORLD" then
    wasInGroup = comms:IsInGroup()
    if wasInGroup and comms:IsEnabled() then
      comms:RequestFullQuestList()
      comms:BroadcastFullQuestList()
      comms:SendVisibilitySnapshot()
    end

  elseif event == "QUEST_WATCH_UPDATE" then
    if comms:IsInGroup() and comms:IsEnabled() then
      comms:SendVisibilitySnapshot()
    end
  end
end)

-- Hook Item and Unit Tooltips for Party Quest Objectives
local function HookTooltip(tip)
  if not tip or not tip.HookScript then return end
  tip:HookScript("OnTooltipCleared", function(self)
    self._pfQuestieTooltipName = nil
  end)
  tip:HookScript("OnHide", function(self)
    self._pfQuestieTooltipName = nil
  end)
  tip:HookScript("OnTooltipSetItem", function(self)
    if not comms:IsEnabled() or pfQuest_config["showpartytooltips"] == "0" then
      return
    end
    local name = self:GetItem()
    if name then
      comms:ShowWorldTooltip(name, self)
    end
  end)
  tip:HookScript("OnTooltipSetUnit", function(self)
    if not comms:IsEnabled() or pfQuest_config["showpartytooltips"] == "0" then
      return
    end
    local name = self:GetUnit()
    if name then
      comms:ShowWorldTooltip(name, self)
    end
  end)
end

if GameTooltip then HookTooltip(GameTooltip) end
if ItemRefTooltip then HookTooltip(ItemRefTooltip) end

-- Export module
pfQuest.questieComms = comms
