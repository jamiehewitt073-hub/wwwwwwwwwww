--[[
================================================================================
  DESKLOCK - grandMA3 plugin                                            v1.0.0
================================================================================
  Locks the desk behind a full-screen picture on EVERY screen (main screens,
  command screen, letterbox, onPC windows ...). Each screen shows its own
  appearance (image) from the Appearances pool, so every screen holds its own
  content. Unlock with a PIN on an on-screen keypad.

    * own image per screen        - any appearance, set per display
    * pixel-perfect sizes         - reads the real size of every display and
                                    exports SVG templates + a size list
    * full lock (hard lock)       - also logs in as a user with no rights, so
                                    keys, encoders and executors do nothing
    * auto-lock on show load      - and a desk that was locked stays locked
                                    after a reboot or show reload
    * failed attempt counter      - on the lock screen and after unlocking
    * cooldown after wrong PINs   - doubles every round
    * optional master PIN         - e.g. for the system tech
    * test lock / preview         - unlocks itself, safe to try out
    * one-press lock              - put  Plugin "DeskLock" "lock"  on a macro

  Run the plugin to open the menu. Start with "Screen sizes", make your
  pictures at exactly those sizes, import them to the Images pool, put them
  in appearances and assign one appearance per screen.

  Edit SETTINGS below to taste.
================================================================================
]]

local pluginName    = select(1, ...)
local componentName = select(2, ...)
local signalTable   = select(3, ...)
local myHandle      = select(4, ...)

local VERSION = "1.0.0"
local TITLE = "DeskLock"

--------------------------------------------------------------------------------
-- SETTINGS
--------------------------------------------------------------------------------
local SETTINGS = {
  -- Size of the PIN pad in pixels. Keep your artwork clear of the centre
  -- of the PIN pad screen by this much (the SVG templates mark the area).
  padWidth  = 360,
  padHeight = 520,

  -- Height of the info line (clock / message / failed attempts) at the bottom.
  infoHeight = 56,

  -- Seconds between lock screen updates (clock, cooldown, watchdog).
  tick = 0.2,

  -- Name of the no-rights user the hard lock logs in as.
  lockUserName = "DeskLock",

  -- Test lock and screen preview unlock themselves after this many seconds.
  testSeconds = 30,
  previewSeconds = 10,

  -- Seconds to wait after the show has loaded before auto-lock kicks in.
  autoLockDelay = 3,

  -- Longest cooldown after repeated wrong PINs, in seconds.
  maxCooldown = 900,

  -- Print what the plugin does to the System Monitor.
  debug = false,
}

local VAR = "PDL_"            -- prefix of the global variables the plugin keeps
local OVERLAY_NAME = "DeskLockOverlay"

--------------------------------------------------------------------------------
-- Small helpers
--------------------------------------------------------------------------------
local U = {}

