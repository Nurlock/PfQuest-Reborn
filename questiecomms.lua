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
local unpack = unpack or table.unpack
local floor, ceil, abs = math.floor, math.ceil, math.abs
local frexp, ldexp = math.frexp, math.ldexp
local strsub, strfind, stringchar, stringbyte, stringlen = string.sub, string.find, string.char, string.byte, string.len
local strsplit = _G.strsplit or function(delim, str)
  if not str then return nil end
  local pos = strfind(str, delim, 1, true)
  if not pos then return str end
  return strsub(str, 1, pos - 1), strsub(str, pos + stringlen(delim))
end
local tinsert, tremove, tconcat = table.insert, table.remove, table.concat
local band, lshift, rshift = bit.band, bit.lshift, bit.rshift
local GetTime = GetTime
local UnitName = function(u) if _G.UnitName then return _G.UnitName(u) end end
local UnitClass = function(u) if _G.UnitClass then return _G.UnitClass(u) end end
local GetNumPartyMembers = function() return _G.GetNumPartyMembers and _G.GetNumPartyMembers() or 0 end
local GetNumRaidMembers = function() return _G.GetNumRaidMembers and _G.GetNumRaidMembers() or 0 end
local IsQuestWatched = function(q) if _G.IsQuestWatched then return _G.IsQuestWatched(q) end end
local SendAddonMessage = function(...) if _G.SendAddonMessage then return _G.SendAddonMessage(...) end end
local SendChatMessage = function(...) if _G.SendChatMessage then return _G.SendChatMessage(...) end end

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
  if not length or length <= 0 then return "" end
  local chars = {}
  if self._mode == "b89" then
    for i = 1, length do
      chars[i] = stringchar(self:_readByte() or 0)
    end
  else
    for i = 1, length do
      chars[i] = stringchar(self:ReadByte() or 0)
    end
  end
  return tconcat(chars)
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
  if not length or length <= 0 then return "" end
  local chars = {}
  for i = 1, length do
    chars[i] = stringchar(self:ReadByte() or 0)
  end
  return tconcat(chars)
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
  if pfQuest_config then
    if pfQuest_config["experimental"] ~= "1" then return false end
    if pfQuest_config["questiegroup"] == "0" then return false end
  end
  return true
end

-- Splits text into chunks compliant with AceComm-3.0
function comms:ChunkMessage(prefix, text)
  local textlen = #text
  local maxtextlen = MAX_MSG_LENGTH
  local chunks = {}

  if textlen <= maxtextlen then
    tinsert(chunks, { prefix = prefix, text = text })
  else
    -- AceComm-3.0 wire format: control byte appended to prefix
    -- First chunk
    tinsert(chunks, { prefix = prefix .. MSG_MULTI_FIRST, text = strsub(text, 1, maxtextlen) })
    -- Continuation chunks
    local pos = 1 + maxtextlen
    while pos + maxtextlen <= textlen do
      tinsert(chunks, { prefix = prefix .. MSG_MULTI_NEXT, text = strsub(text, pos, pos + maxtextlen - 1) })
      pos = pos + maxtextlen
    end
    -- Final chunk
    tinsert(chunks, { prefix = prefix .. MSG_MULTI_LAST, text = strsub(text, pos) })
  end
  return chunks
end

