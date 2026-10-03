--[[
================================================================================
  SPEED MASTER LEDS - grandMA3 plugin                                   v1.0.0
================================================================================
  Flashes the key LEDs and the encoder LEDs (knob or fader LEDs) of your
  executors in time with a speed master's BPM.

  Run it and press Start. With Executors = auto it finds the executors on the
  current page that hold the speed master (Speed Master 1 by default) and
  flashes their LEDs, following page changes. "Learn keys" lets you tap the
  keys to flash instead.

  Run it again to stop, or call it from a macro or key:
    Plugin "Speed Master LEDs" "toggle"    start / stop with the saved settings
    Plugin "Speed Master LEDs" "start"
    Plugin "Speed Master LEDs" "stop"
    Plugin "Speed Master LEDs" "check"     show the BPM and hardware it sees

  It drives the LEDs with SetLED(). MA publishes the LED layout only for the
  Master Module (MM) and the two fader modules (MFE / MFX) of the full-size
  (the light should report the same modules), so only those modules are
  touched. onPC, compact consoles and wings aren't supported.

  Edit SETTINGS below to taste.
================================================================================
]]

local pluginName    = select(1, ...)
local componentName = select(2, ...)
local signalTable   = select(3, ...)
local myHandle      = select(4, ...)

--------------------------------------------------------------------------------
-- SETTINGS
--------------------------------------------------------------------------------
local SETTINGS = {
  -- How often the flash loop wakes up, in seconds.
  frameTime = 0.02,

  -- Resend the LEDs at least this often, in seconds. The console takes the
  -- LEDs back about 2 seconds after the last SetLED.
  refreshTime = 0.2,

  -- Key LED brightness at the peak of a flash (0 - 100).
  keyBrightness = 100,

  -- A BPM change after this many seconds without changes counts as a tap
  -- (tap tempo): the next flash starts at that moment. Faster changes, such as
  -- riding the fader, keep the flashes running smoothly instead.
  tapGap = 0.35,

  -- With Executors = auto, look for the speed master on the page this often.
  rescanTime = 1.0,

  -- Learn keys: stop listening this many seconds after the last tap, or after
  -- learnMaxWait seconds if nothing is tapped.
  learnIdle = 5,
  learnMaxWait = 20,

  -- If the plugin can't tell which module is which, set it here by module
  -- name (the names are listed by "Check BPM and hardware"), for example:
  --   moduleTypes = { ["UsbDeviceMA3 2"] = "MM", ["UsbDeviceMA3 3"] = "MFE" },
  -- MM = master module, MFE = fader module with encoders,
  -- MFX = fader module with crossfader.
  moduleTypes = {},

  -- Remember the dialog values (stored as user variables SML_*).
  rememberValues = true,

  -- Size of the table handed to SetLED (the manual asks for 1024).
  ledTableSize = 1024,
}

local TITLE = "Speed Master LEDs"