function U.trim(s) return (tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", "")) end

function U.toBool(v)
  if type(v) == "boolean" then return v end
  if type(v) == "number" then return v ~= 0 end
  v = tostring(v or ""):lower()
  return v == "1" or v == "true" or v == "yes" or v == "on"
end

function U.clamp(v, lo, hi)
  v = tonumber(v) or lo
  if v < lo then return lo end
  if v > hi then return hi end
  return math.floor(v)
end

-- Greatest common divisor, for the aspect ratio in the size list.
function U.gcd(a, b)
  a, b = math.floor(a), math.floor(b)
  while b ~= 0 do a, b = b, a % b end
  return a
end

function U.aspect(w, h)
  if not w or not h or w <= 0 or h <= 0 then return "?" end
  local g = U.gcd(w, h)
  local aw, ah = w / g, h / g
  if aw > 64 or ah > 64 then return string.format("%.3f:1", w / h) end
  return string.format("%d:%d", aw, ah)
end

function U.xmlEscape(s)
  return (tostring(s):gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"):gsub('"', "&quot;"))
end

function U.fileSafe(s)
  return (tostring(s):gsub("[^%w%-_]+", "_"):gsub("_+", "_"):gsub("^_", ""):gsub("_$", ""))
end

--------------------------------------------------------------------------------
-- PIN hashing. The PIN itself is never stored, only a salted, stretched hash.
-- Plain arithmetic (no bit operators) so it runs on any Lua the console uses.
-- A 4-8 digit PIN is no password: this keeps it out of plain sight, nothing more.
--------------------------------------------------------------------------------
local Hash = {}

local function mix(s, h, mul)
  for i = 1, #s do h = (h * mul + s:byte(i)) % 4294967296 end
  return h
end

function Hash.pin(pin, salt)
  local s = tostring(salt) .. ":" .. tostring(pin)
  local a, b = 5381, 2166136261
  for _ = 1, 400 do
    a = mix(s .. b, a, 33)
    b = mix(s .. a, b, 65599)
  end
  return string.format("%08x%08x", math.floor(a), math.floor(b))
end

function Hash.salt()
  local t = {}
  for i = 1, 4 do t[i] = string.format("%04x", math.random(0, 65535)) end
  return table.concat(t)
end

--------------------------------------------------------------------------------
-- grandMA3 access. Everything that touches the console goes through here and
-- is wrapped in pcall, so a missing call on some version never kills the lock.
--------------------------------------------------------------------------------
local MA = {}

MA.clock = function() return os.time() end   -- seconds; the tests replace it

function MA.log(fmt, ...)
  local msg = string.format(fmt, ...)
  pcall(Printf, "[" .. TITLE .. "] " .. msg)
end

function MA.debug(fmt, ...)
  if SETTINGS.debug then MA.log(fmt, ...) end
end

function MA.err(fmt, ...)
  local msg = string.format(fmt, ...)
  if not pcall(ErrPrintf, "[" .. TITLE .. "] " .. msg) then pcall(Printf, "[" .. TITLE .. "] " .. msg) end
end

function MA.cmd(c)
  MA.debug("cmd: %s", c)
  local ok, res = pcall(Cmd, c)
  if not ok then MA.err("command failed: %s (%s)", c, tostring(res)) end
  return ok and res
end

function MA.sleep(seconds)
  -- grandMA3 plugins wait with coroutine.yield(seconds).
  local ok = pcall(coroutine.yield, seconds)
  return ok
end

-- Reads a property, nil on any error.
function MA.get(obj, key)
  if obj == nil then return nil end
  local ok, v = pcall(function() return obj[key] end)
  if ok then return v end
  return nil
end

-- Sets a property, true when the console took it.
function MA.set(obj, key, value)
  if obj == nil then return false end
  local ok = pcall(function() obj[key] = value end)
  return ok
end

function MA.children(obj)
  if obj == nil then return {} end
  local ok, list = pcall(function() return obj:Children() end)
  if ok and type(list) == "table" then return list end
  return {}
end

function MA.name(obj)
  local n = MA.get(obj, "Name")
  if n == nil or n == "" then return nil end
  return tostring(n)
end

function MA.findChild(parent, name)
  local lname = tostring(name):lower()
  for _, c in ipairs(MA.children(parent)) do
    if (MA.name(c) or ""):lower() == lname then return c end
  end
  return nil
end

-- Global variables: they live in the show file, so settings travel with the show
-- and stay the same whichever user is logged in.
local function vars()
  local ok, v = pcall(GlobalVars)
  if ok then return v end
  return nil
end

function MA.getVar(key)
  local ok, v = pcall(GetVar, vars(), VAR .. key)
  if ok then return v end
  return nil
end

function MA.setVar(key, value)
  if value == nil then
    if not pcall(DelVar, vars(), VAR .. key) then pcall(SetVar, vars(), VAR .. key, "") end
    return
  end
  pcall(SetVar, vars(), VAR .. key, tostring(value))
end

-- Displays --------------------------------------------------------------------

-- Width / height of a display in pixels. Tries the usual property names.
function MA.displaySize(d)
  local w = tonumber(MA.get(d, "W")) or tonumber(MA.get(d, "Width"))
  local h = tonumber(MA.get(d, "H")) or tonumber(MA.get(d, "Height"))
  if not w or not h then
    local r = MA.get(d, "AbsRect")
    if type(r) == "table" or type(r) == "userdata" then
      w = w or tonumber(MA.get(r, "w") or MA.get(r, "W"))
      h = h or tonumber(MA.get(r, "h") or MA.get(r, "H"))
    end
  end
  return w and math.floor(w + 0.5) or nil, h and math.floor(h + 0.5) or nil
end

-- All displays that are actually there: { index, handle, name, w, h }.
function MA.displays()
  local list, seen = {}, {}
  local function add(index, d)
    if d == nil or seen[index] then return end
    local w, h = MA.displaySize(d)
    if not w or not h or w <= 0 or h <= 0 then return end
    seen[index] = true
    list[#list + 1] = { index = index, handle = d, w = w, h = h,
                        name = MA.name(d) or ("Display " .. index) }
  end
  local okc, collect = pcall(GetDisplayCollect)
  if okc and collect then
    for i, d in ipairs(MA.children(collect)) do
      add(tonumber(MA.get(d, "Index")) or i, d)
    end
  end
  if #list == 0 then
    for i = 1, 16 do
      local ok, d = pcall(GetDisplayByIndex, i)
      if ok and d then add(i, d) end
    end
  end
  table.sort(list, function(a, b) return a.index < b.index end)
  return list
end

-- Appearances -----------------------------------------------------------------

function MA.appearancePool()
  for _, get in ipairs({
    function() return ShowData().Appearances end,
    function() return DataPool().Appearances end,
  }) do
    local ok, pool = pcall(get)
    if ok and pool then return pool end
  end
  return nil
end

-- ref: appearance number or name. Returns handle, label.
function MA.appearance(ref)
  ref = U.trim(ref)
  if ref == "" or ref == "0" then return nil end
  local pool = MA.appearancePool()
  if not pool then return nil end
  local n = tonumber(ref)
  if n then
    local ok, h = pcall(function() return pool[n] end)
    if ok and h then return h, string.format("%d %s", n, MA.name(h) or "") end
    for _, c in ipairs(MA.children(pool)) do
      if tonumber(MA.get(c, "No")) == n then return c, string.format("%d %s", n, MA.name(c) or "") end
    end
    return nil
  end
  local h = MA.findChild(pool, ref)
  if h then return h, (MA.get(h, "No") and (MA.get(h, "No") .. " ") or "") .. ref end
  return nil
end

-- The image an appearance carries (handle or name) and its size when known.
function MA.appearanceImage(app)
  if not app then return nil end
  for _, key in ipairs({ "MediaImage", "Image", "ImageRef", "Media" }) do
    local img = MA.get(app, key)
    if img ~= nil and img ~= "" then
      local w = tonumber(MA.get(img, "Width") or MA.get(img, "W") or MA.get(img, "ResolutionX"))
      local h = tonumber(MA.get(img, "Height") or MA.get(img, "H") or MA.get(img, "ResolutionY"))
      return img, w, h
    end
  end
  return nil
end

-- Users -----------------------------------------------------------------------

function MA.currentUser()
  local ok, u = pcall(CurrentUser)
  if ok and u then return u, MA.name(u) end
  return nil, nil
end

function MA.usersPool()
  local ok, pool = pcall(function() return ShowData().Users end)
  if ok then return pool end
  return nil
end

function MA.login(name, password)
  if password and password ~= "" then
    MA.cmd(string.format('Login "%s" "%s"', name, password))
  else
    MA.cmd(string.format('Login "%s"', name))
  end
  local _, now = MA.currentUser()
  return now ~= nil and now:lower() == tostring(name):lower()
end

-- Colours from the current theme (optional).
function MA.color(group, name)
  local ok, c = pcall(function() return Root().ColorTheme.ColorGroups[group][name] end)
  if ok then return c end
  return nil
end

-- Files -----------------------------------------------------------------------

-- Where templates can be written: internal library + any USB drive.
function MA.exportTargets()
  local targets = {}
  local okd, drives = pcall(function() return Root().Temp.DriveCollect end)
  if okd and drives then
    for i, d in ipairs(MA.children(drives)) do
      local path = MA.get(d, "Path")
      if path and path ~= "" and i > 1 then
        targets[#targets + 1] = { label = "Drive: " .. (MA.name(d) or path), path = path }
      end
    end
  end
  local lib
  for _, get in ipairs({
    function() return GetPath(Enums.PathType.Library) end,
    function() return GetPath("library") end,
    function() return GetPath("") end,
  }) do
    local ok, p = pcall(get)
    if ok and type(p) == "string" and p ~= "" then lib = p break end
  end
  if lib then table.insert(targets, 1, { label = "Internal: " .. lib, path = lib }) end
  return targets
end

function MA.mkdir(path)
  if pcall(CreateDirectoryRecursive, path) then return true end
  return false
end

function MA.writeFile(path, text)
  local f, err = io.open(path, "wb")
  if not f then return false, err end
  f:write(text)
  f:close()
  return true
end

--------------------------------------------------------------------------------
-- Settings stored in the show
--------------------------------------------------------------------------------
local Config = {}

local DEFAULTS = {
  mode = "pin",          -- "pin" or "tap" (showcase: tap anywhere to unlock)
  maxTries = 5,          -- wrong PINs before a cooldown
  cooldown = 30,         -- first cooldown in seconds, doubles every round
  padTimeout = 20,       -- PIN pad hides again after this many idle seconds
  padScreen = 0,         -- 0 = the screen you tap, else a display number
  tapToShow = true,      -- false = PIN pad always visible
  hardLock = true,       -- log in as a no-rights user while locked
  autoLock = false,      -- lock when the show loads
  showFails = true,      -- failed attempt counter on the lock screen
}

local SCREEN_DEFAULTS = { app = "", msg = "", clock = false, showMsg = false, pad = true }

function Config.load()
  local c = {}
  for k, v in pairs(DEFAULTS) do
    local raw = MA.getVar(k)
    if raw == nil or raw == "" then
      c[k] = v
    elseif type(v) == "boolean" then
      c[k] = U.toBool(raw)
    elseif type(v) == "number" then
      c[k] = tonumber(raw) or v
    else
      c[k] = tostring(raw)
    end
  end
  c.pinHash = MA.getVar("PinHash"); if c.pinHash == "" then c.pinHash = nil end
  c.adminHash = MA.getVar("AdminHash"); if c.adminHash == "" then c.adminHash = nil end
  c.salt = MA.getVar("PinSalt") or ""
  return c
end

function Config.save(c)
  for k, v in pairs(DEFAULTS) do
    local val = c[k]
    if type(v) == "boolean" then val = val and 1 or 0 end
    MA.setVar(k, val)
  end
end

function Config.screen(index)
  local s = {}
  for k, v in pairs(SCREEN_DEFAULTS) do
    local raw = MA.getVar("S" .. index .. "_" .. k)
    if raw == nil or raw == "" then
      s[k] = v
    elseif type(v) == "boolean" then
      s[k] = U.toBool(raw)
    else
      s[k] = tostring(raw)
    end
  end
  return s
end

-- Saves the fields in s; fields s leaves out keep their current value.
function Config.saveScreen(index, s)
  local current = Config.screen(index)
  for k, v in pairs(SCREEN_DEFAULTS) do
    local val = s[k]
    if val == nil then val = current[k] end
    if type(v) == "boolean" then val = val and 1 or 0 end
    MA.setVar("S" .. index .. "_" .. k, val == nil and "" or val)
  end
end

function Config.setPin(pin)
  local salt = MA.getVar("PinSalt")
  if salt == nil or salt == "" then salt = Hash.salt(); MA.setVar("PinSalt", salt) end
  MA.setVar("PinHash", Hash.pin(pin, salt))
end

function Config.setAdminPin(pin)
  if pin == nil then MA.setVar("AdminHash", nil) return end
  local salt = MA.getVar("PinSalt")
  if salt == nil or salt == "" then salt = Hash.salt(); MA.setVar("PinSalt", salt) end
  MA.setVar("AdminHash", Hash.pin("admin:" .. pin, salt))
end

-- "user", "admin" or nil
function Config.checkPin(c, pin)
  if pin == nil or pin == "" then return nil end
  if c.pinHash and Hash.pin(pin, c.salt) == c.pinHash then return "user" end
  if c.adminHash and Hash.pin("admin:" .. pin, c.salt) == c.adminHash then return "admin" end
  return nil
end

function Config.validPin(pin)
  pin = U.trim(pin)
  return pin:match("^%d%d%d%d%d?%d?%d?%d?$") ~= nil
end

--------------------------------------------------------------------------------
-- Screen geometry (shared by the lock screens and the templates)
--------------------------------------------------------------------------------
local Geo = {}

function Geo.padFits(w, h)
  return w >= SETTINGS.padWidth + 40 and h >= SETTINGS.padHeight + 40
end

-- Where the PIN pad sits on a w x h screen (top-left x, y, width, height).
function Geo.padRect(w, h)
  local pw, ph = SETTINGS.padWidth, SETTINGS.padHeight
  return math.floor((w - pw) / 2), math.floor((h - ph) / 2), pw, ph
end

-- Which screens may show the PIN pad. Makes sure at least one does.
function Geo.padScreens(screens, cfg)
  local ok = {}
  for _, s in ipairs(screens) do
    if s.cfg.pad and Geo.padFits(s.w, s.h) then ok[s.index] = true end
  end
  if cfg.padScreen and cfg.padScreen > 0 and ok[cfg.padScreen] then
    return { [cfg.padScreen] = true }, cfg.padScreen
  end
  local first
  for _, s in ipairs(screens) do if ok[s.index] then first = first or s.index end end
  if not first then
    -- No screen allowed / big enough: use the biggest one anyway.
    local best
    for _, s in ipairs(screens) do
      if not best or s.w * s.h > best.w * best.h then best = s end
    end
    if best then ok[best.index] = true; first = best.index end
  end
  return ok, first
end

--------------------------------------------------------------------------------
-- The lock
--------------------------------------------------------------------------------
local Lock = { state = nil }
local UI -- dialogs, defined further down
local L -- current lock state, nil when unlocked

local KEYS = { "1", "2", "3", "4", "5", "6", "7", "8", "9", "C", "0", "OK" }

local function now() return MA.clock() end

local function padVisibleOn(index)
  if not L or not L.padOk[index] then return false end
  if L.cfg.mode ~= "pin" then return false end
  if not L.cfg.tapToShow then return true end
  return L.padScreen == index and now() < L.padUntil
end

local function infoText(s)
  local parts = {}
  if s.cfg.showMsg and U.trim(s.cfg.msg) ~= "" then parts[#parts + 1] = s.cfg.msg end
  if s.cfg.clock then parts[#parts + 1] = os.date("%H:%M") end
  if L.cfg.showFails and L.fails > 0 then
    parts[#parts + 1] = string.format("%d failed unlock attempt%s", L.fails, L.fails == 1 and "" or "s")
  end
  if L.test then
    parts[#parts + 1] = string.format("TEST - unlocks in %d s", math.max(0, math.ceil(L.testUntil - now())))
  end
  return table.concat(parts, "     ")
end

local function entryText()
  if #L.entry == 0 then return "Enter PIN" end
  return string.rep("* ", #L.entry):sub(1, -2)
end

local function statusText()
  local wait = L.cooldownUntil - now()
  if wait > 0 then return string.format("Locked - try again in %d s", math.ceil(wait)) end
  return L.status or ""
end

-- Puts a picture from an appearance on a UI object. grandMA3 versions differ in
-- how a plugin UI object takes an image, so a few known ways are tried and the
-- first one the console keeps is used.
local function applyAppearance(obj, app)
  if not app then return "none" end
  if MA.set(obj, "Appearance", app) and MA.get(obj, "Appearance") ~= nil then return "Appearance" end
  local img = MA.appearanceImage(app)
  if img ~= nil then
    local imgName = type(img) == "string" and img or MA.name(img)
    for _, key in ipairs({ "Texture", "Icon" }) do
      for _, v in ipairs({ img, imgName }) do
        if v ~= nil and MA.set(obj, key, v) then
          local back = MA.get(obj, key)
          if back ~= nil and back ~= "" then return key end
        end
      end
    end
  end
  local col = MA.get(app, "Color") or MA.get(app, "BackColor")
  if col ~= nil and MA.set(obj, "BackColor", col) then return "Color" end
  return "failed"
end

local function styleLabel(obj, font)
  MA.set(obj, "HasHover", "No")
  MA.set(obj, "Focus", "Never")
  MA.set(obj, "TextalignmentH", "Centre")
  if font then MA.set(obj, "Font", font) end
  local t = MA.color("Global", "Transparent")
  if t then MA.set(obj, "BackColor", t) end
end

local function clickable(obj, handler)
  MA.set(obj, "PluginComponent", myHandle)
  MA.set(obj, "Clicked", handler)
end

-- Builds the full-screen lock overlay on one display.
local function buildScreen(s)
  local overlay = MA.get(s.handle, "ScreenOverlay")
  if not overlay then MA.err("display %d has no screen overlay", s.index) return false end
  pcall(function() overlay:ClearUIChildren() end)

  local ok, base = pcall(function() return overlay:Append("BaseInput") end)
  if not ok or not base then MA.err("could not cover display %d", s.index) return false end
  MA.set(base, "Name", OVERLAY_NAME)
  MA.set(base, "W", s.w)
  MA.set(base, "H", s.h)
  MA.set(base, "X", 0)
  MA.set(base, "Y", 0)
  MA.set(base, "MinSize", s.w .. "," .. s.h)
  MA.set(base, "MaxSize", s.w .. "," .. s.h)
  MA.set(base, "AutoClose", "No")
  MA.set(base, "CloseOnEscape", "No")
  MA.set(base, "Moveable", "No")
  MA.set(base, "Resizeable", "No")
  local black = MA.color("Global", "Background") or MA.color("Global", "Transparent")
  if black then MA.set(base, "BackColor", black) end

  -- 3 x 3 grid: the PIN pad sits in the fixed centre cell, the info line in
  -- the bottom row, the picture covers all nine cells underneath.
  local hasPad = L.padOk[s.index] and L.cfg.mode == "pin"
  local pw = hasPad and SETTINGS.padWidth or 0
  local ph = hasPad and SETTINGS.padHeight or 0
  MA.set(base, "Columns", 3)
  MA.set(base, "Rows", 3)
  pcall(function()
    base[1][1].SizePolicy = "Stretch"
    base[1][2].SizePolicy = "Fixed"; base[1][2].Size = tostring(ph)
    base[1][3].SizePolicy = "Stretch"
    base[2][1].SizePolicy = "Stretch"
    base[2][2].SizePolicy = "Fixed"; base[2][2].Size = tostring(pw)
    base[2][3].SizePolicy = "Stretch"
  end)

  local ui = { base = base }
  s.ui = ui

  -- Picture (also the "tap to wake" area)
  local bg = base:Append("Button")
  MA.set(bg, "Name", "DLBg_" .. s.index)
  MA.set(bg, "Anchors", { left = 0, right = 2, top = 0, bottom = 2 })
  MA.set(bg, "Text", "")
  MA.set(bg, "HasHover", "No")
  MA.set(bg, "Focus", "Never")
  clickable(bg, "DeskLockWake")
  s.imageMethod = applyAppearance(bg, s.app)
  if s.app and s.imageMethod == "failed" then
    MA.err("display %d: could not show appearance %s", s.index, tostring(s.appLabel))
  end
  ui.bg = bg

  -- Info line (clock / message / failed attempts)
  local info = base:Append("Button")
  MA.set(info, "Name", "DLInfo_" .. s.index)
  MA.set(info, "Anchors", { left = 0, right = 2, top = 2, bottom = 2 })
  MA.set(info, "TextalignmentV", "Bottom")
  MA.set(info, "H", SETTINGS.infoHeight)
  styleLabel(info, "Medium20")
  clickable(info, "DeskLockWake")
  ui.info = info
  ui.infoText = nil

  -- PIN pad
  if hasPad then
    local pad = base:Append("UILayoutGrid")
    MA.set(pad, "Name", "DLPad_" .. s.index)
    MA.set(pad, "Anchors", { left = 1, right = 1, top = 1, bottom = 1 })
    MA.set(pad, "Columns", 3)
    MA.set(pad, "Rows", 7)
    local bgc = MA.color("Global", "Background")
    if bgc then MA.set(pad, "BackColor", bgc) end
    pcall(function()
      pad[1][1].SizePolicy = "Fixed"; pad[1][1].Size = "56"
      pad[1][2].SizePolicy = "Fixed"; pad[1][2].Size = "64"
      for r = 3, 6 do pad[1][r].SizePolicy = "Stretch" end
      pad[1][7].SizePolicy = "Fixed"; pad[1][7].Size = "56"
    end)

    local title = pad:Append("Button")
    MA.set(title, "Name", "DLTitle_" .. s.index)
    MA.set(title, "Anchors", { left = 0, right = 2, top = 0, bottom = 0 })
    MA.set(title, "Text", "Desk locked")
    styleLabel(title, "Medium20")
    clickable(title, "DeskLockWake")

    local entry = pad:Append("Button")
    MA.set(entry, "Name", "DLEntry_" .. s.index)
    MA.set(entry, "Anchors", { left = 0, right = 2, top = 1, bottom = 1 })
    styleLabel(entry, "Medium20")
    clickable(entry, "DeskLockWake")
    ui.entry = entry

    for i, key in ipairs(KEYS) do
      local b = pad:Append("Button")
      local col, row = (i - 1) % 3, 2 + math.floor((i - 1) / 3)
      MA.set(b, "Name", "DLKey_" .. key .. "_" .. s.index)
      MA.set(b, "Text", key)
      MA.set(b, "Anchors", { left = col, right = col, top = row, bottom = row })
      MA.set(b, "Font", "Medium20")
      MA.set(b, "Margin", { left = 3, right = 3, top = 3, bottom = 3 })
      if key == "OK" then
        local please = MA.color("Button", "BackgroundPlease")
        if please then MA.set(b, "BackColor", please) end
      end
      clickable(b, "DeskLockKey")
    end

    local status = pad:Append("Button")
    MA.set(status, "Name", "DLStatus_" .. s.index)
    MA.set(status, "Anchors", { left = 0, right = 2, top = 6, bottom = 6 })
    styleLabel(status)
    clickable(status, "DeskLockWake")
    ui.status = status
    ui.pad = pad
  end

  s.built = true
  Lock.refreshScreen(s, true)
  MA.debug("display %d covered (%dx%d, picture: %s)", s.index, s.w, s.h, s.imageMethod)
  return true
end

local function setIfChanged(ui, key, obj, prop, value)
  if obj == nil then return end
  local cacheKey = key .. "." .. prop
  if ui[cacheKey] ~= value then
    ui[cacheKey] = value
    MA.set(obj, prop, value)
  end
end

function Lock.refreshScreen(s, force)
  local ui = s.ui
  if not ui then return end
  if force then for k in pairs(ui) do if type(k) == "string" and k:find("%.") then ui[k] = nil end end end
  setIfChanged(ui, "info", ui.info, "Text", infoText(s))
  if ui.pad then
    setIfChanged(ui, "pad", ui.pad, "Visible", padVisibleOn(s.index) and "Yes" or "No")
    setIfChanged(ui, "entry", ui.entry, "Text", entryText())
    setIfChanged(ui, "status", ui.status, "Text", statusText())
  end
end

-- Is our overlay still on this display?
local function overlayAlive(s)
  local overlay = MA.get(s.handle, "ScreenOverlay")
  if not overlay then return false end
  for _, c in ipairs(MA.children(overlay)) do
    if MA.name(c) == OVERLAY_NAME then return true end
  end
  return false
end

local function removeScreen(s)
  local overlay = MA.get(s.handle, "ScreenOverlay")
  if overlay then pcall(function() overlay:ClearUIChildren() end) end
  s.ui, s.built = nil, false
end

-- Builds the screen list. only: limit to one display (preview).
local function collectScreens(only)
  local screens = {}
  for _, d in ipairs(MA.displays()) do
    if not only or d.index == only then
      local sc = Config.screen(d.index)
      local app, label = MA.appearance(sc.app)
      screens[#screens + 1] = {
        index = d.index, handle = d.handle, name = d.name, w = d.w, h = d.h,
        cfg = sc, app = app, appLabel = label or sc.app,
      }
    end
  end
  return screens
end

-- Covers every display, and new ones that turn up while locked.
function Lock.sync()
  local fresh = collectScreens(L.only)
  local byIndex = {}
  for _, s in ipairs(L.screens) do byIndex[s.index] = s end
  local changed = false
  for _, f in ipairs(fresh) do
    local s = byIndex[f.index]
    if not s or s.w ~= f.w or s.h ~= f.h then
      if s then f.ui = nil end
      byIndex[f.index] = f
      changed = true
    end
  end
  if changed then
    local list = {}
    for _, s in pairs(byIndex) do list[#list + 1] = s end
    table.sort(list, function(a, b) return a.index < b.index end)
    L.screens = list
    L.padOk, L.firstPad = Geo.padScreens(L.screens, L.cfg)
  end
  for _, s in ipairs(L.screens) do
    if not s.built or not overlayAlive(s) then
      if s.built then MA.log("display %d was uncovered - covering it again", s.index) end
      buildScreen(s)
    end
  end
end

-- Hard lock: log in as a user without rights -------------------------------

local Hard = {}

function Hard.lockUser(profile)
  local pool = MA.usersPool()
  if not pool then return nil end
  local u = MA.findChild(pool, SETTINGS.lockUserName)
  if not u then
    for _, make in ipairs({
      function() return pool:Acquire() end,
      function() return pool:Append() end,
      function() return pool:Append("User") end,
    }) do
      local ok, h = pcall(make)
      if ok and h then u = h break end
    end
    if not u then
      MA.cmd(string.format('Store User "%s"', SETTINGS.lockUserName))
      u = MA.findChild(pool, SETTINGS.lockUserName)
    end
    if not u then return nil end
    MA.set(u, "Name", SETTINGS.lockUserName)
  end
  MA.set(u, "Rights", "None")
  MA.set(u, "Password", "")
  if profile then MA.set(u, "Profile", profile) end
  local rights = tostring(MA.get(u, "Rights") or "")
  if rights ~= "" and rights:lower() ~= "none" then
    MA.err("lock user rights are '%s', not 'None'", rights)
    return nil
  end
  return u
end

function Hard.engage()
  local user, name = MA.currentUser()
  if not user or not name then return nil, "can't read the current user" end
  if name:lower() == SETTINGS.lockUserName:lower() then
    -- Already the lock user (desk locked before a reboot). Keep the user we
    -- have to go back to from the last lock.
    local back = MA.getVar("ReturnUser")
    if back and back ~= "" then return { user = back } end
    return nil, "already logged in as the lock user, but don't know who to go back to"
  end
  local profile = MA.get(user, "Profile")
  if not Hard.lockUser(profile) then return nil, "can't set up the lock user" end
  MA.setVar("ReturnUser", name)
  if not MA.login(SETTINGS.lockUserName) then
    return nil, "login as the lock user didn't work"
  end
  MA.log("hard lock on: logged in as %s (no rights), back to %s on unlock", SETTINGS.lockUserName, name)
  return { user = name }
end

-- Logs back in. Asks for the user's password when it has one.
function Hard.release(h)
  if MA.login(h.user) then return true end
  for _ = 1, 3 do
    local ok, pw = pcall(TextInput, string.format("Password for user %s", h.user), "")
    if not ok or pw == nil then break end
    if MA.login(h.user, pw) then return true end
  end
  return false
end

-- Lock life cycle -----------------------------------------------------------

-- opts: test = true (unlocks itself), preview = display index, reason = text
function Lock.start(opts)
  opts = opts or {}
  if L then return false, "already locked" end
  local cfg = Config.load()
  if cfg.mode == "pin" and not cfg.pinHash and not opts.preview then
    return false, "no PIN set"
  end

  L = {
    cfg = cfg, screens = {}, padOk = {}, entry = "", fails = 0, rounds = 0,
    cooldownUntil = 0, padUntil = 0, padScreen = nil, status = "",
    test = opts.test or opts.preview ~= nil, only = opts.preview,
    started = now(), lastWatch = now(), release = false,
  }
  L.testUntil = L.started + (opts.preview and SETTINGS.previewSeconds or SETTINGS.testSeconds)
  if opts.preview then L.cfg.mode = "pin"; L.cfg.tapToShow = false end
  Lock.state = L

  if not L.test then MA.setVar("Locked", 1) end

  if cfg.hardLock and not opts.preview then
    local h, why = Hard.engage()
    if h then L.hard = h
    else MA.err("hard lock not available (%s) - touch is locked, keys are not", tostring(why)) end
  end

  Lock.sync()
  if #L.screens == 0 then
    MA.err("no displays found to lock")
  end
  MA.log("%s (%d screen%s)", L.test and "test lock" or "desk locked", #L.screens, #L.screens == 1 and "" or "s")
  return true
end

-- One update step. Returns false once the desk is unlocked.
function Lock.tick()
  if not L then return false end
  local t = now()
  if L.test and t >= L.testUntil then L.release = true end
  if L.release then Lock.finish() return false end

  if L.cfg.tapToShow and L.padScreen and t >= L.padUntil then
    L.padScreen, L.entry, L.status = nil, "", ""
  end

  if t - L.lastWatch >= 1 then
    L.lastWatch = t
    Lock.sync()
    if L.hard then
      local _, name = MA.currentUser()
      if name and name:lower() ~= SETTINGS.lockUserName:lower() then
        MA.log("user changed to %s while locked - locking again", name)
        MA.login(SETTINGS.lockUserName)
      end
    end
  end
  for _, s in ipairs(L.screens) do Lock.refreshScreen(s) end
  return true
end

function Lock.finish()
  local state = L
  L, Lock.state = nil, nil
  for _, s in ipairs(state.screens) do removeScreen(s) end
  if state.hard then
    if not Hard.release(state.hard) then
      MA.err("could not log back in as %s - type  Login \"%s\"  on the command line",
        state.hard.user, state.hard.user)
      UI.message(TITLE, string.format("Unlocked, but still logged in as %s (no rights).\n"
        .. "Type  Login \"%s\"  on the command line to get your rights back.",
        SETTINGS.lockUserName, state.hard.user))
    end
  end
  if not state.test then
    MA.setVar("Locked", 0)
    MA.log("desk unlocked%s", state.unlockedBy == "admin" and " with the master PIN" or "")
  end
  if state.fails > 0 and not state.test then
    pcall(MessageBox, {
      title = TITLE,
      message = string.format("%d wrong PIN%s entered while the desk was locked.\nLast one: %s",
        state.fails, state.fails == 1 and " was" or "s were", tostring(state.lastFail)),
      commands = { { value = 1, name = "OK" } },
    })
  end
end

-- Wakes the PIN pad on the screen that was touched.
function Lock.wake(index)
  if not L then return end
  if L.cfg.mode == "tap" then L.release = true return end
  local target = index
  if not L.padOk[target] then target = L.firstPad end
  if L.cfg.padScreen and L.cfg.padScreen > 0 and L.padOk[L.cfg.padScreen] then target = L.cfg.padScreen end
  L.padScreen = target
  L.padUntil = now() + L.cfg.padTimeout
end

function Lock.key(key, index)
  if not L then return end
  Lock.wake(index)
  if L.release then return end
  if key == "C" then
    L.entry, L.status = "", ""
  elseif key == "OK" then
    Lock.submit()
  elseif key:match("^%d$") then
    if now() < L.cooldownUntil then return end
    if #L.entry < 8 then L.entry = L.entry .. key end
    L.status = ""
  end
end

function Lock.submit()
  local t = now()
  if t < L.cooldownUntil then L.entry = "" return end
  local who = Config.checkPin(L.cfg, L.entry)
  if L.only and not L.cfg.pinHash and #L.entry > 0 then who = "user" end -- preview without PIN
  L.entry = ""
  if who then
    L.unlockedBy = who
    L.release = true
    return
  end
  L.fails = L.fails + 1
  L.lastFail = os.date("%Y-%m-%d %H:%M:%S")
  L.status = "Wrong PIN"
  if not L.test then
    MA.setVar("FailCount", (tonumber(MA.getVar("FailCount")) or 0) + 1)
    MA.setVar("LastFail", L.lastFail)
  end
  MA.log("wrong PIN entered (%d)", L.fails)
  if L.fails % math.max(1, L.cfg.maxTries) == 0 then
    L.rounds = L.rounds + 1
    local wait = math.min(SETTINGS.maxCooldown, L.cfg.cooldown * 2 ^ (L.rounds - 1))
    L.cooldownUntil = t + math.floor(wait)
  end
end

-- Runs the lock until it is unlocked. Waits with coroutine.yield.
function Lock.run(opts)
  local ok, why = Lock.start(opts)
  if not ok then return false, why end
  while Lock.tick() do
    if not MA.sleep(SETTINGS.tick) then
      -- No coroutine to wait in: the button handlers drive the lock, and a
      -- timer keeps the clock and the watchdog going where there is one.
      L.noLoop = true
      pcall(Timer, function() if L then Lock.tick() end end, 1, 1000000)
      return true
    end
  end
  return true
end

-- Button handlers (called by the console) -----------------------------------

local function displayOf(caller)
  local name = MA.name(caller) or ""
  return tonumber(name:match("_(%d+)$"))
end

local function afterClick()
  if L and L.noLoop then Lock.tick() end
end

signalTable.DeskLockWake = function(caller)
  Lock.wake(displayOf(caller))
  afterClick()
end

signalTable.DeskLockKey = function(caller)
  local name = MA.name(caller) or ""
  local key = name:match("^DLKey_(%w+)_%d+$")
  if key then Lock.key(key, displayOf(caller)) end
  afterClick()
end

--------------------------------------------------------------------------------
-- Screen sizes and content templates
--------------------------------------------------------------------------------
local Templates = {}

function Templates.rows()
  local cfg = Config.load()
  local screens = collectScreens()
  local padOk = Geo.padScreens(screens, cfg)
  local rows = {}
  for _, s in ipairs(screens) do
    local imgW, imgH
    if s.app then
      local _, iw, ih = MA.appearanceImage(s.app)
      imgW, imgH = iw, ih
    end
    rows[#rows + 1] = {
      index = s.index, name = s.name, w = s.w, h = s.h, aspect = U.aspect(s.w, s.h),
      pad = padOk[s.index] == true and cfg.mode == "pin", app = s.appLabel ~= "" and s.appLabel or nil,
      appMissing = s.cfg.app ~= "" and not s.app, imgW = imgW, imgH = imgH, cfg = s.cfg,
    }
  end
  return rows
end

function Templates.report(rows)
  local lines = { "Make each picture EXACTLY this size (pixels):", "" }
  for _, r in ipairs(rows) do
    lines[#lines + 1] = string.format("Display %d  %-14s %5d x %-5d  (%s)%s",
      r.index, r.name, r.w, r.h, r.aspect, r.pad and "  + PIN pad" or "")
    if r.app then
      local note = ""
      if r.appMissing then
        note = "  <- appearance not found"
      elseif r.imgW and r.imgH then
        if r.imgW == r.w and r.imgH == r.h then note = "  image size OK"
        else note = string.format("  <- image is %dx%d", r.imgW, r.imgH) end
      end
      lines[#lines + 1] = "           picture: appearance " .. r.app .. note
    end
  end
  if #rows == 0 then lines[#lines + 1] = "No displays found." end
  lines[#lines + 1] = ""
  lines[#lines + 1] = string.format("PIN pad: %d x %d px in the centre of the PIN pad screen.",
    SETTINGS.padWidth, SETTINGS.padHeight)
  lines[#lines + 1] = "Sizes are read from this desk / onPC. Run this on the desk you lock."
  return table.concat(lines, "\n")
end

function Templates.csv(rows)
  local out = { "display,name,width_px,height_px,aspect,pin_pad,pad_x,pad_y,pad_w,pad_h,appearance" }
  for _, r in ipairs(rows) do
    local x, y, w, h = "", "", "", ""
    if r.pad then x, y, w, h = Geo.padRect(r.w, r.h) end
    out[#out + 1] = string.format('%d,"%s",%d,%d,%s,%s,%s,%s,%s,%s,"%s"',
      r.index, r.name, r.w, r.h, r.aspect, r.pad and "yes" or "no", x, y, w, h, r.app or "")
  end
  return table.concat(out, "\n") .. "\n"
end

-- An SVG at the exact screen size with guides on their own layer.
function Templates.svg(r)
  local w, h = r.w, r.h
  local s = {}
  local function add(fmt, ...) s[#s + 1] = string.format(fmt, ...) end
  local fs = math.max(12, math.floor(math.min(w, h) / 18))
  add('<?xml version="1.0" encoding="UTF-8"?>')
  add('<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%d" viewBox="0 0 %d %d">', w, h, w, h)
  add('  <title>Display %d %s - %d x %d px</title>', r.index, U.xmlEscape(r.name), w, h)
  add('  <g id="artwork">')
  add('    <rect x="0" y="0" width="%d" height="%d" fill="#101418"/>', w, h)
  add('  </g>')
  add('  <g id="guides" fill="none" stroke-width="1">')
  add('    <rect x="0.5" y="0.5" width="%d" height="%d" stroke="#ff3b30"/>', w - 1, h - 1)
  local mx, my = math.floor(w * 0.05), math.floor(h * 0.05)
  add('    <rect x="%d.5" y="%d.5" width="%d" height="%d" stroke="#ffcc00" stroke-dasharray="8 6"/>',
    mx, my, w - 2 * mx - 1, h - 2 * my - 1)
  add('    <line x1="%d" y1="0" x2="%d" y2="%d" stroke="#3a7bd5"/>', math.floor(w / 2), math.floor(w / 2), h)
  add('    <line x1="0" y1="%d" x2="%d" y2="%d" stroke="#3a7bd5"/>', math.floor(h / 2), w, math.floor(h / 2))
  if r.pad then
    local x, y, pw, ph = Geo.padRect(w, h)
    add('    <rect x="%d" y="%d" width="%d" height="%d" fill="#ff3b30" fill-opacity="0.18" stroke="#ff3b30" stroke-dasharray="10 6"/>',
      x, y, pw, ph)
    add('    <text x="%d" y="%d" fill="#ff3b30" stroke="none" font-family="sans-serif" font-size="%d" text-anchor="middle">PIN pad %dx%d</text>',
      math.floor(w / 2), y + ph + math.floor(fs * 1.2), math.floor(fs * 0.6), pw, ph)
  end
  if r.cfg and (r.cfg.clock or r.cfg.showMsg) then
    local ih = math.min(SETTINGS.infoHeight, h)
    add('    <rect x="0" y="%d" width="%d" height="%d" fill="#ffffff" fill-opacity="0.10" stroke="#ffffff" stroke-dasharray="4 4"/>',
      h - ih, w, ih)
  end
  add('    <text x="%d" y="%d" fill="#ffffff" stroke="none" font-family="sans-serif" font-size="%d" text-anchor="middle">Display %d - %d x %d px</text>',
    math.floor(w / 2), math.floor(h / 2) - math.floor(fs * 0.6), fs, r.index, w, h)
  add('    <text x="%d" y="%d" fill="#ffffff" stroke="none" font-family="sans-serif" font-size="%d" text-anchor="middle">%s (%s)</text>',
    math.floor(w / 2), math.floor(h / 2) + fs, math.floor(fs * 0.6), U.xmlEscape(r.name), r.aspect)
  add('  </g>')
  add('</svg>')
  return table.concat(s, "\n") .. "\n"
end

function Templates.fileName(r)
  return string.format("Display%d_%s_%dx%d.svg", r.index, U.fileSafe(r.name), r.w, r.h)
end

function Templates.export(dir)
  local rows = Templates.rows()
  local sep = dir:find("\\", 1, true) and "\\" or "/"
  local folder = dir:gsub("[/\\]+$", "") .. sep .. "desklock_templates"
  if not MA.mkdir(folder) then
    local probe = io.open(folder .. sep .. ".probe", "wb")
    if probe then probe:close(); pcall(os.remove, folder .. sep .. ".probe")
    else folder = dir:gsub("[/\\]+$", "") end
  end
  local written = {}
  local ok, err = MA.writeFile(folder .. sep .. "screens.csv", Templates.csv(rows))
  if not ok then return nil, err end
  written[#written + 1] = "screens.csv"
  MA.writeFile(folder .. sep .. "screens.txt", Templates.report(rows) .. "\n")
  written[#written + 1] = "screens.txt"
  for _, r in ipairs(rows) do
    local name = Templates.fileName(r)
    if MA.writeFile(folder .. sep .. name, Templates.svg(r)) then written[#written + 1] = name end
  end
  return folder, written
end

--------------------------------------------------------------------------------
-- Dialogs
--------------------------------------------------------------------------------
UI = {}

local function focusDisplay()
  local ok, d = pcall(GetFocusDisplay)
  if ok then return d end
  return nil
end

function UI.message(title, text)
  pcall(MessageBox, { title = title, message = text, commands = { { value = 1, name = "OK" } } })
end

function UI.ask(title, text, yes, no)
  local ok, res = pcall(MessageBox, {
    title = title, message = text,
    commands = { { value = 1, name = yes or "Yes" }, { value = 0, name = no or "Cancel" } },
  })
  return ok and type(res) == "table" and res.result == 1
end

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

-- fields: { key, label, type = "int" | "text" | "pin" | "bool" }
function UI.form(title, message, fields, values, buttons)
  local inputs, states, labels = {}, {}, {}
  local n = 0
  for _, f in ipairs(fields) do
    if f.type == "bool" then
      states[#states + 1] = { name = f.label, state = U.toBool(values[f.key]) }
    else
      n = n + 1
      local label = string.format("%d %s", n, f.label)
      labels[f.key] = label
      local input = { name = label, value = tostring(values[f.key] == nil and "" or values[f.key]) }
      if f.type == "int" or f.type == "pin" then
        input.whiteFilter = "0123456789"
        input.vkPlugin = "TextInputNumOnly"
      end
      if f.type == "pin" then input.maxTextLength = 8 end
      inputs[#inputs + 1] = input
    end
  end
  local spec = {
    title = title, message = message,
    commands = buttons or { { value = 1, name = "OK" }, { value = 0, name = "Cancel" } },
    inputs = (#inputs > 0) and inputs or nil,
    states = (#states > 0) and states or nil,
  }
  local ok, res = pcall(MessageBox, spec)
  if not ok then
    for _, input in ipairs(inputs) do input.whiteFilter, input.vkPlugin, input.maxTextLength = nil, nil, nil end
    ok, res = pcall(MessageBox, spec)
  end
  if not ok or type(res) ~= "table" or not res.result or res.result == 0 then return nil end
  local out = {}
  for k, v in pairs(values) do out[k] = v end
  for _, f in ipairs(fields) do
    if f.type == "bool" then
      local v = res.states and res.states[f.label]
      if v ~= nil then out[f.key] = U.toBool(v) end
    else
      local v = res.inputs and res.inputs[labels[f.key]]
      if v ~= nil then out[f.key] = (f.type == "int") and tonumber(v) or U.trim(v) end
    end
  end
  return out, res.result
end

-- Asks for the current PIN before settings can change. true when OK.
local function confirmPin(cfg, why)
  if not cfg.pinHash then return true end
  local ok, pin = pcall(TextInput, why or "Current PIN", "")
  if not ok or pin == nil then return false end
  if Config.checkPin(cfg, U.trim(pin)) then return true end
  UI.message(TITLE, "Wrong PIN.")
  return false
end

-- PIN & security ------------------------------------------------------------

local function securityDialog()
  local cfg = Config.load()
  if not confirmPin(cfg, "Current PIN (to change settings)") then return end
  local values = {
    newPin = "", repeatPin = "", adminPin = "",
    maxTries = cfg.maxTries, cooldown = cfg.cooldown, padTimeout = cfg.padTimeout, padScreen = cfg.padScreen,
    hardLock = cfg.hardLock, autoLock = cfg.autoLock, showFails = cfg.showFails,
    tapToShow = cfg.tapToShow, tapMode = cfg.mode == "tap",
  }
  local message = (cfg.pinHash and "A PIN is set. Leave the PIN fields empty to keep it." or "No PIN set yet.")
    .. "\nPIN: 4 to 8 digits. Master PIN: 0 removes it."
    .. "\nHard lock logs in as a no-rights user while locked, so keys, faders and encoders do nothing."
  local fields = {
    { key = "newPin",     label = "New PIN",                          type = "pin" },
    { key = "repeatPin",  label = "Repeat new PIN",                   type = "pin" },
    { key = "adminPin",   label = "Master PIN (optional)",            type = "pin" },
    { key = "maxTries",   label = "Wrong PINs before cooldown",       type = "int" },
    { key = "cooldown",   label = "Cooldown seconds (doubles)",       type = "int" },
    { key = "padTimeout", label = "PIN pad hides after (s)",          type = "int" },
    { key = "padScreen",  label = "PIN pad screen (0 = tapped one)",  type = "int" },
    { key = "hardLock",   label = "Hard lock (block keys + faders)",  type = "bool" },
    { key = "autoLock",   label = "Auto-lock when the show loads",    type = "bool" },
    { key = "showFails",  label = "Show failed attempts",             type = "bool" },
    { key = "tapToShow",  label = "Tap screen to show PIN pad",       type = "bool" },
    { key = "tapMode",    label = "No PIN - tap unlocks (showcase)",  type = "bool" },
  }
  while true do
    local v = UI.form(TITLE .. " - PIN & security", message, fields, values)
    if not v then return end
    values = v
    local problem
    if v.newPin ~= "" or v.repeatPin ~= "" then
      if not Config.validPin(v.newPin) then problem = "The PIN must be 4 to 8 digits."
      elseif v.newPin ~= v.repeatPin then problem = "The two PINs are not the same." end
    elseif not cfg.pinHash and not v.tapMode then
      problem = "Set a PIN (or switch on showcase mode)."
    end
    if not problem and v.adminPin ~= "" and v.adminPin ~= "0" and not Config.validPin(v.adminPin) then
      problem = "The master PIN must be 4 to 8 digits."
    end
    if not problem and v.adminPin ~= "" and v.adminPin == v.newPin then
      problem = "The master PIN must differ from the PIN."
    end
    if not problem then
      if v.newPin ~= "" then Config.setPin(v.newPin) end
      if v.adminPin == "0" then Config.setAdminPin(nil)
      elseif v.adminPin ~= "" then Config.setAdminPin(v.adminPin) end
      cfg.maxTries   = U.clamp(v.maxTries, 1, 99)
      cfg.cooldown   = U.clamp(v.cooldown, 0, SETTINGS.maxCooldown)
      cfg.padTimeout = U.clamp(v.padTimeout, 5, 600)
      cfg.padScreen  = U.clamp(v.padScreen, 0, 99)
      cfg.hardLock, cfg.autoLock, cfg.showFails = v.hardLock, v.autoLock, v.showFails
      cfg.tapToShow = v.tapToShow
      cfg.mode = v.tapMode and "tap" or "pin"
      Config.save(cfg)
      UI.message(TITLE, "Saved." .. (cfg.autoLock and "\nThe desk will lock every time this show loads." or ""))
      return
    end
    UI.message(TITLE .. " - check", problem)
  end
end

-- Screens -------------------------------------------------------------------

local function screenLabel(d)
  local sc = Config.screen(d.index)
  local app = sc.app ~= "" and ("appearance " .. sc.app) or "no picture"
  return string.format("Display %d  %dx%d  -  %s", d.index, d.w, d.h, app)
end

local function previewScreen(index)
  local ok, why = Lock.run({ preview = index })
  if not ok then UI.message(TITLE, "Preview not possible: " .. tostring(why)) end
end

local function screenDialog(d)
  local sc = Config.screen(d.index)
  local fits = Geo.padFits(d.w, d.h)
  local fields = {
    { key = "app",     label = "Appearance (no. or name)", type = "text" },
    { key = "msg",     label = "Message text",            type = "text" },
    { key = "showMsg", label = "Show message",            type = "bool" },
    { key = "clock",   label = "Show clock",              type = "bool" },
  }
  if fits then fields[#fields + 1] = { key = "pad", label = "PIN pad may show here", type = "bool" } end
  local message = string.format("Display %d - %s\nPicture size: %d x %d px (%s)%s\nEmpty appearance = black screen.",
    d.index, d.name, d.w, d.h, U.aspect(d.w, d.h), fits and "" or "\nToo small for the PIN pad.")
  local v, button = UI.form(TITLE .. " - display " .. d.index, message, fields, sc, {
    { value = 1, name = "Save" }, { value = 2, name = "Save + preview" }, { value = 0, name = "Cancel" },
  })
  if not v then return end
  if v.app ~= "" and not MA.appearance(v.app) then
    UI.message(TITLE, "Appearance '" .. v.app .. "' was not found. Saved anyway.")
  end
  Config.saveScreen(d.index, v)
  if button == 2 then previewScreen(d.index) end
end

local function screensMenu()
  while true do
    local displays = MA.displays()
    if #displays == 0 then return UI.message(TITLE, "No displays found.") end
    local items = {}
    for i, d in ipairs(displays) do items[i] = screenLabel(d) end
    items[#items + 1] = "Same appearance on every screen"
    items[#items + 1] = "Consecutive appearances (first no. -> display 1, next -> 2 ...)"
    local choice = UI.choose(TITLE .. " - pictures per screen", items)
    if not choice then return end
    if choice == items[#items - 1] or choice == items[#items] then
      local same = choice == items[#items - 1]
      local v = UI.form(TITLE, same and "Appearance for every screen" or "First appearance number",
        { { key = "app", label = same and "Appearance (no. or name)" or "First appearance no.", type = same and "text" or "int" } },
        { app = "" })
      if v and U.trim(v.app) ~= "" then
        local first = tonumber(v.app)
        for i, d in ipairs(displays) do
          local sc = Config.screen(d.index)
          sc.app = same and tostring(v.app) or tostring((first or 1) + i - 1)
          Config.saveScreen(d.index, sc)
        end
      end
    else
      for i, d in ipairs(displays) do
        if items[i] == choice then screenDialog(d) break end
      end
    end
  end
end

local function sizesDialog()
  local rows = Templates.rows()
  local text = Templates.report(rows)
  MA.log("screen sizes:\n%s", text)
  local ok, res = pcall(MessageBox, {
    title = TITLE .. " - screen sizes", message = text,
    commands = { { value = 2, name = "Export templates" }, { value = 1, name = "OK" } },
  })
  if ok and type(res) == "table" and res.result == 2 then return "export" end
end

local function exportDialog()
  local targets = MA.exportTargets()
  if #targets == 0 then return UI.message(TITLE, "No folder to write to was found.") end
  local target = targets[1]
  if #targets > 1 then
    local items = {}
    for i, t in ipairs(targets) do items[i] = t.label end
    local choice = UI.choose(TITLE .. " - export to", items)
    if not choice then return end
    for i, t in ipairs(targets) do if items[i] == choice then target = t end end
  end
  local folder, written = Templates.export(target.path)
  if not folder then return UI.message(TITLE, "Export failed: " .. tostring(written)) end
  MA.log("templates written to %s", folder)
  UI.message(TITLE, "Written to\n" .. folder .. "\n\n" .. table.concat(written, "\n")
    .. "\n\nOpen the SVGs in Photoshop / Illustrator / Affinity / Figma: each one is exactly the screen size."
    .. " Hide the 'guides' layer before you export your PNG.")
end

local function historyDialog()
  local count = tonumber(MA.getVar("FailCount")) or 0
  local last = MA.getVar("LastFail")
  local text = string.format("Wrong PINs since last reset: %d", count)
  if last and last ~= "" then text = text .. "\nLast one: " .. last end
  if UI.ask(TITLE .. " - unlock history", text, "Reset", "Close") then
    MA.setVar("FailCount", 0)
    MA.setVar("LastFail", nil)
  end
end

local HELP_TEXT = [[
1. Screen sizes: shows the exact pixel size of every screen. Export templates
   writes an SVG per screen at that size (PIN pad area marked) + screens.csv.
2. Make one picture per screen at exactly that size, import it to the Images
   pool and put it in an appearance.
3. Pictures per screen: give every display its appearance. Save + preview
   shows it for a few seconds.
4. PIN & security: set a PIN (4-8 digits), optional master PIN, hard lock,
   auto-lock on show load.
5. Lock desk now. Tap any screen, enter the PIN, OK.

One-press lock: put  Plugin "DeskLock" "lock"  in a macro.
Hard lock logs in as user "DeskLock" (no rights) and back in as you on
unlock; if your user has a password you'll be asked for it.
A desk that was locked stays locked after a reboot or show reload.
Try Test lock first: it unlocks itself after 30 s.]]

--------------------------------------------------------------------------------
-- Main
--------------------------------------------------------------------------------
local function lockNow(test)
  local cfg = Config.load()
  if cfg.mode == "pin" and not cfg.pinHash then
    UI.message(TITLE, "Set a PIN first.")
    securityDialog()
    cfg = Config.load()
    if cfg.mode == "pin" and not cfg.pinHash then return end
  end
  local ok, why = Lock.run({ test = test })
  if not ok then UI.message(TITLE, "Can't lock: " .. tostring(why)) end
end

local function menu()
  while true do
    local cfg = Config.load()
    local status = cfg.mode == "tap" and "showcase (no PIN)" or (cfg.pinHash and "PIN set" or "no PIN yet")
    local items = {
      "Lock desk now",
      string.format("Test lock (unlocks itself after %d s)", SETTINGS.testSeconds),
      "Screen sizes (pixel size for your pictures)",
      "Export content templates (SVG + size list)",
      "Pictures per screen (appearances)",
      "PIN & security",
      "Unlock history",
      "Help",
    }
    local choice = UI.choose(string.format("%s %s - %s%s%s", TITLE, VERSION, status,
      cfg.hardLock and ", hard lock" or "", cfg.autoLock and ", auto-lock" or ""), items)
    if not choice then return end
    if choice == items[1] then return lockNow(false)
    elseif choice == items[2] then lockNow(true)
    elseif choice == items[3] then if sizesDialog() == "export" then exportDialog() end
    elseif choice == items[4] then exportDialog()
    elseif choice == items[5] then screensMenu()
    elseif choice == items[6] then securityDialog()
    elseif choice == items[7] then historyDialog()
    elseif choice == items[8] then UI.message(TITLE .. " - help", HELP_TEXT)
    end
  end
end

-- Should the desk lock straight away (auto-lock, or locked before a reboot)?
local function pendingLock()
  local cfg = Config.load()
  if cfg.mode == "pin" and not cfg.pinHash then return false end
  -- Set by the auto-lock a moment ago (ignored when it is stale).
  local t = tonumber(MA.getVar("AutoPending")) or 0
  return t > 0 and math.abs(now() - t) <= 120
end

local function Main(displayHandle, argument)
  local arg = U.trim(argument):lower()
  if L then return end -- already locked (second call while the lock runs)
  if pendingLock() then
    MA.setVar("AutoPending", 0)
    return Lock.run({ reason = "auto" })
  end
  if arg == "lock" then return lockNow(false) end
  if arg == "test" then return lockNow(true) end
  if arg == "sizes" then if sizesDialog() == "export" then exportDialog() end return end
  return menu()
end

--------------------------------------------------------------------------------
-- Auto-lock: the plugin is loaded with the show. If auto-lock is on, or the
-- desk was locked when the show was saved / the desk went down, start the
-- plugin a moment later so it locks.
--------------------------------------------------------------------------------
local function pluginAddress()
  local ok, parent = pcall(function() return myHandle:Parent() end)
  if ok and parent then
    local okA, addr = pcall(function() return parent:ToAddr() end)
    if okA and addr and addr ~= "" then return addr end
  end
  return string.format('Plugin "%s"', tostring(pluginName or TITLE))
end

local function armAutoLock()
  if L then return end
  local cfg = Config.load()
  if cfg.mode == "pin" and not cfg.pinHash then return end
  local _, user = MA.currentUser()
  local wasLocked = MA.getVar("Locked") == "1"
    or (user ~= nil and user:lower() == SETTINGS.lockUserName:lower())
  if not cfg.autoLock and not wasLocked then return end
  MA.setVar("AutoPending", now())
  MA.log("%s - locking", wasLocked and "desk was locked" or "auto-lock is on")
  MA.cmd(pluginAddress())
end

if type(DESKLOCK_TEST_HOOK) ~= "table" then
  pcall(function()
    if type(Timer) == "function" then
      Timer(armAutoLock, SETTINGS.autoLockDelay, 1)
    end
  end)
end

-- Test hook: lets the offline test suite reach the internals. Never set on a console.
if type(DESKLOCK_TEST_HOOK) == "table" then
  local H = DESKLOCK_TEST_HOOK
  H.U, H.Hash, H.MA, H.Config, H.Geo, H.Lock, H.Templates, H.SETTINGS = U, Hash, MA, Config, Geo, Lock, Templates, SETTINGS
  H.armAutoLock, H.signalTable = armAutoLock, signalTable
  H.state = function() return L end
end

return Main