local sendQueue = {}
local sendFrame = CreateFrame("Frame")
sendFrame:Hide()
local lastSendTime = 0
sendFrame:SetScript("OnUpdate", function(self)
  if #sendQueue == 0 then
    if self then self:Hide() else sendFrame:Hide() end
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
    if self then self:Hide() else sendFrame:Hide() end
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
  if not message or message == "" then return message end
  local now = GetTime()

  -- Standard AceComm-3.0 wire format (control byte appended to prefix)
  local pfxCtrl = strsub(prefix, -1)
  if pfxCtrl == MSG_MULTI_FIRST or pfxCtrl == MSG_MULTI_NEXT or pfxCtrl == MSG_MULTI_LAST then
    local realPrefix = strsub(prefix, 1, -2)
    local pfxKey = realPrefix .. "\t" .. distribution .. "\t" .. sender
    if pfxCtrl == MSG_MULTI_FIRST then
      multipartSpool[pfxKey] = { message, time = now }
      return nil
    elseif pfxCtrl == MSG_MULTI_NEXT then
      if multipartSpool[pfxKey] then
        tinsert(multipartSpool[pfxKey], message)
        multipartSpool[pfxKey].time = now
      end
      return nil
    elseif pfxCtrl == MSG_MULTI_LAST then
      if multipartSpool[pfxKey] then
        tinsert(multipartSpool[pfxKey], message)
        local full = tconcat(multipartSpool[pfxKey], "")
        multipartSpool[pfxKey] = nil
        return full
      else
        return message
      end
    end
  end

  -- Backward-compatibility fallback (control byte at start of message)
  local msgCtrl = strsub(message, 1, 1)
  local key = prefix .. "\t" .. distribution .. "\t" .. sender

  if msgCtrl == MSG_MULTI_FIRST then
    multipartSpool[key] = { strsub(message, 2), time = now }
    return nil
  elseif msgCtrl == MSG_MULTI_NEXT then
    if multipartSpool[key] then
      tinsert(multipartSpool[key], strsub(message, 2))
      multipartSpool[key].time = now
    end
    return nil
  elseif msgCtrl == MSG_MULTI_LAST then
    if multipartSpool[key] then
      tinsert(multipartSpool[key], strsub(message, 2))
      local full = tconcat(multipartSpool[key], "")
      multipartSpool[key] = nil
      return full
    else
      return strsub(message, 2)
    end
  elseif msgCtrl == "\004" then
    return strsub(message, 2)
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
  if not pfDB then return end

  for playerName, quests in pairs(pfQuest.partyQuests) do
    for questId, questData in pairs(quests) do
      partyObjectivesByQuest[questId] = partyObjectivesByQuest[questId] or {}
      partyObjectivesByQuest[questId][playerName] = questData

      local qData = pfDB["quests"] and pfDB["quests"]["loc"] and pfDB["quests"]["loc"][questId]
      local qTitle = qData and qData.T or ("Quest " .. questId)
      local questBase = pfDB["quests"] and pfDB["quests"]["data"] and pfDB["quests"]["data"][questId]

      if questData.objectives then
        for objIndex, obj in pairs(questData.objectives) do
          local ful = tonumber(obj.fulfilled or obj.ful or obj.Collected or obj.numFulfilled) or 0
          local req = tonumber(obj.required or obj.req or obj.Needed or obj.numRequired) or 1
          local fin = (obj.finished ~= nil and obj.finished)
            or (obj.fin ~= nil and obj.fin)
            or (obj.Finished ~= nil and obj.Finished)
            or (obj.Completed ~= nil and obj.Completed)
            or (ful >= req)

          local text = obj.text or obj.desc or obj.name or obj.Description or obj.Text
          local objType = obj.type or obj.typ or obj.Type or "m"
          if type(objType) == "string" then
            local low = string.lower(objType)
            if low == "monster" or low == "creature" or low == "m" then
              objType = "m"
            elseif low == "item" or low == "i" then
              objType = "i"
            elseif low == "object" or low == "gameobject" or low == "o" then
              objType = "o"
            end
          else
            objType = "m"
          end

          local directId = obj.id or obj.Id

          local entry = {
            playerName = playerName,
            questId = questId,
            questTitle = qTitle,
            objIndex = objIndex,
            objId = directId,
            objType = objType,
            fulfilled = ful,
            required = req,
            finished = fin,
            text = text,
          }

          -- 1. Index by direct objective ID if available
          if directId and directId > 0 then
            if (objType == "m") and pfDB["units"] and pfDB["units"]["loc"] and pfDB["units"]["loc"][directId] then
              addLookupEntry(partyObjectivesByMob, pfDB["units"]["loc"][directId], entry)
            elseif (objType == "i") and pfDB["items"] and pfDB["items"]["loc"] and pfDB["items"]["loc"][directId] then
              addLookupEntry(partyObjectivesByItem, pfDB["items"]["loc"][directId], entry)
              -- Also index gathering objects and mobs that drop this item
              if pfDB["items"]["data"] and pfDB["items"]["data"][directId] then
                local itemData = pfDB["items"]["data"][directId]
                if itemData["O"] and pfDB["objects"] and pfDB["objects"]["loc"] then
                  for oid in pairs(itemData["O"]) do
                    local oname = pfDB["objects"]["loc"][oid]
                    if oname then
                      addLookupEntry(partyObjectivesByObject, oname, entry)
                    end
                  end
                end
                if itemData["U"] and pfDB["units"] and pfDB["units"]["loc"] then
                  for uid in pairs(itemData["U"]) do
                    local uname = pfDB["units"]["loc"][uid]
                    if uname then
                      addLookupEntry(partyObjectivesByMob, uname, entry)
                    end
                  end
                end
              end
            elseif (objType == "o") and pfDB["objects"] and pfDB["objects"]["loc"] and pfDB["objects"]["loc"][directId] then
              addLookupEntry(partyObjectivesByObject, pfDB["objects"]["loc"][directId], entry)
            end
          end

          -- 2. Index by text name directly if available
          if text and text ~= "" then
            local cleanText = string.match(text, "^(.-)%s*:%s*[%d]+%s*/%s*[%d]+")
              or string.match(text, "^(.-)%s+[%d]+%s*/%s*[%d]+")
              or string.match(text, "^[%d]+%s*/%s*[%d]+%s*(.-)$")
              or text
            cleanText = string.gsub(cleanText, "^Kill%s+", "")
            cleanText = string.gsub(cleanText, "^Collect%s+", "")
            cleanText = string.gsub(cleanText, "%s+slain$", "")

            if objType == "m" then
              addLookupEntry(partyObjectivesByMob, cleanText, entry)
              addLookupEntry(partyObjectivesByMob, text, entry)
            elseif objType == "o" then
              addLookupEntry(partyObjectivesByObject, cleanText, entry)
              addLookupEntry(partyObjectivesByObject, text, entry)
            elseif objType == "i" then
              addLookupEntry(partyObjectivesByItem, cleanText, entry)
              addLookupEntry(partyObjectivesByItem, text, entry)
            end
          end

          -- 3. Also index from quest database compiled spawns/dependencies
          if questBase and questBase["obj"] then
            -- Monster kills / units
            if (objType == "m") and questBase["obj"]["U"] and pfDB["units"] and pfDB["units"]["loc"] then
              for _, uid in ipairs(questBase["obj"]["U"]) do
                local uname = pfDB["units"]["loc"][uid]
                if uname then
                  if not text or strfind(text, uname, 1, true) or strfind(uname, text, 1, true) or (directId == uid) or (#questData.objectives == 1) then
                    addLookupEntry(partyObjectivesByMob, uname, entry)
                  end
                end
              end
            end

            -- Gathering gameobjects
            if (objType == "o") and questBase["obj"]["O"] and pfDB["objects"] and pfDB["objects"]["loc"] then
              for _, oid in ipairs(questBase["obj"]["O"]) do
                local oname = pfDB["objects"]["loc"][oid]
                if oname then
                  if not text or strfind(text, oname, 1, true) or strfind(oname, text, 1, true) or (directId == oid) or (#questData.objectives == 1) then
                    addLookupEntry(partyObjectivesByObject, oname, entry)
                  end
                end
              end
            end

            -- Items (and their source objects & mobs)
            if (objType == "i") and questBase["obj"]["I"] and pfDB["items"] and pfDB["items"]["loc"] then
              for _, iid in ipairs(questBase["obj"]["I"]) do
                local iname = pfDB["items"]["loc"][iid]
                if iname then
                  if not text or strfind(text, iname, 1, true) or strfind(iname, text, 1, true) or (directId == iid) or (#questData.objectives == 1) then
                    addLookupEntry(partyObjectivesByItem, iname, entry)
                    if pfDB["items"]["data"] and pfDB["items"]["data"][iid] then
                      local itemData = pfDB["items"]["data"][iid]
                      if itemData["O"] and pfDB["objects"] and pfDB["objects"]["loc"] then
                        for oid in pairs(itemData["O"]) do
                          local oname = pfDB["objects"]["loc"][oid]
                          if oname then
                            addLookupEntry(partyObjectivesByObject, oname, entry)
                          end
                        end
                      end
                      if itemData["U"] and pfDB["units"] and pfDB["units"]["loc"] then
                        for uid in pairs(itemData["U"]) do
                          local uname = pfDB["units"]["loc"][uid]
                          if uname then
                            addLookupEntry(partyObjectivesByMob, uname, entry)
                          end
                        end
                      end
                    end
                  end
                end
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
function comms:DeletePartyQuestNodes(questId, sender)
  local pfMap = _G.pfMap
  if not pfMap then return end

  local pfDB = _G.pfDB
  local numQId = tonumber(questId)
  local qData = pfDB and pfDB["quests"] and pfDB["quests"]["loc"] and (pfDB["quests"]["loc"][questId] or (numQId and pfDB["quests"]["loc"][numQId]))
  if not qData and type(questId) == "string" and pfDB and pfDB["quests"] and pfDB["quests"]["loc"] then
    for dbId, qd in pairs(pfDB["quests"]["loc"]) do
      if qd.T == questId then
        qData = qd
        numQId = dbId
        break
      end
    end
  end
  local qTitle = qData and qData.T or (type(questId) == "string" and questId) or ("Quest " .. tostring(questId))
  local nodeTitle = sender and (qTitle .. " (" .. sender .. ")") or qTitle

  if pfMap.DeleteNode then
    if sender then
      pfMap:DeleteNode("PARTY", nodeTitle)
    end
    pfMap:DeleteNode("PARTY", qTitle)
    if type(questId) == "string" and questId ~= qTitle then
      if sender then
        pfMap:DeleteNode("PARTY", questId .. " (" .. sender .. ")")
      end
      pfMap:DeleteNode("PARTY", questId)
    end
  end

  if pfMap.nodes and pfMap.nodes["PARTY"] then
    for map, coords in pairs(pfMap.nodes["PARTY"]) do
      for coord, titles in pairs(coords) do
        for title, node in pairs(titles) do
          if (not sender or node.partyMember == sender) and
             (node.questid == questId or (numQId and node.questid == numQId) or
              node.quest == qTitle or title == nodeTitle or title == qTitle or
              (type(questId) == "string" and (node.quest == questId or title == questId))) then
            titles[title] = nil
            if pfMap.titleIndex and pfMap.titleIndex["PARTY"] and pfMap.titleIndex["PARTY"][title] then
              if pfMap.titleIndex["PARTY"][title][map] then
                pfMap.titleIndex["PARTY"][title][map][coord] = nil
              end
            end
          end
        end
        if pfMap.IsEmpty and pfMap.IsEmpty(titles) then
          coords[coord] = nil
        elseif next(titles) == nil then
          coords[coord] = nil
        end
      end
    end
  end

  pfMap.queue_update = GetTime()
  pfMap.tick = nil
  if pfMap.UpdateNodes then
    pfMap:UpdateNodes()
  end
end

local function UpdatePartyMapNodes(questId, playerName)
  if not comms:IsEnabled() or pfQuest_config["showpartyobjectives"] == "0" then
    return
  end
  if playerName == UnitName("player") then
    return
  end

  local numQId = tonumber(questId)

  -- Don't draw party nodes if the local player already has this quest
  if pfQuest.questlog and (pfQuest.questlog[questId] or (numQId and pfQuest.questlog[numQId])) then
    comms:DeletePartyQuestNodes(questId, playerName)
    return
  end

  -- Check visibility
  local isVisible = comms:IsPartyObjectiveVisible(playerName, questId)
  local playerQuests = pfQuest.partyQuests[playerName]
  local questObj = playerQuests and (playerQuests[questId] or (numQId and playerQuests[numQId]))

  if not isVisible or not questObj then
    comms:DeletePartyQuestNodes(questId, playerName)
    return
  end

  -- Check if all objectives are completed or status is Complete
  local isCompleteStatus = false
  if questObj.status then
    local s = type(questObj.status) == "string" and string.lower(questObj.status) or questObj.status
    if s == "c" or s == "complete" or s == "done" or s == 1 or s == "1" then
      isCompleteStatus = true
    end
  end
  if questObj.finished == true or questObj.finished == 1 or questObj.finished == "1" or
     questObj.isComplete == true or questObj.isComplete == 1 or questObj.isComplete == "1" or
     questObj.complete == true or questObj.complete == 1 or questObj.complete == "1" then
    isCompleteStatus = true
  end

  local allFinished = isCompleteStatus
  if not allFinished and questObj.objectives and next(questObj.objectives) then
    allFinished = true
    for _, obj in pairs(questObj.objectives) do
      local isDone = false
      if obj.finished == true or obj.finished == 1 or obj.finished == "1" or
         obj.fin == true or obj.fin == 1 or obj.fin == "1" or
         obj.Finished == true or obj.Finished == 1 or obj.Finished == "1" or
         obj.Completed == true or obj.Completed == 1 or obj.Completed == "1" then
        isDone = true
      end
      local ful = tonumber(obj.fulfilled or obj.ful or obj.Collected or obj.numFulfilled) or 0
      local req = tonumber(obj.required or obj.req or obj.Needed or obj.numRequired) or 1
      if not isDone and (ful >= req) then
        isDone = true
      end
      if not isDone then
        allFinished = false
        break
      end
    end
  end

  if allFinished then
    comms:DeletePartyQuestNodes(questId, playerName)
    return
  end

  -- Re-add node for this party member's quest
  local pfMap = _G.pfMap
  local pfDB = _G.pfDB
  local pfDatabase = _G.pfDatabase
  local qData = pfDB and pfDB["quests"] and pfDB["quests"]["loc"] and (pfDB["quests"]["loc"][questId] or (numQId and pfDB["quests"]["loc"][numQId]))
  local qTitle = qData and qData.T or (type(questId) == "string" and questId) or ("Quest " .. tostring(questId))
  local nodeTitle = qTitle .. " (" .. playerName .. ")"

  if pfMap and pfDatabase and pfDatabase.SearchQuestID then
    comms:DeletePartyQuestNodes(questId, playerName)
    local meta = {
      addon = "PARTY",
      partyMember = playerName,
      title = nodeTitle,
      quest = qTitle,
      questid = numQId or questId,
      color = playerName, -- gives each party member consistent distinctive coloring
    }

    pfDatabase:SearchQuestID(numQId or questId, meta)
    pfMap.queue_update = GetTime()
    pfMap.tick = nil
    if pfMap.UpdateNodes then
      pfMap:UpdateNodes()
    end
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
    local desc = nil
    if qObjDB and pfDB then
      if typ == "m" and qObjDB["U"] and pfDB["units"] and pfDB["units"]["loc"] then
        for _, uid in ipairs(qObjDB["U"]) do
          local uname = pfDB["units"]["loc"][uid]
          if uname and text and strfind(text, uname, 1, true) then
            rawId = uid
            desc = uname
            break
          end
        end
        if rawId == 0 then
          rawId = qObjDB["U"][i] or qObjDB["U"][1] or 0
        end
      elseif typ == "i" and qObjDB["I"] and pfDB["items"] and pfDB["items"]["loc"] then
        for _, iid in ipairs(qObjDB["I"]) do
          local iname = pfDB["items"]["loc"][iid]
          if iname and text and strfind(text, iname, 1, true) then
            rawId = iid
            desc = iname
            break
          end
        end
        if rawId == 0 then
          rawId = qObjDB["I"][i] or qObjDB["I"][1] or 0
        end
      elseif typ == "o" and qObjDB["O"] and pfDB["objects"] and pfDB["objects"]["loc"] then
        for _, oid in ipairs(qObjDB["O"]) do
          local oname = pfDB["objects"]["loc"][oid]
          if oname and text and strfind(text, oname, 1, true) then
            rawId = oid
            desc = oname
            break
          end
        end
        if rawId == 0 then
          rawId = qObjDB["O"][i] or qObjDB["O"][1] or 0
        end
      end
    end

    if not desc and text then
      desc = string.match(text, "^(.-)%s*:%s*[%d]+%s*/%s*[%d]+")
        or string.match(text, "^(.-)%s+[%d]+%s*/%s*[%d]+")
        or string.match(text, "^[%d]+%s*/%s*[%d]+%s*(.-)$")
        or text
      desc = string.gsub(desc, "^Kill%s+", "")
      desc = string.gsub(desc, "^Collect%s+", "")
      desc = string.gsub(desc, "%s+slain$", "")
    end

    local isDone = done and true or (cur >= req)

    questData.objectives[i] = {
      index = i,
      id = rawId,
      typ = typ,
      fin = isDone,
      ful = cur,
      req = req,
      text = desc,
    }
  end

  return questData
end

function comms:UpdateLocalPlayerQuest(questId)
  local playerName = UnitName("player")
  if not playerName or not self:IsInGroup() then return end
  pfQuest.partyQuests = pfQuest.partyQuests or {}
  pfQuest.partyQuests[playerName] = pfQuest.partyQuests[playerName] or {}

  local data = pfQuest.questlog and pfQuest.questlog[questId]
  if data and data.qlogid then
    pfQuest.partyQuests[playerName][questId] = self:CreateQuestData(questId, data.qlogid)
  else
    pfQuest.partyQuests[playerName][questId] = nil
  end
  RebuildObjectiveLookups()
end

function comms:RemoveLocalPlayerQuest(questId)
  local playerName = UnitName("player")
  if not playerName then return end
  if pfQuest.partyQuests and pfQuest.partyQuests[playerName] then
    pfQuest.partyQuests[playerName][questId] = nil
    RebuildObjectiveLookups()
  end
end

function comms:UpdateLocalPlayerQuests()
  local playerName = UnitName("player")
  if not playerName then return end

  if not self:IsInGroup() then
    if pfQuest.partyQuests and pfQuest.partyQuests[playerName] then
      pfQuest.partyQuests[playerName] = nil
      RebuildObjectiveLookups()
    end
    return
  end

  pfQuest.partyQuests = pfQuest.partyQuests or {}
  local localQuests = {}

  if pfQuest.questlog then
    for questId, data in pairs(pfQuest.questlog) do
      if tonumber(questId) and data.qlogid then
        localQuests[questId] = self:CreateQuestData(questId, data.qlogid)
      end
    end
  end

  pfQuest.partyQuests[playerName] = localQuests
  RebuildObjectiveLookups()
end

function comms:BroadcastQuestUpdate(questId)
  self:UpdateLocalPlayerQuest(questId)
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
  self:RemoveLocalPlayerQuest(questId)
  if not self:IsEnabled() then return end
  if not self:IsInGroup() then return end

  local numericId = tonumber(questId)
  if not numericId and type(questId) == "string" and _G.pfDB and _G.pfDB.quests and _G.pfDB.quests.loc then
    for qid, qd in pairs(_G.pfDB.quests.loc) do
      if qd.T == questId then
        numericId = qid
        break
      end
    end
  end

  local packet = {
    ver = ADDON_VERSION_STR,
    msgVer = COMM_MESSAGE_VERSION,
    msgId = QC_ID_BROADCAST_QUEST_REMOVE,
    id = numericId or questId,
    questId = numericId or questId,
    [1] = QC_ID_BROADCAST_QUEST_REMOVE,
    [2] = numericId or questId,
  }

  local serialized = Serializer:Serialize(packet, "b89")
  local dist = self:GetGroupDistribution()
  if dist then
    self:SendComm(COMM_PREFIX, serialized, dist)
  end
end

function comms:BroadcastFullQuestList(targetPlayer)
  self:UpdateLocalPlayerQuests()
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
  if not message or not sender then
    return
  end
  local myName = UnitName("player")
  local cleanSender = sender
  if strfind(sender, "-") then
    cleanSender = strsplit("-", sender)
  end
  if cleanSender == myName or sender == myName then
    return
  end
  if not comms:IsEnabled() then
    return
  end

  if prefix == VISIBILITY_PREFIX then
    local success, snapshot
    if type(message) == "table" then
      snapshot = message
      success = true
    else
      success, snapshot = pcall(Serializer.Deserialize, Serializer, message, "1short")
    end
    if success and type(snapshot) == "table" then
      pfQuest.partyVisibility[cleanSender] = snapshot
      if pfQuest.partyQuests[cleanSender] then
        for questId in pairs(pfQuest.partyQuests[cleanSender]) do
          UpdatePartyMapNodes(questId, cleanSender)
        end
      end
    end
    return
  end

  if prefix == COMM_PREFIX then
    local packet
    if type(message) == "table" then
      packet = message
    else
      local success, res = pcall(Serializer.Deserialize, Serializer, message, "b89")
      if success and type(res) == "table" then
        packet = res
      else
        local s2, res2 = pcall(Serializer.Deserialize, Serializer, message, "1short")
        if s2 and type(res2) == "table" then
          packet = res2
        end
      end
    end
    if not packet or type(packet) ~= "table" then
      return
    end

    local msgId = packet.msgId or (type(packet[1]) == "number" and packet[1]) or packet.type or packet.messageId
    if not msgId then return end

    pfQuest.partyQuests[cleanSender] = pfQuest.partyQuests[cleanSender] or {}

    local function ParseObjectiveType(rawTyp)
      if type(rawTyp) == "number" then
        if rawTyp == 1 or rawTyp == stringbyte("m") or rawTyp == stringbyte("M") then
          return "m"
        elseif rawTyp == 2 or rawTyp == stringbyte("o") or rawTyp == stringbyte("O") then
          return "o"
        elseif rawTyp == 3 or rawTyp == stringbyte("i") or rawTyp == stringbyte("I") then
          return "i"
        elseif rawTyp == 4 or rawTyp == stringbyte("e") or rawTyp == stringbyte("E") then
          return "e"
        elseif rawTyp > 31 and rawTyp < 127 then
          return string.lower(stringchar(rawTyp))
        end
        return "m"
      elseif type(rawTyp) == "string" then
        local low = string.lower(rawTyp)
        if low == "monster" or low == "creature" or low == "unit" or low == "m" then
          return "m"
        elseif low == "object" or low == "gameobject" or low == "o" then
          return "o"
        elseif low == "item" or low == "i" then
          return "i"
        elseif low == "event" or low == "log" or low == "e" then
          return "e"
        else
          return strsub(low, 1, 1)
        end
      end
      return "m"
    end

    local function NormalizeObjectives(rawObjectives)
      local normalized = {}
      if rawObjectives then
        for i, obj in pairs(rawObjectives) do
          local typ = ParseObjectiveType(obj.type or obj.typ or obj.Type)
          local id = obj.id or obj.Id or obj.ID
          if id and id == 0 then id = nil end

          local ful = tonumber(obj.fulfilled or obj.ful or obj.Collected or obj.numFulfilled) or 0
          local req = tonumber(obj.required or obj.req or obj.Needed or obj.numRequired) or 1
          local fin = (obj.finished ~= nil and obj.finished)
            or (obj.fin ~= nil and obj.fin)
            or (obj.Finished ~= nil and obj.Finished)
            or (obj.Completed ~= nil and obj.Completed)
            or (ful >= req)

          local text = obj.text or obj.desc or obj.name or obj.Description or obj.Text

          normalized[i] = {
            index = i,
            id = id,
            Id = id,
            type = typ,
            typ = typ,
            fulfilled = ful,
            ful = ful,
            Collected = ful,
            numFulfilled = ful,
            required = req,
            req = req,
            Needed = req,
            numRequired = req,
            finished = fin and true or false,
            fin = fin and true or false,
            Finished = fin and true or false,
            Completed = fin and true or false,
            text = text,
            Description = text,
            Text = text,
          }
        end
      end
      return normalized
    end

    if msgId == QC_ID_BROADCAST_QUEST_UPDATE then
      local q = packet.quest or packet
      local qId = q and (q.id or q.Id or q.questId or (type(packet[2]) == "number" and packet[2]))
      if qId then
        local oldQuest = pfQuest.partyQuests[cleanSender][qId]
        local rawObjs = q.objectives or q.Objectives
        local newObjs = NormalizeObjectives(rawObjs)

        if oldQuest and oldQuest.objectives then
          for idx, nobj in pairs(newObjs) do
            local oobj = oldQuest.objectives[idx]
            if oobj then
              if not nobj.text and oobj.text then nobj.text = oobj.text end
              if not nobj.id and oobj.id then nobj.id = oobj.id end
            end
          end
        end

        local qStatus = q.status or q.Status
        if not qStatus and oldQuest and oldQuest.status then
          local oldSt = type(oldQuest.status) == "string" and string.lower(oldQuest.status) or oldQuest.status
          if oldSt == "c" or oldSt == "complete" or oldSt == "done" or oldSt == 1 then
            local objsComplete = true
            if newObjs and next(newObjs) then
              for _, nobj in pairs(newObjs) do
                if not nobj.finished and (not nobj.fulfilled or not nobj.required or nobj.fulfilled < nobj.required) then
                  objsComplete = false
                  break
                end
              end
            end
            if objsComplete then
              qStatus = oldQuest.status
            end
          else
            qStatus = oldQuest.status
          end
        end

        local isComplete = q.isComplete or q.complete or q.finished
        if isComplete == nil and oldQuest and (oldQuest.isComplete or oldQuest.finished) then
          local objsComplete = true
          if newObjs and next(newObjs) then
            for _, nobj in pairs(newObjs) do
              if not nobj.finished and (not nobj.fulfilled or not nobj.required or nobj.fulfilled < nobj.required) then
                objsComplete = false
                break
              end
            end
          end
          if objsComplete then
            isComplete = oldQuest.isComplete or oldQuest.finished
          end
        end

        pfQuest.partyQuests[cleanSender][qId] = {
          id = qId,
          status = qStatus,
          isComplete = isComplete,
          finished = isComplete,
          objectives = newObjs,
        }
        RebuildObjectiveLookups()
        UpdatePartyMapNodes(qId, cleanSender)
      end

    elseif msgId == QC_ID_BROADCAST_QUEST_REMOVE then
      local rawId = packet.id or packet.questId or packet.Id or (packet.quest and (packet.quest.id or packet.quest.Id)) or packet[2] or packet[1] or (type(packet) == "number" and packet)
      local qId = tonumber(rawId) or rawId
      if not tonumber(qId) and type(qId) == "string" and _G.pfDB and _G.pfDB.quests and _G.pfDB.quests.loc then
        for dbQid, qd in pairs(_G.pfDB.quests.loc) do
          if qd.T == qId then
            qId = dbQid
            break
          end
        end
      end
      if qId then
        local numQId = tonumber(qId)
        pfQuest.partyQuests[cleanSender][qId] = nil
        if numQId then
          pfQuest.partyQuests[cleanSender][numQId] = nil
        end
        if rawId and rawId ~= qId then
          pfQuest.partyQuests[cleanSender][rawId] = nil
          local numRaw = tonumber(rawId)
          if numRaw then
            pfQuest.partyQuests[cleanSender][numRaw] = nil
          end
        end
        RebuildObjectiveLookups()
        comms:DeletePartyQuestNodes(qId, cleanSender)
        if numQId and numQId ~= qId then
          comms:DeletePartyQuestNodes(numQId, cleanSender)
        end
        if rawId and rawId ~= qId then
          comms:DeletePartyQuestNodes(rawId, cleanSender)
        end
      end

    elseif msgId == QC_ID_BROADCAST_FULL_QUESTLIST then
      if packet.rawQuestList then
        -- Prune quests no longer present in sender's quest log
        if pfQuest.partyQuests[cleanSender] then
          for oldQId in pairs(pfQuest.partyQuests[cleanSender]) do
            local numOld = tonumber(oldQId)
            if not packet.rawQuestList[oldQId] and not (numOld and packet.rawQuestList[numOld]) then
              pfQuest.partyQuests[cleanSender][oldQId] = nil
              comms:DeletePartyQuestNodes(oldQId, cleanSender)
            end
          end
        end

        for qId, questData in pairs(packet.rawQuestList) do
          local oldQuest = pfQuest.partyQuests[cleanSender][qId]
          local rawObjs = questData.objectives or questData.Objectives
          local newObjs = NormalizeObjectives(rawObjs)
          if oldQuest and oldQuest.objectives then
            for idx, nobj in pairs(newObjs) do
              local oobj = oldQuest.objectives[idx]
              if oobj then
                if not nobj.text and oobj.text then nobj.text = oobj.text end
                if not nobj.id and oobj.id then nobj.id = oobj.id end
              end
            end
          end
          pfQuest.partyQuests[cleanSender][qId] = {
            id = qId,
            status = questData.status or questData.Status or (oldQuest and oldQuest.status),
            isComplete = questData.isComplete or questData.complete or questData.finished or (oldQuest and (oldQuest.isComplete or oldQuest.finished)),
            finished = questData.isComplete or questData.complete or questData.finished or (oldQuest and (oldQuest.isComplete or oldQuest.finished)),
            objectives = newObjs,
          }
          UpdatePartyMapNodes(qId, cleanSender)
        end
        RebuildObjectiveLookups()
      end

    elseif msgId == QC_ID_REQUEST_FULL_QUESTLIST then
      self:BroadcastFullQuestList(cleanSender)
      self:SendVisibilitySnapshot(cleanSender)

    elseif msgId == QC_ID_BROADCAST_FULL_QUESTLISTV2 then
      -- Flat array v2 packet
      local block = packet[1]
      local pfDB = _G.pfDB
      if block and type(block) == "table" then
        local failedQuests = {}
        if packet[2] then
          for _, qId in pairs(packet[2]) do
            failedQuests[qId] = true
          end
        end

        local presentQuests = {}
        local count = block[1] or 0
        local offset = 2
        for _ = 1, count do
          local qId = block[offset]
          presentQuests[qId] = true
          local objCount = block[offset + 1] or 0
          offset = offset + 2
          local objectives = {}
          local oldQuest = pfQuest.partyQuests[cleanSender][qId]
          for oIdx = 1, objCount do
            local rawId = block[offset]
            local typChar = ParseObjectiveType(block[offset + 1])
            local ful = tonumber(block[offset + 2]) or 0
            local req = tonumber(block[offset + 3]) or 1

            local oldObj = oldQuest and oldQuest.objectives and oldQuest.objectives[oIdx]
            local text = oldObj and oldObj.text

            if not text and rawId and rawId > 0 and pfDB then
              if typChar == "m" and pfDB["units"] and pfDB["units"]["loc"] then
                text = pfDB["units"]["loc"][rawId]
              elseif typChar == "o" and pfDB["objects"] and pfDB["objects"]["loc"] then
                text = pfDB["objects"]["loc"][rawId]
              elseif typChar == "i" and pfDB["items"] and pfDB["items"]["loc"] then
                text = pfDB["items"]["loc"][rawId]
              end
            end

            objectives[oIdx] = {
              index = oIdx,
              id = rawId ~= 0 and rawId or (oldObj and oldObj.id),
              Id = rawId ~= 0 and rawId or (oldObj and oldObj.id),
              type = typChar,
              typ = typChar,
              fulfilled = ful,
              ful = ful,
              Collected = ful,
              numFulfilled = ful,
              required = req,
              req = req,
              Needed = req,
              numRequired = req,
              finished = (ful >= req),
              fin = (ful >= req),
              Finished = (ful >= req),
              Completed = (ful >= req),
              text = text,
              Description = text,
              Text = text,
            }
            offset = offset + 4
          end
          pfQuest.partyQuests[cleanSender][qId] = {
            id = qId,
            status = failedQuests[qId] and "F" or (oldQuest and oldQuest.status),
            objectives = objectives,
          }
          UpdatePartyMapNodes(qId, cleanSender)
        end

        RebuildObjectiveLookups()
      end

    elseif msgId == QC_ID_BROADCAST_QUEST_UPDATEV2 then
      local block = packet[1]
      local pfDB = _G.pfDB
      if block and type(block) == "table" then
        local qId = block[1]
        local objCount = block[2] or 0
        local offset = 3
        local objectives = {}
        local oldQuest = pfQuest.partyQuests[cleanSender][qId]
        for oIdx = 1, objCount do
          local rawId = block[offset]
          local typChar = ParseObjectiveType(block[offset + 1])
          local ful = tonumber(block[offset + 2]) or 0
          local req = tonumber(block[offset + 3]) or 1

          local oldObj = oldQuest and oldQuest.objectives and oldQuest.objectives[oIdx]
          local text = oldObj and oldObj.text

          if not text and rawId and rawId > 0 and pfDB then
            if typChar == "m" and pfDB["units"] and pfDB["units"]["loc"] then
              text = pfDB["units"]["loc"][rawId]
            elseif typChar == "o" and pfDB["objects"] and pfDB["objects"]["loc"] then
              text = pfDB["objects"]["loc"][rawId]
            elseif typChar == "i" and pfDB["items"] and pfDB["items"]["loc"] then
              text = pfDB["items"]["loc"][rawId]
            end
          end

          objectives[oIdx] = {
            index = oIdx,
            id = rawId ~= 0 and rawId or (oldObj and oldObj.id),
            Id = rawId ~= 0 and rawId or (oldObj and oldObj.id),
            type = typChar,
            typ = typChar,
            fulfilled = ful,
            ful = ful,
            Collected = ful,
            numFulfilled = ful,
            required = req,
            req = req,
            Needed = req,
            numRequired = req,
            finished = (ful >= req),
            fin = (ful >= req),
            Finished = (ful >= req),
            Completed = (ful >= req),
            text = text,
            Description = text,
            Text = text,
          }
          offset = offset + 4
        end
        pfQuest.partyQuests[cleanSender][qId] = {
          id = qId,
          status = oldQuest and oldQuest.status,
          objectives = objectives,
        }
        RebuildObjectiveLookups()
        UpdatePartyMapNodes(qId, cleanSender)
      end

    elseif msgId == QC_ID_YELL_PROGRESS then
      local qId = packet.questId or packet.id or (packet.quest and (packet.quest.id or packet.quest.Id))
      if qId then
        local qObj = pfQuest.partyQuests[cleanSender][qId]
        if not qObj then
          qObj = { id = qId, objectives = {} }
          pfQuest.partyQuests[cleanSender][qId] = qObj
        end
        local oIdx = packet.objIndex or packet.index or packet.idx or 1
        local oldObj = qObj.objectives and qObj.objectives[oIdx]
        local ful = tonumber(packet.fulfilled or packet.ful or packet.cur or packet.Collected or packet.numFulfilled) or 0
        local req = tonumber(packet.required or packet.req or packet.max or packet.Needed or packet.numRequired) or 1
        local fin = (ful >= req) or packet.finished or packet.fin or packet.Finished or packet.Completed
        local text = packet.text or packet.desc or packet.Description or (oldObj and oldObj.text)
        local rawId = packet.objId or packet.id or (oldObj and oldObj.id)
        local typ = ParseObjectiveType(packet.type or packet.typ or packet.Type or (oldObj and oldObj.type))

        qObj.objectives[oIdx] = {
          index = oIdx,
          id = rawId,
          Id = rawId,
          type = typ,
          typ = typ,
          fulfilled = ful,
          ful = ful,
          Collected = ful,
          numFulfilled = ful,
          required = req,
          req = req,
          Needed = req,
          numRequired = req,
          finished = fin and true or false,
          fin = fin and true or false,
          Finished = fin and true or false,
          Completed = fin and true or false,
          text = text,
          Description = text,
          Text = text,
        }
        RebuildObjectiveLookups()
        UpdatePartyMapNodes(qId, cleanSender)
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

function comms:AnnounceQuest(questId, title, isTurnIn)
  if pfQuest_config and (pfQuest_config["experimental"] ~= "1" or pfQuest_config["questannounce"] == "0") then
    return
  end
  if not self:IsInGroup() then
    return
  end

  local dist = self:GetGroupDistribution()
  if not dist then return end

  local numericId = tonumber(questId) or 0
  local level = 0
  local qTitle = title
  local pfDB = _G.pfDB
  if pfDB and pfDB.quests then
    if pfDB.quests.loc and pfDB.quests.loc[numericId] then
      qTitle = pfDB.quests.loc[numericId].T
    end
    if pfDB.quests.data and pfDB.quests.data[numericId] then
      level = pfDB.quests.data[numericId].lvl or 0
    end
  end
  if not qTitle and pfQuest.questlog and pfQuest.questlog[questId] then
    qTitle = pfQuest.questlog[questId].title
  end
  qTitle = qTitle or (type(questId) == "string" and questId) or ("Quest " .. tostring(questId))

  local questLink
  if _G.GetQuestLink and pfQuest.questlog and pfQuest.questlog[questId] and pfQuest.questlog[questId].qlogid then
    questLink = _G.GetQuestLink(pfQuest.questlog[questId].qlogid)
  end
  if not questLink and numericId > 0 then
    questLink = string.format("|cffffff00|Hquest:%d:%d|h[%s]|h|r", numericId, level, qTitle)
  else
    questLink = questLink or ("[" .. qTitle .. "]")
  end

  local action = isTurnIn and "Quest Completed" or "Quest Completed"
  local msg = "{rt1} pfQuest: " .. action .. ": " .. questLink .. "!"

  SendChatMessage(msg, dist)
end

function comms:GetPlayerColor(playerName)
  if not playerName then return "|cff33ffcc" end
  if playerName == UnitName("player") then
    local _, class = UnitClass("player")
    if class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class] then
      local c = RAID_CLASS_COLORS[class]
      return string.format("|cff%02x%02x%02x", floor(c.r * 255), floor(c.g * 255), floor(c.b * 255))
    end
    return "|cff33ffcc"
  end

  local numRaid = GetNumRaidMembers()
  if numRaid > 0 then
    for i = 1, numRaid do
      if UnitName("raid" .. i) == playerName then
        local _, class = UnitClass("raid" .. i)
        if class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class] then
          local c = RAID_CLASS_COLORS[class]
          return string.format("|cff%02x%02x%02x", floor(c.r * 255), floor(c.g * 255), floor(c.b * 255))
        end
        break
      end
    end
  else
    local numParty = GetNumPartyMembers()
    for i = 1, numParty do
      if UnitName("party" .. i) == playerName then
        local _, class = UnitClass("party" .. i)
        if class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class] then
          local c = RAID_CLASS_COLORS[class]
          return string.format("|cff%02x%02x%02x", floor(c.r * 255), floor(c.g * 255), floor(c.b * 255))
        end
        break
      end
    end
  end
  return "|cff33ffcc"
end

function comms:PrunePartyMembers()
  local active = {}
  local myName = UnitName("player")
  if myName then active[myName] = true end
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
  local now = GetTime()
  for k, spool in pairs(multipartSpool) do
    local sender = string.match(k, "\t([^\t]+)$")
    if (sender and not active[sender]) or (type(spool) == "table" and spool.time and (now - spool.time > 15)) then
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
local function TooltipHasQuest(tip, questTitle)
  if not tip or not tip.NumLines or not questTitle then return false end
  local tipName = tip.GetName and tip:GetName()
  for i = 1, tip:NumLines() do
    local line = tipName and _G[tipName .. "TextLeft" .. i]
    local txt = line and line.GetText and line:GetText()
    if txt and strfind(txt, questTitle, 1, true) then
      return true
    end
  end
  return false
end

function comms:AddPartyTooltipLines(questTitle, tooltip, meta)
  if not self:IsEnabled() or pfQuest_config["showpartytooltips"] == "0" then
    return
  end
  if not self:IsInGroup() then
    return
  end
  tooltip = tooltip or GameTooltip
  local pfDB = _G.pfDB
  local localPlayer = UnitName("player")

  if localPlayer and (not pfQuest.partyQuests or not pfQuest.partyQuests[localPlayer]) then
    self:UpdateLocalPlayerQuests()
  end

  local playerNames = {}
  for playerName in pairs(pfQuest.partyQuests) do
    table.insert(playerNames, playerName)
  end
  table.sort(playerNames, function(a, b)
    if a == localPlayer then return true end
    if b == localPlayer then return false end
    return a < b
  end)

  local filterName = meta and (meta["spawn"] or (meta["item"] and meta["item"][1]))
  local shownPlayerLines = {}

  for _, playerName in ipairs(playerNames) do
    local quests = pfQuest.partyQuests[playerName]
    if quests then
      for questId, questData in pairs(quests) do
        local qData = pfDB and pfDB["quests"] and pfDB["quests"]["loc"] and pfDB["quests"]["loc"][questId]
        local title = qData and qData.T or ("Quest " .. questId)
        if title == questTitle and questData.objectives then
          local pColor = self:GetPlayerColor(playerName)
          local numObjs = 0
          for _ in pairs(questData.objectives) do numObjs = numObjs + 1 end

          local hasMatch = false
          if filterName then
            for _, obj in pairs(questData.objectives) do
              if obj.text and (obj.text == filterName or strfind(obj.text, filterName, 1, true) or strfind(filterName, obj.text, 1, true)) then
                hasMatch = true
                break
              end
            end
          end

          for _, obj in pairs(questData.objectives) do
            local matchesFilter = (not filterName) or (not hasMatch) or (obj.text and (obj.text == filterName or strfind(obj.text, filterName, 1, true) or strfind(filterName, obj.text, 1, true)))
            if matchesFilter then
              local cur = obj.fulfilled or 0
              local req = obj.required or 1
              local status = obj.finished and (" |cff00ff00(" .. (pfQuest_Loc["Complete"] or "Complete") .. ")|r") or ""
              local objLabel = ""
              if numObjs > 1 and not hasMatch then
                if obj.text and obj.text ~= "" then
                  objLabel = " (" .. obj.text .. ")"
                elseif obj.index then
                  objLabel = " (#" .. obj.index .. ")"
                end
              end
              local lineKey = playerName .. ":" .. tostring(obj.index or obj.Id or obj.text or "")
              if not shownPlayerLines[lineKey] then
                shownPlayerLines[lineKey] = true
                tooltip:AddLine("  " .. pColor .. playerName .. "|r" .. objLabel .. ": " .. cur .. "/" .. req .. status, 0.8, 0.8, 0.8)
              end
            end
          end
        end
      end
    end
  end
end

function comms:ShowWorldTooltip(name, tooltip)
  if not self:IsEnabled() or pfQuest_config["showpartytooltips"] == "0" then
    return
  end
  if not self:IsInGroup() then
    return
  end
  if not name or name == "__NONE__" then return end
  tooltip = tooltip or GameTooltip

  if tooltip._pfQuestieTooltipName == name then
    return
  end

  local myName = UnitName("player")
  if myName and (not pfQuest.partyQuests or not pfQuest.partyQuests[myName]) then
    self:UpdateLocalPlayerQuests()
  end

  local entries = {}
  local seen = {}
  local function collect(tbl)
    if not tbl then return end
    for _, e in ipairs(tbl) do
      local k = e.playerName .. ":" .. e.questId .. ":" .. tostring(e.objIndex)
      if not seen[k] then
        seen[k] = true
        tinsert(entries, e)
      end
    end
  end

  collect(partyObjectivesByMob[name])
  collect(partyObjectivesByObject[name])
  collect(partyObjectivesByItem[name])

  if #entries == 0 then return end

  tooltip._pfQuestieTooltipName = name

  table.sort(entries, function(a, b)
    if a.questTitle ~= b.questTitle then
      return a.questTitle < b.questTitle
    end
    local aIsMe = (a.playerName == myName)
    local bIsMe = (b.playerName == myName)
    if aIsMe and not bIsMe then return true end
    if not aIsMe and bIsMe then return false end
    if a.playerName ~= b.playerName then
      return a.playerName < b.playerName
    end
    return (a.objIndex or 0) < (b.objIndex or 0)
  end)

  local alreadyInTooltip = {}
  for _, entry in ipairs(entries) do
    if alreadyInTooltip[entry.questTitle] == nil then
      alreadyInTooltip[entry.questTitle] = TooltipHasQuest(tooltip, entry.questTitle)
    end
  end

  local shownQuests = {}
  local shownEntries = {}
  local anyAdded = false
  for _, entry in ipairs(entries) do
    if not alreadyInTooltip[entry.questTitle] then
      if not shownQuests[entry.questTitle] then
        shownQuests[entry.questTitle] = true
        tooltip:AddLine("|cff555555[|cff33ffcc!|cff555555]|r " .. entry.questTitle, 1, 1, 0.7)
        anyAdded = true
      end
      local pColor = self:GetPlayerColor(entry.playerName)
      local status = entry.finished and (" |cff00ff00(" .. (pfQuest_Loc["Complete"] or "Complete") .. ")|r") or ""
      local objDesc = ""
      if entry.text and entry.text ~= "" and entry.text ~= name then
        objDesc = " (" .. entry.text .. ")"
      end
      local entryKey = entry.questTitle .. ":" .. entry.playerName .. ":" .. objDesc
      if not shownEntries[entryKey] then
        shownEntries[entryKey] = true
        tooltip:AddLine("  " .. pColor .. entry.playerName .. "|r" .. objDesc .. ": " .. entry.fulfilled .. "/" .. entry.required .. status, 0.8, 0.8, 0.8)
        anyAdded = true
      end
    end
  end
  if anyAdded and not self.inTooltipShow then
    self.inTooltipShow = true
    tooltip:Show()
    self.inTooltipShow = nil
  end
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
        comms:UpdateLocalPlayerQuests()
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
      comms:UpdateLocalPlayerQuests()
    end

  elseif event == "PLAYER_ENTERING_WORLD" then
    wasInGroup = comms:IsInGroup()
    if wasInGroup and comms:IsEnabled() then
      comms:UpdateLocalPlayerQuests()
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

-- Hook Item, Unit, and GameObject Tooltips for Party Quest Objectives
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
  tip:HookScript("OnShow", function(self)
    if comms.inTooltipShow then
      return
    end
    if not comms:IsEnabled() or pfQuest_config["showpartytooltips"] == "0" then
      return
    end
    if (self.GetUnit and self:GetUnit()) or (self.GetItem and self:GetItem()) then
      return
    end
    local owner = self.GetOwner and self:GetOwner()
    if not owner or owner == UIParent or owner == WorldFrame then
      return
    end
    local tipName = self:GetName()
    local text = tipName and _G[tipName .. "TextLeft1"] and _G[tipName .. "TextLeft1"]:GetText()
    if text and text ~= "" and text ~= "__NONE__" then
      local clean = string.gsub(text, "|c%x%x%x%x%x%x%x%x", "")
      clean = string.gsub(clean, "|r", "")
      comms:ShowWorldTooltip(clean, self)
    end
  end)
end

if GameTooltip then HookTooltip(GameTooltip) end
if ItemRefTooltip then HookTooltip(ItemRefTooltip) end

-- Export module
pfQuest.questieComms = comms