--------------------------------------------------------------------------------
-- HARDWARE MAP
-- Index numbers from the grandMA3 manual, Lua topics SetLED ("Hardware Modules
-- LED Table") and GetButton ("Hardware Modules Button Table"). Only LEDs in
-- this map are ever written: setting an index with no LED behind it can crash
-- and reboot the module.
--
--   keys      executor -> LED of its key
--   rgb       executor -> { red, green, blue } LEDs of its knob (191-298 on
--             the master module, 3xx and 4xx on the fader modules) or of its
--             fader (2xx)
--   buttons   executor -> GetButton index of its key
--   touch     executor -> GetButton index of its touch-sensitive fader
--   encoders  the 5 dual encoders under the screen, { red, green, blue } for
--             inner 1, outer 1, inner 2, outer 2, ...
--
-- On the fader modules the executors are the module's own 101-115, 201-215,
-- 301-315 and 401-415.
--------------------------------------------------------------------------------
local FADER_BUTTONS = {
  [101] = 47, [102] = 48, [103] = 49, [104] = 50, [105] = 33, [106] = 34, [107] = 35, [108] = 3,
  [109] = 38, [110] = 4, [111] = 46, [112] = 26, [113] = 25, [114] = 24, [115] = 23, [201] = 42,
  [202] = 41, [203] = 40, [204] = 39, [205] = 29, [206] = 28, [207] = 27, [208] = 19, [209] = 17,
  [210] = 18, [211] = 10, [212] = 11, [213] = 12, [214] = 13, [215] = 14, [301] = 227, [302] = 225,
  [303] = 238, [304] = 241, [305] = 242, [306] = 163, [307] = 161, [308] = 174, [309] = 177, [310] = 178,
  [311] = 99, [312] = 97, [313] = 110, [314] = 113, [315] = 114, [401] = 203, [402] = 204, [403] = 211,
  [404] = 210, [405] = 209, [406] = 139, [407] = 140, [408] = 147, [409] = 146, [410] = 145, [411] = 75,
  [412] = 76, [413] = 83, [414] = 82, [415] = 81,
}

local FADER_TOUCH = {
  [201] = 249, [202] = 250, [203] = 187, [204] = 188, [205] = 189, [206] = 190, [207] = 191, [208] = 192,
  [209] = 121, [210] = 122, [211] = 59, [212] = 60, [213] = 61, [214] = 62, [215] = 63,
}

local HW = {
  MM = {
    keys = {
      [191] = 139, [192] = 122, [193] = 123, [194] = 124, [195] = 78, [196] = 79, [197] = 85, [198] = 94,
      [291] = 135, [292] = 136, [293] = 137, [294] = 138, [295] = 72, [296] = 73, [297] = 95, [298] = 87,
    },
    rgb = {
      [291] = { 108, 113, 125 }, [292] = { 109, 114, 126 }, [293] = { 104, 115, 127 }, [294] = { 107, 116, 128 },
      [295] = { 75, 80, 90 }, [296] = { 76, 81, 91 }, [297] = { 71, 82, 92 }, [298] = { 74, 83, 93 },
    },
    buttons = {
      [191] = 242, [192] = 225, [193] = 226, [194] = 227, [195] = 146, [196] = 147, [197] = 155, [198] = 169,
      [291] = 238, [292] = 239, [293] = 240, [294] = 241, [295] = 139, [296] = 140, [297] = 170, [298] = 157,
    },
    touch = {},
    encoders = {
      { 7, 10, 22 }, { 8, 11, 23 }, { 3, 12, 24 }, { 6, 13, 25 }, { 34, 14, 26 },
      { 2, 15, 27 }, { 1, 16, 28 }, { 20, 17, 29 }, { 33, 18, 30 }, { 32, 19, 31 },
    },
  },
  MFE = {
    keys = {
      [101] = 27, [102] = 28, [103] = 29, [104] = 30, [105] = 18, [106] = 19, [107] = 20, [108] = 1,
      [109] = 21, [110] = 2, [111] = 26, [112] = 14, [113] = 13, [114] = 12, [115] = 11, [201] = 25,
      [202] = 24, [203] = 23, [204] = 22, [205] = 17, [206] = 16, [207] = 15, [208] = 10, [209] = 8,
      [210] = 9, [211] = 3, [212] = 4, [213] = 5, [214] = 6, [215] = 7, [301] = 134, [302] = 132,
      [303] = 145, [304] = 148, [305] = 149, [306] = 94, [307] = 92, [308] = 105, [309] = 108, [310] = 109,
      [311] = 54, [312] = 52, [313] = 65, [314] = 68, [315] = 69, [401] = 114, [402] = 115, [403] = 121,
      [404] = 120, [405] = 119, [406] = 74, [407] = 75, [408] = 81, [409] = 80, [410] = 79, [411] = 34,
      [412] = 35, [413] = 41, [414] = 40, [415] = 39,
    },
    rgb = {
      [201] = { 161, 162, 163 }, [202] = { 164, 165, 166 }, [203] = { 167, 168, 169 }, [204] = { 170, 171, 172 },
      [205] = { 173, 174, 175 }, [206] = { 176, 177, 178 }, [207] = { 179, 180, 181 }, [208] = { 182, 183, 184 },
      [209] = { 185, 186, 187 }, [210] = { 188, 189, 190 }, [211] = { 191, 192, 193 }, [212] = { 194, 195, 196 },
      [213] = { 197, 198, 199 }, [214] = { 200, 201, 202 }, [215] = { 203, 204, 205 },
      [301] = { 112, 127, 140 }, [302] = { 111, 128, 141 }, [303] = { 133, 129, 142 }, [304] = { 147, 130, 143 },
      [305] = { 146, 131, 144 }, [306] = { 72, 87, 100 }, [307] = { 71, 88, 101 }, [308] = { 93, 89, 102 },
      [309] = { 107, 90, 103 }, [310] = { 106, 91, 104 }, [311] = { 32, 47, 60 }, [312] = { 31, 48, 61 },
      [313] = { 53, 49, 62 }, [314] = { 67, 50, 63 }, [315] = { 66, 51, 64 },
      [401] = { 117, 122, 135 }, [402] = { 118, 123, 136 }, [403] = { 113, 124, 137 }, [404] = { 116, 125, 138 },
      [405] = { 150, 126, 139 }, [406] = { 77, 82, 95 }, [407] = { 78, 83, 96 }, [408] = { 73, 84, 97 },
      [409] = { 76, 85, 98 }, [410] = { 110, 86, 99 }, [411] = { 37, 42, 55 }, [412] = { 38, 43, 56 },
      [413] = { 33, 44, 57 }, [414] = { 36, 45, 58 }, [415] = { 70, 46, 59 },
    },
    buttons = FADER_BUTTONS,
    touch = FADER_TOUCH,
  },
  MFX = {
    keys = {
      [101] = 40, [102] = 41, [103] = 42, [104] = 43, [105] = 26, [106] = 27, [107] = 28, [108] = 1,
      [109] = 31, [110] = 2, [111] = 39, [112] = 19, [113] = 18, [114] = 17, [115] = 16, [201] = 35,
      [202] = 34, [203] = 33, [204] = 32, [205] = 22, [206] = 21, [207] = 20, [208] = 12, [209] = 10,
      [210] = 11, [211] = 3, [212] = 4, [213] = 5, [214] = 6, [215] = 7, [301] = 151, [302] = 149,
      [303] = 162, [304] = 165, [305] = 166, [306] = 111, [307] = 109, [308] = 122, [309] = 125, [310] = 126,
      [311] = 71, [312] = 69, [313] = 82, [314] = 85, [315] = 86, [401] = 131, [402] = 132, [403] = 138,
      [404] = 137, [405] = 136, [406] = 91, [407] = 92, [408] = 98, [409] = 97, [410] = 96, [411] = 51,
      [412] = 52, [413] = 58, [414] = 57, [415] = 56,
    },
    rgb = {
      [201] = { 168, 169, 170 }, [202] = { 171, 172, 173 }, [203] = { 174, 175, 176 }, [204] = { 177, 178, 179 },
      [205] = { 180, 181, 182 }, [206] = { 183, 184, 185 }, [207] = { 186, 187, 188 }, [208] = { 189, 190, 191 },
      [209] = { 192, 193, 194 }, [210] = { 195, 196, 197 }, [211] = { 198, 199, 200 }, [212] = { 201, 202, 203 },
      [213] = { 204, 205, 206 }, [214] = { 207, 208, 209 }, [215] = { 210, 211, 212 },
      [301] = { 129, 144, 157 }, [302] = { 128, 145, 158 }, [303] = { 150, 146, 159 }, [304] = { 164, 147, 160 },
      [305] = { 163, 148, 161 }, [306] = { 89, 104, 117 }, [307] = { 88, 105, 118 }, [308] = { 110, 106, 119 },
      [309] = { 124, 107, 120 }, [310] = { 123, 108, 121 }, [311] = { 49, 64, 77 }, [312] = { 48, 65, 78 },
      [313] = { 70, 66, 79 }, [314] = { 84, 67, 80 }, [315] = { 83, 68, 81 },
      [401] = { 134, 139, 152 }, [402] = { 135, 140, 153 }, [403] = { 130, 141, 154 }, [404] = { 133, 142, 155 },
      [405] = { 167, 143, 156 }, [406] = { 94, 99, 112 }, [407] = { 95, 100, 113 }, [408] = { 90, 101, 114 },
      [409] = { 93, 102, 115 }, [410] = { 127, 103, 116 }, [411] = { 54, 59, 72 }, [412] = { 55, 60, 73 },
      [413] = { 50, 61, 74 }, [414] = { 53, 62, 75 }, [415] = { 87, 63, 76 },
    },
    buttons = FADER_BUTTONS,
    touch = FADER_TOUCH,
  },
}
-- The manual lists MFX LED 88 as "Executor 307 Fader" without a colour. It is
-- the only LED of that knob not otherwise listed, so it is used as red above.

local MODULE_INFO = {
  MM  = { name = "Master Module (MM)", product = 46531,
          patterns = { "%(MM%)", "Master Module", "Wing%-MM" } },
  MFE = { name = "Fader Module Encoder (MFE)", product = 46533,
          patterns = { "%(MFE%)", "Fader Module Encoder", "Wing%-MFE" } },
  MFX = { name = "Fader Module Crossfader (MFX)", product = 46532,
          patterns = { "%(MFX%)", "Fader Module Crossfader", "Wing%-MFX" } },
}

-- Module names on a grandMA3 full-size, from the GetButton topic (2.2 and
-- later; the 2.1 manual names them differently). Only used when a module
-- doesn't say what it is.
local FULLSIZE_NAMES = { ["UsbDeviceMA3 2"] = "MM", ["UsbDeviceMA3 3"] = "MFE", ["UsbDeviceMA3 4"] = "MFX" }

-- LEDs 1-140 are ordinary key and knob LEDs on all three modules. A module
-- whose type is only guessed from its name gets just these, so a wrong guess
-- lights the wrong LED but can't hit a missing LED or a screen backlight.
local GUESSED_MAX = 140

-- Every LED index the plugin may write, per module type.
local ALLOWED = {}
for t, hw in pairs(HW) do
  local set = {}
  for _, i in pairs(hw.keys) do set[i] = true end
  for _, c in pairs(hw.rgb) do for _, i in ipairs(c) do set[i] = true end end
  for _, c in ipairs(hw.encoders or {}) do for _, i in ipairs(c) do set[i] = true end end
  ALLOWED[t] = set
end

-- Executor numbers the auto mode looks at on the current page.
local SCAN_EXECS = {}
for row = 1, 4 do
  for col = 1, 30 do SCAN_EXECS[#SCAN_EXECS + 1] = row * 100 + col end
end
for no = 191, 198 do SCAN_EXECS[#SCAN_EXECS + 1] = no end
for no = 291, 298 do SCAN_EXECS[#SCAN_EXECS + 1] = no end

local COLORS = {
  white = { 255, 255, 255 }, red = { 255, 0, 0 }, orange = { 255, 90, 0 }, amber = { 255, 150, 0 },
  yellow = { 255, 220, 0 }, green = { 0, 255, 0 }, cyan = { 0, 255, 255 }, blue = { 0, 0, 255 },
  purple = { 140, 0, 255 }, magenta = { 255, 0, 255 }, pink = { 255, 60, 150 },
}

-- Speed master fader position (0-100) to BPM, as measured on grandMA3 2.x.
-- Only used to add decimals to the BPM shown on the master.
local CURVE_MAX_BPM, CURVE_EXPONENT = 225, 1.90689062

--------------------------------------------------------------------------------
-- PURE HELPERS (no console calls)
--------------------------------------------------------------------------------
local P = {}

function P.trim(s)
  return (tostring(s == nil and "" or s):gsub("^%s+", ""):gsub("%s+$", ""))
end

function P.toBool(v)
  if type(v) == "boolean" then return v end
  if type(v) == "number" then return v ~= 0 end
  local s = P.trim(v):lower()
  return s == "1" or s == "true" or s == "yes" or s == "on"
end

function P.toInt(s, default)
  local n = tonumber(P.trim(s))
  if not n or n ~= n then return default end
  return math.floor(n + 0.5)
end

function P.round(x)
  return math.floor(x + 0.5)
end

function P.clamp(x, lo, hi)
  if x < lo then return lo end
  if x > hi then return hi end
  return x
end

function P.isMMExec(no)
  return (no >= 191 and no <= 198) or (no >= 291 and no <= 298)
end

-- Executor number -> the fader module's own number (101-415), and whether it
-- is in the second section (x16-x30). nil if it isn't a fader executor.
function P.faderLocal(no)
  local row, col = math.floor(no / 100), no % 100
  if row < 1 or row > 4 or col < 1 or col > 30 then return nil end
  return row * 100 + (col - 1) % 15 + 1, col > 15
end

-- Flashes per beat: "1", "2", "0.5", "1/2".
function P.parseRate(text)
  local s = P.trim(text):gsub(",", ".")
  local a, b = s:match("^(%d+%.?%d*)%s*/%s*(%d+%.?%d*)$")
  local v
  if a then v = tonumber(a) / tonumber(b) else v = tonumber(s) end
  if not v or v ~= v or v <= 0 or v > 16 then
    return nil, "Flashes per beat: use a number like 1, 2, 4 or 1/2 (up to 16)."
  end
  return v
end

-- Colour name, "r,g,b" (0-255) or "#rrggbb".
function P.parseColor(text)
  local s = P.trim(text):lower()
  if COLORS[s] then return { COLORS[s][1], COLORS[s][2], COLORS[s][3] } end
  local hex = s:match("^#?(%x%x%x%x%x%x)$")
  if hex then
    return { tonumber(hex:sub(1, 2), 16), tonumber(hex:sub(3, 4), 16), tonumber(hex:sub(5, 6), 16) }
  end
  local r, g, b = s:match("^(%d+)%s*[,/ ]%s*(%d+)%s*[,/ ]%s*(%d+)$")
  if r then
    r, g, b = tonumber(r), tonumber(g), tonumber(b)
    if r <= 255 and g <= 255 and b <= 255 then return { r, g, b } end
  end
  return nil, "Colour: use White, Red, Orange, Amber, Yellow, Green, Cyan, Blue, Purple, Magenta, Pink, "
    .. "or numbers like 255,0,0."
end

local function execError(tok)
  return "Executors: '" .. tok .. "' has no LEDs I can drive. Use the X-key executors "
    .. "191-198 / 291-298, or 101-415 on a fader module (MFE:401)."
end

-- "auto", "291, 293-295", "291 thru 294", "MFE:401", "MFX:201-205".
-- Returns { auto = bool, list = { { mod = "MM"|"MFE"|"MFX"|nil, exec = n } } }.
function P.parseExecs(text)
  local s = P.trim(text):lower()
  if s == "" then return nil, "Executors: type auto, executor numbers, or use Learn keys." end
  s = s:gsub("%s+thru%s+", "-"):gsub("%s*%-%s*", "-"):gsub("%s*:%s*", ":")
  local out = { auto = false, list = {} }
  for tok in s:gmatch("[^%s,;+]+") do
    if tok == "auto" then
      out.auto = true
    else
      local mod, rest = tok:match("^(%a+):(.+)$")
      if mod then
        mod = mod:upper()
        if not HW[mod] then return nil, "Executors: '" .. mod .. "' isn't a module. Use MM, MFE or MFX." end
      else
        rest = tok
      end
      local a, b = rest:match("^(%d+)%-(%d+)$")
      if not a then a = rest:match("^(%d+)$"); b = a end
      if not a then return nil, "Executors: can't read '" .. tok .. "'." end
      a, b = tonumber(a), tonumber(b)
      if math.abs(b - a) > 60 then return nil, "Executors: '" .. tok .. "' is too long a range." end
      for no = a, b, (a <= b) and 1 or -1 do
        local ok
        if mod == "MM" then
          ok = P.isMMExec(no)
        elseif mod then
          local loc, upper = P.faderLocal(no)
          ok = loc ~= nil and not upper
        else
          ok = P.isMMExec(no) or P.faderLocal(no) ~= nil
        end
        if not ok then return nil, execError(mod and (mod .. ":" .. no) or tostring(no)) end
        out.list[#out.list + 1] = { mod = mod, exec = no }
      end
    end
  end
  if not out.auto and #out.list == 0 then
    return nil, "Executors: type auto, executor numbers, or use Learn keys."
  end
  return out
end

-- Text of a speed master fader ("120", "120.5 BPM", "2 Hz", "0.5s").
-- Returns value, unit ("bpm" | "hz" | "s") and number of decimals.
function P.parseSpeedText(text)
  if type(text) ~= "string" then return nil end
  local t = text:lower()
  local num = t:match("(%d+[%.,]?%d*)")
  if not num then return nil end
  num = num:gsub(",", ".")
  local v = tonumber(num)
  if not v then return nil end
  local decimals = #(num:match("%.(%d*)$") or "")
  local unit = "bpm"
  if t:find("hz", 1, true) then
    unit = "hz"
  elseif t:find("bpm", 1, true) then
    unit = "bpm"
  elseif t:find("%d%s*s$") or t:find("sec", 1, true) then
    unit = "s"
  end
  return v, unit, decimals
end

function P.toBpm(v, unit)
  if unit == "hz" then return v * 60 end
  if unit == "s" then
    if v <= 0 then return math.huge end
    return 60 / v
  end
  return v
end

function P.curveBpm(fader, scaleExp)
  if type(fader) ~= "number" or fader <= 0 then return 0 end
  return CURVE_MAX_BPM * (fader / 100) ^ CURVE_EXPONENT * 2 ^ (scaleExp or 0)
end

-- BPM from the text shown on the master. The fader position gives the same
-- value with more decimals, so it is used when it agrees with the text.
-- Returns bpm (nil if unknown) and where it came from.
function P.chooseBpm(text, fader, scaleExp)
  local v, unit, decimals = P.parseSpeedText(text)
  local curves = {}
  if type(fader) == "number" then
    if scaleExp and scaleExp ~= 0 then curves[#curves + 1] = P.curveBpm(fader, scaleExp) end
    curves[#curves + 1] = P.curveBpm(fader, 0)
  end
  if v then
    local half = 0.5 * 10 ^ (-decimals)
    local a, b = P.toBpm(math.max(v - half, 0), unit), P.toBpm(v + half, unit)
    local lo, hi = math.min(a, b), math.max(a, b)
    for _, c in ipairs(curves) do
      if c > 0 and c >= lo - 1e-9 and c <= hi + 1e-9 then return c, "fader" end
    end
    return P.toBpm(v, unit), "text"
  end
  if curves[1] then return curves[1], "fader" end
  return nil, "none"
end

-- SpeedScale property: a number (2^x) or a name like "Mul2" / "Div4" / "x2".
function P.scaleExponent(v)
  if type(v) == "number" then return v end
  local s = P.trim(v):lower()
  if s == "" or s == "none" or s == "one" then return 0 end
  if tonumber(s) then return tonumber(s) end
  local mul = s:match("^mul(%d+)$") or s:match("^x%s*(%d+)$") or s:match("^%*%s*(%d+)$")
  local div = s:match("^div(%d+)$") or s:match("^/%s*(%d+)$")
  local n = tonumber(mul or div)
  if not n or n <= 0 then return 0 end
  local e = math.log(n) / math.log(2)
  return div and -e or e
end

--------------------------------------------------------------------------------
-- FLASH ENGINE
-- Turns time and BPM into a brightness level 0..1. nil = speed master stopped.
--------------------------------------------------------------------------------
local Engine = {}
Engine.__index = Engine

function Engine.new(cfg)
  return setmetatable({
    rate = cfg.rate, duty = cfg.duty / 100, pulse = cfg.pulse, resync = cfg.resync,
    bpm = nil, origin = nil, changed = nil, tapped = nil,
  }, Engine)
end

function Engine:period()
  return 60 / (self.bpm * self.rate)
end

function Engine:phase(now)
  return ((now - self.origin) / self:period()) % 1
end

-- A key tap: the next flash starts now.
function Engine:tap(now)
  self.tapped = now
  if self.bpm then self.origin = now end
end

function Engine:update(now, bpm)
  if not bpm or bpm ~= bpm or bpm <= 0 or bpm == math.huge then
    self.bpm = nil
    return nil
  end
  if not self.bpm then
    self.bpm, self.origin, self.changed = bpm, now, now
  elseif math.abs(bpm - self.bpm) > 1e-6 then
    local quiet = now - self.changed >= SETTINGS.tapGap
    if self.resync and quiet then
      -- Tap tempo: line up with the tap that changed the BPM.
      local recentTap = self.tapped and now - self.tapped < 0.15
      self.origin = recentTap and self.tapped or now
      self.bpm = bpm
    else
      local phase = self:phase(now)
      self.bpm = bpm
      self.origin = now - phase * self:period()
    end
    self.changed = now
  end
  return self:level(now)
end

function Engine:level(now)
  local phase = self:phase(now)
  if self.pulse then
    if phase >= self.duty then return 0 end
    local x = 1 - phase / self.duty
    return x * x
  end
  return (phase < self.duty) and 1 or 0
end

--------------------------------------------------------------------------------
-- grandMA3 API WRAPPERS
--------------------------------------------------------------------------------
local MA = {}

function MA.log(msg)
  Printf("%s", "[" .. TITLE .. "] " .. tostring(msg))
end

function MA.err(msg)
  if ErrPrintf then
    ErrPrintf("%s", "[" .. TITLE .. "] " .. tostring(msg))
  else
    MA.log(msg)
  end
end

function MA.getVar(key, default)
  if not SETTINGS.rememberValues then return default end
  local ok, v = pcall(function() return GetVar(UserVars(), "SML_" .. key) end)
  if ok and v ~= nil and tostring(v) ~= "" then return tostring(v) end
  return default
end

function MA.setVar(key, value)
  if not SETTINGS.rememberValues then return end
  if type(value) == "boolean" then value = value and "1" or "0" end
  pcall(function() SetVar(UserVars(), "SML_" .. key, tostring(value)) end)
end

function MA.time()
  local ok, t = pcall(Time)
  if ok and type(t) == "number" then return t end
  return os.clock()
end

-- True when the plugin can wait without blocking the console.
function MA.canWait()
  return coroutine.isyieldable ~= nil and coroutine.isyieldable()
end

function MA.sleep(seconds)
  if MA.canWait() then coroutine.yield(seconds) end
end

function MA.prop(h, key)
  local ok, v = pcall(function() return h[key] end)
  if ok then return v end
  return nil
end

function MA.count(h)
  local ok, n = pcall(function() return #h end)
  if ok and type(n) == "number" then return n end
  ok, n = pcall(function() return h:Count() end)
  if ok and type(n) == "number" then return n end
  return 0
end

function MA.children(h)
  local ok, kids = pcall(function() return h:Children() end)
  if ok and type(kids) == "table" then return kids end
  local out = {}
  for i = 1, MA.count(h) do
    local okc, k = pcall(function() return h[i] end)
    if okc and k then out[#out + 1] = k end
  end
  return out
end

function MA.addrOf(h)
  local ok, a = pcall(function() return h:ToAddr() end)
  if ok and type(a) == "string" then return a end
  return nil
end

function MA.same(a, b)
  if a == nil or b == nil then return false end
  if a == b then return true end
  local ok1, x = pcall(HandleToInt, a)
  local ok2, y = pcall(HandleToInt, b)
  if ok1 and ok2 and x ~= nil and x == y then return true end
  local ax, bx = MA.addrOf(a), MA.addrOf(b)
  return ax ~= nil and ax == bx
end

function MA.host()
  local okT, t = pcall(HostType)
  local okS, s = pcall(HostSubType)
  return okT and tostring(t) or "?", okS and tostring(s) or "?"
end

-- All properties of an object: { { name, raw, text } }.
function MA.properties(h)
  local out, seen = {}, {}
  local okc, n = pcall(function() return h:PropertyCount() end)
  if not okc or type(n) ~= "number" then return out end
  local role
  pcall(function() role = Enums.Roles.Display end)
  for i = 0, n do -- the index base isn't documented: try both
    local okn, name = pcall(function() return h:PropertyName(i) end)
    if okn and type(name) == "string" and name ~= "" and not seen[name] then
      seen[name] = true
      local entry = { name = name }
      local okr, raw = pcall(function() return h:Get(name) end)
      if okr then entry.raw = raw end
      if role ~= nil then
        local okt, text = pcall(function() return h:Get(name, role) end)
        if okt then entry.text = text end
      end
      out[#out + 1] = entry
    end
  end
  return out
end

-- Works out whether a module is the MM, MFE or MFX.
-- Returns type (or nil) and how it was found.
function MA.moduleType(h, name)
  local forced = SETTINGS.moduleTypes[name]
  if forced and HW[forced] then return forced, "set in SETTINGS" end
  local found = {}
  local function look(propName, v)
    if v == nil then return end
    for t, info in pairs(MODULE_INFO) do
      local hit = false
      if type(v) == "string" then
        for _, pat in ipairs(info.patterns) do
          if v:find(pat) then hit = true break end
        end
      end
      -- A bare number only counts in a property that is about the product.
      local lname = propName:lower()
      if not hit and (lname:find("product", 1, true) or lname:find("pid", 1, true)) then
        hit = tonumber(v) == info.product
      end
      if hit then found[t] = propName end
    end
  end
  for _, p in ipairs(MA.properties(h)) do
    look(p.name, p.raw)
    look(p.name, p.text)
  end
  local types = {}
  for t in pairs(found) do types[#types + 1] = t end
  if #types == 1 then return types[1], "property " .. found[types[1]] end
  if #types > 1 then return nil, "it reports more than one type" end
  local _, sub = MA.host()
  if (sub == "FullSize" or sub == "FullSizeCRV") and FULLSIZE_NAMES[name] then
    return FULLSIZE_NAMES[name], "full-size module name", true
  end
  return nil, "type not found"
end

-- The console's hardware modules: { { handle, name, type, how } }.
function MA.modules()
  local list = {}
  local ok, coll = pcall(function() return Root().UsbNotifier.MA3Modules end)
  if not ok or not coll then return list end
  for i, h in ipairs(MA.children(coll)) do
    local name = tostring(MA.prop(h, "Name") or ("Module " .. i))
    local t, how, guessed = MA.moduleType(h, name)
    list[#list + 1] = { handle = h, name = name, type = t, how = how, guessed = guessed or nil }
  end
  return list
end

function MA.setLeds(h, frame)
  local ok, err = pcall(SetLED, h, frame)
  if not ok then error("SetLED failed: " .. tostring(err), 0) end
end

function MA.buttons(h)
  local ok, t = pcall(GetButton, h)
  if ok and type(t) == "table" then return t end
  return nil
end

function MA.pressed(state, index)
  local v = state and state[index]
  return v == true or tostring(v) == "true"
end

function MA.speedMaster(no)
  local tries = {
    function() return MasterPool().Speed[no] end,
    function() return ShowData().Masters.Speed[no] end,
    function() return ShowData().Masters[3][no] end,
    function() return ObjectList("Master 3." .. no)[1] end,
  }
  for _, f in ipairs(tries) do
    local ok, h = pcall(f)
    if ok and h ~= nil then return h end
  end
  return nil
end

-- Raw readings of a speed master: fader text, fader 0-100, scale exponent.
function MA.readSpeed(master)
  local okT, text = pcall(function() return master:GetFaderText({}) end)
  local okF, fader = pcall(function() return master:GetFader({}) end)
  return okT and text or nil, okF and tonumber(fader) or nil, P.scaleExponent(MA.prop(master, "SpeedScale"))
end

function MA.bpm(master)
  return P.chooseBpm(MA.readSpeed(master))
end

-- Executors on the current page that hold the given object (wide ones count
-- once per column).
function MA.execsHolding(object)
  local found, seen = {}, {}
  for _, no in ipairs(SCAN_EXECS) do
    local ok, ex = pcall(GetExecutor, no)
    if ok and ex ~= nil then
      local obj = MA.prop(ex, "Object")
      if MA.same(obj, object) then
        local width = P.clamp(tonumber(MA.prop(ex, "Width")) or 1, 1, 15)
        for i = 0, width - 1 do
          if not seen[no + i] then
            seen[no + i] = true
            found[#found + 1] = no + i
          end
        end
      end
    end
  end
  table.sort(found)
  return found
end

local Progress = {}
function Progress.start(text)
  local ok, h = pcall(StartProgress, text)
  if ok then return h end
  return nil
end
function Progress.text(h, text)
  if h then pcall(SetProgressText, h, text) end
end
function Progress.stop(h)
  if h then pcall(StopProgress, h) end
end

--------------------------------------------------------------------------------
-- TARGETS: which LEDs flash
--------------------------------------------------------------------------------
local T = {}

-- True when the plugin may set this LED on this module.
function T.writable(m, idx)
  if not (m.type and ALLOWED[m.type] and ALLOWED[m.type][idx]) then return false end
  return not m.guessed or idx <= GUESSED_MAX
end

local function byType(modules)
  local out = { MM = {}, MFE = {}, MFX = {} }
  for _, m in ipairs(modules) do
    if m.type and out[m.type] then table.insert(out[m.type], m) end
  end
  return out
end

function T.label(m, exec)
  if m.type == "MM" then return tostring(exec) end
  return m.type .. ":" .. exec
end

-- cfg.execs from P.parseExecs, autoExecs = executor numbers holding the master.
-- Returns targets and notes about executors that can't be placed.
function T.resolve(cfg, modules, autoExecs)
  local types = byType(modules)
  local faders = {}
  for _, m in ipairs(types.MFE) do faders[#faders + 1] = m end
  for _, m in ipairs(types.MFX) do faders[#faders + 1] = m end

  local targets, notes, seen = {}, {}, {}
  local function note(text)
    for _, n in ipairs(notes) do if n == text then return end end
    notes[#notes + 1] = text
  end
  local function add(m, exec)
    local key = m.name .. "|" .. exec
    if seen[key] then return end
    seen[key] = true
    local hw = HW[m.type]
    local t = {
      module = m, exec = exec, label = T.label(m, exec),
      key = hw.keys[exec], rgb = hw.rgb[exec], button = hw.buttons[exec],
    }
    targets[#targets + 1] = t
    local all = { t.key }
    for _, i in ipairs(t.rgb or {}) do all[#all + 1] = i end
    for _, i in ipairs(all) do
      if not T.writable(m, i) then
        note(m.name .. "'s type is only guessed from its name, so some LEDs of " .. t.label
          .. " are left alone. Set moduleTypes in SETTINGS to use them.")
        break
      end
    end
  end
  local function place(mod, no)
    if mod then
      if #types[mod] == 0 then return note("There's no " .. MODULE_INFO[mod].name .. " on this console.") end
      for _, m in ipairs(types[mod]) do add(m, no) end
    elseif P.isMMExec(no) then
      if #types.MM == 0 then return note("Executor " .. no .. ": there's no master module I can use.") end
      for _, m in ipairs(types.MM) do add(m, no) end
    else
      local loc, upper = P.faderLocal(no)
      if not loc then return end
      if #faders == 0 then
        note("Executor " .. no .. ": there's no fader module I can use.")
      elseif #faders == 1 and not upper then
        add(faders[1], loc)
      elseif #faders == 1 then
        note("Executor " .. no .. " isn't on this console's fader module. Use Learn keys.")
      else
        note("Executor " .. no .. ": this console has two fader modules and I can't tell which one "
          .. "shows it. Use Learn keys (or type MFE:" .. loc .. " or MFX:" .. loc .. ").")
      end
    end
  end
  for _, e in ipairs(cfg.execs.list) do place(e.mod, e.exec) end
  if cfg.execs.auto then
    for _, no in ipairs(autoExecs or {}) do place(nil, no) end
  end
  if cfg.screenEncoders then
    for _, m in ipairs(types.MM) do
      targets[#targets + 1] = { module = m, label = "screen encoders", encoders = HW.MM.encoders }
    end
  end
  return targets, notes
end

function T.describe(targets)
  local parts = {}
  for _, t in ipairs(targets) do parts[#parts + 1] = t.label end
  return table.concat(parts, ", ")
end

function T.same(a, b)
  return T.describe(a) == T.describe(b)
end

-- LED values for one frame: { [module] = { [index] = value } }.
-- level nil = hand every LED back to the console.
function T.values(targets, cfg, level)
  local values = {}
  for _, t in ipairs(targets) do values[t.module] = values[t.module] or {} end
  if level == nil then return values end
  local dim = cfg.dim / 100
  local k = dim + (1 - dim) * level
  local keyV = P.round(255 * P.clamp(SETTINGS.keyBrightness, 0, 100) / 100 * k)
  local rgbV = { P.round(cfg.color[1] * k), P.round(cfg.color[2] * k), P.round(cfg.color[3] * k) }
  for _, t in ipairs(targets) do
    local m, v = t.module, values[t.module]
    local function set(idx, value)
      if T.writable(m, idx) then v[idx] = value end
    end
    if cfg.keys and t.key then set(t.key, keyV) end
    if cfg.rings and t.rgb then
      for c = 1, 3 do set(t.rgb[c], rgbV[c]) end
    end
    if t.encoders then
      for _, e in ipairs(t.encoders) do
        for c = 1, 3 do set(e[c], rgbV[c]) end
      end
    end
  end
  return values
end

-- True when the key of any target was just pressed.
function T.tapped(targets, prev)
  local hit = false
  local states = {}
  for _, t in ipairs(targets) do
    if t.button then
      local m = t.module
      if states[m] == nil then states[m] = MA.buttons(m.handle) or false end
      prev[m] = prev[m] or {}
      local down = MA.pressed(states[m], t.button)
      if down and not prev[m][t.button] then hit = true end
      prev[m][t.button] = down
    end
  end
  return hit
end

--------------------------------------------------------------------------------
-- LED OUTPUT
-- Keeps one SetLED table per module. Indices we don't drive stay -1 (left to
-- the console). Sends when something changed, and every refreshTime.
--------------------------------------------------------------------------------
local Output = {}
Output.__index = Output

function Output.new()
  return setmetatable({ mods = {} }, Output)
end

function Output:state(m)
  local st = self.mods[m]
  if not st then
    local frame = {}
    for i = 1, SETTINGS.ledTableSize do frame[i] = -1 end
    st = { frame = frame, used = {}, sent = -math.huge }
    self.mods[m] = st
  end
  return st
end

function Output:show(values, now)
  for m, vals in pairs(values) do
    local st = self:state(m)
    local changed = false
    for idx in pairs(st.used) do
      if vals[idx] == nil then
        st.frame[idx] = -1
        st.used[idx] = nil
        changed = true
      end
    end
    for idx, v in pairs(vals) do
      if not T.writable(m, idx) then
        error("refusing to set LED " .. tostring(idx) .. " on " .. tostring(m.name), 0)
      end
      v = P.clamp(P.round(v), 0, 255)
      if st.frame[idx] ~= v then
        st.frame[idx] = v
        changed = true
      end
      st.used[idx] = true
    end
    if changed or (next(st.used) ~= nil and now - st.sent >= SETTINGS.refreshTime) then
      MA.setLeds(m.handle, st.frame)
      st.sent = now
    end
  end
  for m in pairs(self.mods) do
    if values[m] == nil then self:release(m) end
  end
end

function Output:release(m)
  local st = self.mods[m]
  if not st or next(st.used) == nil then return end
  for idx in pairs(st.used) do st.frame[idx] = -1 end
  st.used = {}
  pcall(MA.setLeds, m.handle, st.frame)
end

function Output:releaseAll()
  for m in pairs(self.mods) do self:release(m) end
end

--------------------------------------------------------------------------------
-- SHARED STATE between runs of the plugin (start in one, stop from another)
--------------------------------------------------------------------------------
local G = (type(_G) == "table") and _G or {}
local shared = rawget(G, "SpeedMasterLEDs_State")
if type(shared) ~= "table" then
  shared = { token = 0 }
  rawset(G, "SpeedMasterLEDs_State", shared)
end

local function isRunning()
  return shared.running ~= nil and shared.running == shared.token
    and shared.alive ~= nil and MA.time() - shared.alive < 2
end

local function stop()
  shared.token = shared.token + 1
end

-- Also reachable from the command line: Lua "SpeedMasterLEDs_Stop()"
rawset(G, "SpeedMasterLEDs_Stop", stop)

--------------------------------------------------------------------------------
-- DIALOGS
--------------------------------------------------------------------------------
local UI = {}

local function focusDisplay()
  local ok, d = pcall(GetFocusDisplay)
  if ok then return d end
  return nil
end

function UI.message(title, text)
  pcall(MessageBox, {
    title = title, message = text,
    commands = { { value = 1, name = "OK" } },
  })
end

function UI.error(text)
  MA.err(text)
  UI.message(TITLE .. " - problem", text)
end

-- Shows a list, returns the chosen item string (or nil).
function UI.choose(title, items)
  local ok, idx, value = pcall(PopupInput, { title = title, caller = focusDisplay(), items = items })
  if ok then
    if type(value) == "string" and value ~= "" then return value end
    if type(idx) == "number" then return items[idx + 1] end
    return nil
  end
  local lines = {}
  for i, item in ipairs(items) do lines[#lines + 1] = i .. "  " .. item end
  local okm, res = pcall(MessageBox, {
    title = title, message = table.concat(lines, "\n"),
    commands = { { value = 1, name = "OK" }, { value = 0, name = "Cancel" } },
    inputs = { { name = "Number", value = "1", whiteFilter = "0123456789" } },
  })
  if okm and type(res) == "table" and res.result == 1 and res.inputs then
    return items[tonumber(res.inputs["Number"]) or 0]
  end
  return nil
end

-- Generic form. values: key -> current value. Returns new values + button.
function UI.form(title, message, fields, values, buttons)
  local inputs, states, labels = {}, {}, {}
  local n = 0
  for _, f in ipairs(fields) do
    if f.type == "bool" then
      states[#states + 1] = { name = f.label, state = P.toBool(values[f.key]) }
      labels[f.key] = f.label
    else
      n = n + 1
      local label = string.format("%d %s", n, f.label)
      labels[f.key] = label
      local input = { name = label, value = tostring(values[f.key] == nil and "" or values[f.key]) }
      if f.type == "int" then
        input.whiteFilter = "0123456789"
        input.vkPlugin = "TextInputNumOnly"
      else
        input.maxTextLength = 256
      end
      inputs[#inputs + 1] = input
    end
  end
  local spec = {
    title = title,
    message = message,
    commands = buttons,
    inputs = (#inputs > 0) and inputs or nil,
    states = (#states > 0) and states or nil,
  }
  local ok, res = pcall(MessageBox, spec)
  if not ok then
    -- Older versions may not know the optional input keys: retry without them.
    for _, input in ipairs(inputs) do
      input.whiteFilter, input.vkPlugin, input.maxTextLength = nil, nil, nil
    end
    ok, res = pcall(MessageBox, spec)
  end
  if not ok then
    MA.err("Dialog failed: " .. tostring(res))
    return nil
  end
  if type(res) ~= "table" or not res.result or res.result == 0 then return nil end
  local out = {}
  for k, v in pairs(values) do out[k] = v end
  for _, f in ipairs(fields) do
    local label = labels[f.key]
    if f.type == "bool" then
      if res.states and res.states[label] ~= nil then out[f.key] = P.toBool(res.states[label]) end
    elseif res.inputs and res.inputs[label] ~= nil then
      out[f.key] = res.inputs[label]
    end
  end
  return out, res.result
end

local FIELDS = {
  { key = "master",   label = "Speed master",                     type = "int",  default = 1 },
  { key = "execs",    label = "Executors",                        type = "text", default = "auto" },
  { key = "rate",     label = "Flashes per beat",                 type = "text", default = "1" },
  { key = "duty",     label = "On time %",                        type = "int",  default = 50 },
  { key = "color",    label = "Encoder colour",                   type = "text", default = "White" },
  { key = "dim",      label = "Brightness between flashes %",     type = "int",  default = 0 },
  { key = "keys",     label = "Flash the keys",                   type = "bool", default = true },
  { key = "rings",    label = "Flash the encoder / fader LEDs",   type = "bool", default = true },
  { key = "screenEncoders", label = "Also flash the 5 screen encoders", type = "bool", default = false },
  { key = "pulse",    label = "Pulse (fade out) instead of blink", type = "bool", default = false },
  { key = "resync",   label = "Line up with taps",                type = "bool", default = true },
}

local SETUP_MESSAGE = "Flashes executor LEDs in time with a speed master.\n"
  .. "Executors: auto = the executors on this page that hold the speed master,\n"
  .. "or numbers: 291, 293-295 (X-keys and knobs), 201 (fader), MFE:401 / MFX:401.\n"
  .. "Learn keys: tap the keys to flash instead of typing them.\n"
  .. "Colour: White, Red, Amber, Green, Cyan, Blue, Magenta ... or 255,0,0."

local HELP_TEXT = [[
Flashes executor LEDs in time with a speed master's BPM.

EXECUTORS
  auto         the executors on the current page that hold the speed master.
               Follows page changes.
  291, 293     executor numbers. X-keys 191-198 and 291-298 (with the knobs
               above X1-X8), or 101-415 when the console has one fader module.
  MFE:401      an executor on a given fader module: MFE = the module with
               encoders, MFX = the module with the crossfader.
  Learn keys   tap the keys to flash (tap again to remove). Touching a fader
               picks its 2xx executor. Each tap also does what the key does.

WHAT FLASHES
  The key LED, the knob LED (291-298, 3xx, 4xx) or the fader LED (2xx), and
  if you like the 5 dual encoders under the screen.

TIMING
  The plugin reads the BPM, not the speed master's beat position. A flash
  starts on the beat when you tap a flashing key, or when the BPM jumps (a
  tap tempo). With "Line up with taps" off, the flashes just keep running.

FROM A MACRO OR KEY
  Plugin "Speed Master LEDs" "toggle"     ("start", "stop", "check")

Supported: the MA3 master and fader modules (MM, MFE, MFX) of the full-size,
and the light if it reports the same modules. onPC, compact consoles and
wings have no published LED map.]]

local function initialValues()
  local values = {}
  for _, f in ipairs(FIELDS) do
    local saved = MA.getVar(f.key, nil)
    local value = f.default
    if saved ~= nil then
      if f.type == "bool" then value = P.toBool(saved) else value = saved end
    end
    values[f.key] = value
  end
  return values
end

local function saveValues(values)
  for _, f in ipairs(FIELDS) do
    if values[f.key] ~= nil then MA.setVar(f.key, values[f.key]) end
  end
end

-- Dialog values -> config, or nil + error.
local function makeConfig(values)
  local cfg = {}
  cfg.master = P.toInt(values.master, nil)
  if not cfg.master or cfg.master < 1 or cfg.master > 16 then
    return nil, "Speed master: use a number from 1 to 16."
  end
  local err
  cfg.execs, err = P.parseExecs(values.execs)
  if not cfg.execs then return nil, err end
  cfg.rate, err = P.parseRate(values.rate)
  if not cfg.rate then return nil, err end
  cfg.duty = P.toInt(values.duty, nil)
  if not cfg.duty or cfg.duty < 5 or cfg.duty > 95 then return nil, "On time: use 5 to 95 %." end
  cfg.color, err = P.parseColor(values.color)
  if not cfg.color then return nil, err end
  cfg.dim = P.toInt(values.dim, nil)
  if not cfg.dim or cfg.dim < 0 or cfg.dim > 90 then return nil, "Brightness between flashes: use 0 to 90 %." end
  cfg.keys = P.toBool(values.keys)
  cfg.rings = P.toBool(values.rings)
  cfg.screenEncoders = P.toBool(values.screenEncoders)
  cfg.pulse = P.toBool(values.pulse)
  cfg.resync = P.toBool(values.resync)
  if not (cfg.keys or cfg.rings or cfg.screenEncoders) then
    return nil, "Tick at least one of: keys, encoder / fader LEDs, screen encoders."
  end
  return cfg
end

--------------------------------------------------------------------------------
-- RUN
--------------------------------------------------------------------------------
local function usableModules(modules)
  local list = {}
  for _, m in ipairs(modules) do
    if m.type then list[#list + 1] = m end
  end
  return list
end

local function noModulesText(modules)
  if #modules == 0 then
    return "No grandMA3 surface modules found. The plugin needs a full-size or light console "
      .. "(onPC, compact consoles and wings aren't supported)."
  end
  local names = {}
  for _, m in ipairs(modules) do names[#names + 1] = m.name end
  return "I can't tell which hardware modules these are: " .. table.concat(names, ", ") .. ".\n"
    .. "Run \"Check BPM and hardware\" and set moduleTypes in the plugin's SETTINGS."
end

-- Flashes until stopped. Runs inside the plugin call, so this call returns
-- only when the flashing stops.
local function run(cfg)
  if not MA.canWait() then return UI.error("This console can't run the plugin in the background.") end
  stop() -- ends any loop that is already running
  local token = shared.token

  local master = MA.speedMaster(cfg.master)
  if not master then return UI.error("Speed Master " .. cfg.master .. " doesn't exist in this show.") end
  local modules = usableModules(MA.modules())
  if #modules == 0 then return UI.error(noModulesText(MA.modules())) end

  local function resolve()
    local auto = cfg.execs.auto and MA.execsHolding(master) or nil
    return T.resolve(cfg, modules, auto)
  end
  local targets, notes = resolve()
  if #targets == 0 then
    if #notes == 0 then
      notes[1] = "Speed Master " .. cfg.master .. " isn't on an executor of this page with LEDs I can drive. "
        .. "Type the executors or use Learn keys."
    end
    return UI.error(table.concat(notes, "\n"))
  end
  for _, n in ipairs(notes) do MA.err(n) end
  MA.log(string.format("Flashing %s with Speed Master %d. Run the plugin again to stop.",
    T.describe(targets), cfg.master))

  local engine = Engine.new(cfg)
  local out = Output.new()
  local prevButtons = {}
  local lastScan = MA.time()
  shared.running, shared.master, shared.alive, shared.bpm = token, cfg.master, lastScan, nil

  local ok, err = pcall(function()
    while shared.token == token do
      local now = MA.time()
      shared.alive = now
      if cfg.execs.auto and now - lastScan >= SETTINGS.rescanTime then
        lastScan = now
        local fresh = resolve()
        if not T.same(fresh, targets) then
          targets = fresh
          MA.log("Now flashing: " .. (#targets > 0 and T.describe(targets) or "nothing (not on this page)"))
        end
      end
      local bpm = MA.bpm(master)
      shared.bpm = bpm
      if cfg.resync and T.tapped(targets, prevButtons) then engine:tap(now) end
      local level = engine:update(now, bpm)
      out:show(T.values(targets, cfg, level), now)
      MA.sleep(SETTINGS.frameTime)
    end
  end)
  out:releaseAll()
  if shared.running == token then shared.running = nil end
  if ok then
    MA.log("Stopped.")
  else
    UI.error("Stopped: " .. tostring(err))
  end
end

--------------------------------------------------------------------------------
-- LEARN KEYS
--------------------------------------------------------------------------------
-- Listens to the keys and returns the executors tapped, as text for the
-- Executors field (nil if nothing was tapped).
local function learn(values)
  if not MA.canWait() then
    UI.error("This console can't listen to the keys from a plugin.")
    return nil
  end
  local modules = usableModules(MA.modules())
  if #modules == 0 then
    UI.error(noModulesText(MA.modules()))
    return nil
  end
  local cfg = makeConfig(values) or makeConfig({
    master = 1, execs = "auto", rate = "1", duty = 50, color = "White", dim = 0, keys = true, rings = true,
  })

  local picked, order = {}, {}
  local prev = {}
  local out = Output.new()
  local start = MA.time()
  local lastTap = nil
  local progress = Progress.start(TITLE .. ": tap the keys to flash")

  local function toggle(m, exec)
    local key = m.name .. "|" .. exec
    if picked[key] then
      picked[key] = nil
      for i, k in ipairs(order) do if k == key then table.remove(order, i) break end end
    else
      picked[key] = { module = m, exec = exec }
      order[#order + 1] = key
    end
  end

  local function current()
    local targets = {}
    for _, key in ipairs(order) do
      local p = picked[key]
      local hw = HW[p.module.type]
      targets[#targets + 1] = { module = p.module, exec = p.exec, label = T.label(p.module, p.exec),
        key = hw.keys[p.exec], rgb = hw.rgb[p.exec] }
    end
    return targets
  end

  local lit = { keys = true, rings = true, dim = 0, color = cfg.color }
  local ok, err = pcall(function()
    while true do
      local now = MA.time()
      for _, m in ipairs(modules) do
        local state = MA.buttons(m.handle)
        if state then
          prev[m] = prev[m] or {}
          local hw = HW[m.type]
          for _, map in ipairs({ hw.buttons, hw.touch }) do
            for exec, index in pairs(map) do
              local down = MA.pressed(state, index)
              local id = (map == hw.touch and "t" or "b") .. index
              if down and not prev[m][id] then
                toggle(m, exec)
                lastTap = now
              end
              prev[m][id] = down
            end
          end
        end
      end
      local targets = current()
      out:show(T.values(targets, lit, 1), now)
      local left
      if lastTap then
        left = SETTINGS.learnIdle - (now - lastTap)
      else
        left = SETTINGS.learnMaxWait - (now - start)
      end
      Progress.text(progress, string.format("Tapped: %s  (done in %d s)",
        #targets > 0 and T.describe(targets) or "-", math.max(0, math.ceil(left))))
      if left <= 0 then break end
      MA.sleep(0.03)
    end
  end)
  out:releaseAll()
  Progress.stop(progress)
  if not ok then
    UI.error("Learn keys stopped: " .. tostring(err))
    return nil
  end
  local targets = current()
  if #targets == 0 then
    UI.message(TITLE, "No keys were tapped.")
    return nil
  end
  local text = T.describe(targets)
  MA.log("Learned: " .. text)
  return text
end

--------------------------------------------------------------------------------
-- CHECK
--------------------------------------------------------------------------------
local function check(values)
  local lines = {}
  local function add(s) lines[#lines + 1] = s end
  local hostType, hostSub = MA.host()
  add("Console: " .. hostType .. " / " .. hostSub)

  local no = P.toInt(values and values.master, 1) or 1
  local master = MA.speedMaster(no)
  if master then
    local text, fader, scale = MA.readSpeed(master)
    local bpm, source = P.chooseBpm(text, fader, scale)
    add(string.format("Speed Master %d: shows \"%s\", fader %s %%, BPM %s (from the %s)",
      no, tostring(text), fader and string.format("%.1f", fader) or "?",
      bpm and string.format("%.2f", bpm) or "?", source))
  else
    add("Speed Master " .. no .. ": not found")
  end

  local modules = MA.modules()
  if #modules == 0 then add("Hardware modules: none found") end
  for _, m in ipairs(modules) do
    if m.type then
      add(string.format("%s: %s (%s)", m.name, MODULE_INFO[m.type].name, m.how))
    else
      add(string.format("%s: not used, %s", m.name, m.how))
      MA.log("Properties of " .. m.name .. ":")
      for _, p in ipairs(MA.properties(m.handle)) do
        MA.log(string.format("  %s = %s", p.name, tostring(p.text ~= nil and p.text or p.raw)))
      end
    end
  end

  if master then
    local execs = MA.execsHolding(master)
    add("On this page the speed master is on: " .. (#execs > 0 and table.concat(execs, ", ") or "no executor"))
    local cfg = values and makeConfig(values)
    if cfg then
      local targets, notes = T.resolve(cfg, usableModules(modules), cfg.execs.auto and execs or nil)
      add("Would flash: " .. (#targets > 0 and T.describe(targets) or "nothing"))
      for _, n in ipairs(notes) do add(n) end
    end
  end
  add(isRunning() and "Flashing is running." or "Flashing is stopped.")

  for _, l in ipairs(lines) do MA.log(l) end
  UI.message(TITLE .. " - check", table.concat(lines, "\n"))
end

--------------------------------------------------------------------------------
-- MAIN
--------------------------------------------------------------------------------
local function startSaved()
  local values = initialValues()
  local cfg, err = makeConfig(values)
  if not cfg then return UI.error(err) end
  return run(cfg)
end

local function setup()
  local values = initialValues()
  while true do
    local vals, button = UI.form(TITLE, SETUP_MESSAGE, FIELDS, values, {
      { value = 1, name = "Start" }, { value = 2, name = "Learn keys" },
      { value = 3, name = "Check" }, { value = 4, name = "Help" }, { value = 0, name = "Cancel" },
    })
    if not vals then return end
    values = vals
    if button == 2 then
      local text = learn(values)
      if text then values.execs = text end
    elseif button == 3 then
      check(values)
    elseif button == 4 then
      UI.message(TITLE .. " - help", HELP_TEXT)
    else
      local cfg, err = makeConfig(values)
      if cfg then
        saveValues(values)
        return run(cfg)
      end
      UI.error(err)
    end
  end
end

local function Main(displayHandle, argument)
  local arg = P.trim(argument):lower()
  if arg == "stop" then return stop() end
  if arg == "start" then return startSaved() end
  if arg == "toggle" then
    if isRunning() then return stop() end
    return startSaved()
  end
  if arg == "check" then return check(initialValues()) end

  if not isRunning() then return setup() end
  local status = string.format("running, Speed Master %s%s", tostring(shared.master),
    shared.bpm and string.format(" at %.1f BPM", shared.bpm) or "")
  local choice = UI.choose(TITLE .. " - " .. status,
    { "Stop flashing", "Change settings", "Check BPM and hardware", "Help" })
  if choice == "Stop flashing" then
    stop()
  elseif choice == "Change settings" then
    stop()
    setup()
  elseif choice == "Check BPM and hardware" then
    check(initialValues())
  elseif choice == "Help" then
    UI.message(TITLE .. " - help", HELP_TEXT)
  end
end

-- Test hook: lets the offline test suite reach the internals. Never set on a console.
if type(SML_TEST_HOOK) == "table" then
  SML_TEST_HOOK.P, SML_TEST_HOOK.MA, SML_TEST_HOOK.T = P, MA, T
  SML_TEST_HOOK.HW, SML_TEST_HOOK.ALLOWED, SML_TEST_HOOK.SETTINGS = HW, ALLOWED, SETTINGS
  SML_TEST_HOOK.Engine, SML_TEST_HOOK.Output, SML_TEST_HOOK.shared = Engine, Output, shared
  SML_TEST_HOOK.makeConfig, SML_TEST_HOOK.GUESSED_MAX = makeConfig, GUESSED_MAX
end

return Main
