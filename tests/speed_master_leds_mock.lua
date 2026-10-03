-- Minimal grandMA3 stand-in for running Speed Master LEDs offline.
-- It models the hardware modules (SetLED / GetButton), a clock, speed masters,
-- the executors of the current page and scripted dialogs.
--
-- Every SetLED call is checked against the LED table from the grandMA3 manual
-- (tests/fixtures): a value of 0 or more on an index with no LED on that module
-- is recorded as a violation.

local M = {}

local function splitTsv(line)
  local out = {}
  for cell in (line .. "\t"):gmatch("([^\t]*)\t") do out[#out + 1] = cell end
  return out
end

function M.readTsv(path)
  local rows = {}
  local first = true
  for line in io.lines(path) do
    if first then first = false else rows[#rows + 1] = splitTsv(line) end
  end
  return rows
end

M.LED_ROWS = M.readTsv("tests/fixtures/ma3_setled_table.tsv")
M.BUTTON_ROWS = M.readTsv("tests/fixtures/ma3_getbutton_table.tsv")

-- LED names per module type, by index.
local LED_COL = { MM = 2, MFE = 3, MFX = 4 }
M.LED_NAMES = { MM = {}, MFE = {}, MFX = {} }
for _, r in ipairs(M.LED_ROWS) do
  local idx = tonumber(r[1])
  for t, col in pairs(LED_COL) do
    local name = r[col]
    if name and name ~= "" then M.LED_NAMES[t][idx] = name end
  end
end

-- Button names per module type, by 1-based index.
local BUTTON_COL = { MM = 3, MFE = 4, MFX = 5 }
M.BUTTON_NAMES = { MM = {}, MFE = {}, MFX = {} }
for _, r in ipairs(M.BUTTON_ROWS) do
  local idx = tonumber(r[2])
  for t, col in pairs(BUTTON_COL) do
    local name = r[col]
    if name and name ~= "" then M.BUTTON_NAMES[t][idx] = name end
  end
end

local PRODUCT = { MM = 46531, MFX = 46532, MFE = 46533 }
local PRODUCT_TEXT = {
  MM = "grandMA3 Master Module (MM)",
  MFE = "grandMA3 Fader Module Encoder (MFE)",
  MFX = "grandMA3 Fader Module Crossfader (MFX)",
}

-- An object with properties (case-insensitive) and the property API.
local function makeObject(props, methods)
  local order = {}
  local store = {}
  for _, p in ipairs(props or {}) do
    order[#order + 1] = p[1]
    store[p[1]:lower()] = { raw = p[2], text = p[3] }
  end
  local obj = { _store = store, _order = order }
  local api = {
    PropertyCount = function(self) return #rawget(self, "_order") end,
    PropertyName = function(self, i) return rawget(self, "_order")[i + 1] end,
    Get = function(self, name, role)
      local e = rawget(self, "_store")[tostring(name):lower()]
      if not e then return nil end
      if role ~= nil then return tostring(e.text ~= nil and e.text or e.raw) end
      return e.raw
    end,
  }
  for k, f in pairs(methods or {}) do api[k] = f end
  return setmetatable(obj, {
    __index = function(t, k)
      if api[k] then return api[k] end
      local e = rawget(t, "_store")[tostring(k):lower()]
      return e and e.raw
    end,
  })
end
M.makeObject = makeObject

function M.new()
  local S = {
    now = 100.0,
    host = { "Console", "FullSize" },
    modules = {},
    ledCalls = {},
    violations = {},
    masters = {},
    execs = {},
    pressed = {},
    log = {}, errors = {}, vars = {},
    boxes = {}, popups = {}, boxSpecs = {},
    progress = {},
  }

  -- type: "MM" | "MFE" | "MFX" | anything else (unknown hardware)
  -- how:  "product" (numeric ProductID) | "text" (display text) | "none"
  function S.addModule(name, mtype, how)
    how = how or "product"
    local props = { { "Name", name }, { "Serial", 46531 } } -- serial looks like a product id: must be ignored
    if how == "product" then
      props[#props + 1] = { "ProductID", PRODUCT[mtype] or 12345, PRODUCT_TEXT[mtype] or "Something else" }
    elseif how == "text" then
      props[#props + 1] = { "Type", 7, PRODUCT_TEXT[mtype] or "Something else" }
    end
    local m = makeObject(props)
    rawset(m, "_type", mtype)
    rawset(m, "_name", name)
    S.modules[#S.modules + 1] = m
    S.pressed[m] = {}
    return m
  end

  function S.moduleNamed(name)
    for _, m in ipairs(S.modules) do if rawget(m, "_name") == name then return m end end
  end

  function S.press(name, index, down)
    S.pressed[S.moduleNamed(name)][index] = (down ~= false) or nil
  end

  -- text = what the master shows, fader = 0-100
  function S.setMaster(no, text, fader, scale)
    local m = S.masters[no]
    if not m then
      m = makeObject({}, {
        GetFaderText = function(self) return rawget(self, "_text") end,
        GetFader = function(self) return rawget(self, "_fader") end,
      })
      S.masters[no] = m
    end
    rawset(m, "_text", text)
    rawset(m, "_fader", fader)
    rawget(m, "_store").speedscale = { raw = scale or 0 }
    return m
  end

  -- Puts an object (a speed master number, or false for something else) on an executor.
  function S.assign(no, masterNo, width)
    if masterNo == nil then S.execs[no] = nil return end
    local obj = masterNo and S.masters[masterNo] or makeObject({ { "Name", "Seq" } })
    S.execs[no] = makeObject({ { "Object", obj }, { "Width", width or 1 } })
  end

  -- Value of one LED at time t (nil = never set / released).
  function S.ledAt(name, index, t)
    local value
    for _, c in ipairs(S.ledCalls) do
      if c.t > t then break end
      if c.module == name then
        local v = c.frame[index]
        value = (v ~= nil and v >= 0) and v or nil
      end
    end
    return value
  end

  function S.lastFrame(name)
    for i = #S.ledCalls, 1, -1 do
      if S.ledCalls[i].module == name then return S.ledCalls[i].frame end
    end
  end

  -- Indices >= 0 in the last frame sent to a module.
  function S.litIndices(name)
    local out = {}
    local f = S.lastFrame(name)
    if not f then return out end
    for i = 1, #f do if f[i] >= 0 then out[#out + 1] = i end end
    return out
  end

  local G = {}
  function G.Printf(fmt, ...) S.log[#S.log + 1] = string.format(fmt, ...) end
  function G.ErrPrintf(fmt, ...) S.errors[#S.errors + 1] = string.format(fmt, ...) end
  function G.Time() return S.now end
  function G.HostType() return S.host[1] end
  function G.HostSubType() return S.host[2] end
  G.Enums = { Roles = { Display = 2 } }
  function G.Root()
    return { UsbNotifier = { MA3Modules = { Children = function() return S.modules end } } }
  end
  function G.SetLED(h, frame)
    local mtype, name = rawget(h, "_type"), rawget(h, "_name")
    if type(frame) ~= "table" or #frame ~= 1024 then
      S.violations[#S.violations + 1] = name .. ": frame size " .. tostring(type(frame) == "table" and #frame)
    end
    local copy = {}
    for i = 1, #frame do
      local v = frame[i]
      copy[i] = v
      if math.type(v) ~= "integer" or v < -1 or v > 255 then
        S.violations[#S.violations + 1] = name .. ": bad value " .. tostring(v) .. " at " .. i
      elseif v >= 0 and not (M.LED_NAMES[mtype] and M.LED_NAMES[mtype][i]) then
        S.violations[#S.violations + 1] = name .. ": no LED at index " .. i
      end
    end
    S.ledCalls[#S.ledCalls + 1] = { t = S.now, module = name, frame = copy }
  end
  function G.GetButton(h)
    local out = {}
    local p = S.pressed[h] or {}
    for i = 1, 512 do out[i] = p[i] == true end
    return out
  end
  function G.MasterPool()
    return { Speed = setmetatable({}, { __index = function(_, k) return S.masters[k] end }) }
  end
  function G.GetExecutor(no) return S.execs[no] end
  function G.UserVars() return "uservars" end
  function G.GetVar(_, k) return S.vars[k] end
  function G.SetVar(_, k, v) S.vars[k] = v end
  function G.GetFocusDisplay() return {} end
  function G.StartProgress(text) S.progress[#S.progress + 1] = text return "progress" end
  function G.SetProgressText(_, text) S.progress[#S.progress + 1] = text end
  function G.StopProgress() end
  function G.MessageBox(spec)
    S.boxSpecs[#S.boxSpecs + 1] = spec
    local h = table.remove(S.boxes, 1)
    if not h then error("unexpected MessageBox: " .. tostring(spec.title) .. "\n" .. tostring(spec.message)) end
    return h(spec)
  end
  function G.PopupInput(spec)
    local h = table.remove(S.popups, 1)
    if not h then error("unexpected PopupInput: " .. tostring(spec.title)) end
    return h(spec)
  end
  S.globals = G

  function S.install()
    for k, v in pairs(G) do _G[k] = v end
  end

  -- Runs fn(...) as the plugin call, advancing the clock by every wait.
  function S.start(fn, ...)
    local args = table.pack(...)
    return coroutine.create(function() return fn(table.unpack(args, 1, args.n)) end)
  end

  -- Resumes the plugin call until it ends or `seconds` have passed.
  -- onFrame(now) runs after every wait.
  function S.drive(co, seconds, onFrame)
    local stopAt = S.now + seconds
    while coroutine.status(co) ~= "dead" and S.now < stopAt - 1e-9 do
      local ok, wait = coroutine.resume(co)
      if not ok then error(debug.traceback(co, wait), 0) end
      if coroutine.status(co) == "dead" then break end
      S.now = S.now + (tonumber(wait) or 0)
      if onFrame then onFrame(S.now) end
    end
  end

  return S
end

-- Dialog answer helpers -------------------------------------------------------

-- Answer a form: overrides are keyed by label without the "1 " prefix.
function M.form(overrides, result)
  overrides = overrides or {}
  return function(spec)
    local res = { result = result or 1, inputs = {}, states = {} }
    for _, input in ipairs(spec.inputs or {}) do
      local base = input.name:gsub("^%d+ ", "")
      local v = overrides[base]
      res.inputs[input.name] = (v ~= nil) and tostring(v) or input.value
    end
    for _, st in ipairs(spec.states or {}) do
      local v = overrides[st.name]
      if v == nil then v = st.state end
      res.states[st.name] = v
    end
    return res
  end
end

function M.button(value)
  return function() return { result = value } end
end

function M.pick(text)
  return function(spec)
    for i, item in ipairs(spec.items) do
      if item:find(text, 1, true) then return i - 1, item end
    end
    error("popup has no item matching " .. text)
  end
end

return M
