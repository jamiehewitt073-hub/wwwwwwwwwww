-- Minimal grandMA3 stand-in for running DeskLock offline.
-- It models displays with screen overlays and plugin UI objects, users and
-- logins, appearances, global variables and dialogs answered by scripted
-- handlers. A clock the tests move by hand replaces real time.

local M = {}

-- Generic console object: properties + children. obj[1] / obj[2] are the
-- row / column collections of a UI grid, like on the console.
local function newObject(class, props)
  local o = { _class = class, _props = props or {}, _children = {}, _grid = {} }
  return setmetatable(o, {
    __index = function(t, k)
      if k == "Children" then return function(self) return rawget(self, "_children") end end
      if k == "Append" then
        return function(self, cls)
          local c = newObject(cls or "Object")
          rawset(c, "_parent", self)
          local kids = rawget(self, "_children")
          kids[#kids + 1] = c
          return c
        end
      end
      if k == "Acquire" then return function(self) return t.Append(self, "User") end end
      if k == "ClearUIChildren" then return function(self) rawset(self, "_children", {}) end end
      if k == "Parent" then return function(self) return rawget(self, "_parent") end end
      if k == "ToAddr" then return function(self) return rawget(self, "_props").addr end end
      if k == "GetClass" then return function(self) return rawget(self, "_class") end end
      if type(k) == "number" then
        if k == 1 or k == 2 then
          local g = rawget(t, "_grid")
          g[k] = g[k] or setmetatable({}, { __index = function(tt, i) local cell = {}; rawset(tt, i, cell); return cell end })
          return g[k]
        end
        return rawget(t, "_children")[k]
      end
      return rawget(t, "_props")[k]
    end,
    __newindex = function(t, k, v) rawget(t, "_props")[k] = v end,
  })
end
M.newObject = newObject

function M.new()
  local S = {
    t = 1000000, displays = {}, users = {}, current = nil, vars = {},
    commands = {}, log = {}, errors = {}, timers = {},
    boxes = {}, popups = {}, texts = {}, boxSpecs = {}, textTitles = {},
    appearances = {}, library = nil,
  }

  -- Displays ------------------------------------------------------------------
  function S.addDisplay(index, name, w, h)
    local d = newObject("Display", { Name = name, W = w, H = h, Index = index })
    d._props.ScreenOverlay = newObject("ScreenOverlay")
    S.displays[#S.displays + 1] = d
    return d
  end
  local displayCollect = newObject("DisplayCollect")
  displayCollect._children = S.displays

  -- Users ---------------------------------------------------------------------
  local usersPool = newObject("Users")
  S.usersPool = usersPool
  function S.addUser(name, password, rights)
    local u = usersPool:Append("User")
    u.Name, u.Password, u.Rights, u.Profile = name, password or "", rights or "Admin", "Default"
    return u
  end
  S.current = S.addUser("Admin", "", "Admin")

  -- Appearances ---------------------------------------------------------------
  local appPool = newObject("Appearances")
  function S.addAppearance(no, name, imgW, imgH)
    local a = appPool:Append("Appearance")
    a.Name, a.No = name, no
    if imgW then a.MediaImage = newObject("Image", { Name = name .. ".png", Width = imgW, Height = imgH }) end
    S.appearances[no] = a
    return a
  end
  setmetatable(S.appearances, {})
  local appIndex = getmetatable(appPool).__index
  getmetatable(appPool).__index = function(t, k)
    if type(k) == "number" then return S.appearances[k] end
    return appIndex(t, k)
  end

  -- Plugin handle -------------------------------------------------------------
  local plugin = newObject("Plugin", { addr = "Plugin 7", Name = "DeskLock" })
  S.component = plugin:Append("ComponentLua")

  -- UI helpers for tests --------------------------------------------------------
  function S.overlay(i) return S.displays[i]._props.ScreenOverlay end
  function S.lockBase(i)
    for _, c in ipairs(S.overlay(i)._children) do
      if c._props.Name == "DeskLockOverlay" then return c end
    end
  end
  -- Finds a UI object by name anywhere below obj.
  function S.find(obj, name)
    if obj == nil then return nil end
    if obj._props.Name == name then return obj end
    for _, c in ipairs(obj._children) do
      local f = S.find(c, name)
      if f then return f end
    end
  end
  function S.click(displayIndex, name)
    local obj = S.find(S.lockBase(displayIndex), name)
    assert(obj, "no UI object " .. name .. " on display " .. displayIndex)
    assert(obj._props.Clicked, name .. " is not clickable")
    S.signalTable[obj._props.Clicked](obj)
  end
  function S.typePin(displayIndex, pin)
    for d in pin:gmatch("%d") do S.click(displayIndex, "DLKey_" .. d .. "_" .. displayIndex) end
    S.click(displayIndex, "DLKey_OK_" .. displayIndex)
  end

  -- Globals ---------------------------------------------------------------------
  local G = {}
  function G.Printf(fmt, ...) S.log[#S.log + 1] = string.format(fmt, ...) end
  function G.ErrPrintf(fmt, ...) S.errors[#S.errors + 1] = string.format(fmt, ...) end
  function G.Cmd(c)
    S.commands[#S.commands + 1] = c
    local name, pw = c:match('^Login "([^"]*)" "([^"]*)"$')
    if not name then name = c:match('^Login "([^"]*)"$'); pw = "" end
    if name then
      for _, u in ipairs(usersPool._children) do
        if u._props.Name == name and (u._props.Password or "") == pw then S.current = u return "Ok" end
      end
      return "Error"
    end
    return "Ok"
  end
  function G.GlobalVars() return "globalvars" end
  function G.GetVar(_, k) return S.vars[k] end
  function G.SetVar(_, k, v) S.vars[k] = v end
  function G.DelVar(_, k) S.vars[k] = nil end
  function G.GetDisplayCollect() return displayCollect end
  function G.GetDisplayByIndex(i) return S.displays[i] end
  function G.GetFocusDisplay() return S.displays[1] end
  function G.CurrentUser() return S.current end
  function G.ShowData() return { Users = usersPool, Appearances = appPool } end
  function G.DataPool() return {} end
  function G.Root() return { Temp = { DriveCollect = newObject("Drives") } } end
  function G.GetPath() return S.library end
  function G.CreateDirectoryRecursive(p) os.execute('mkdir -p "' .. p .. '"') return true end
  function G.Timer(fn, delay, count) S.timers[#S.timers + 1] = { fn = fn, delay = delay, count = count } end
  function G.MessageBox(spec)
    S.boxSpecs[#S.boxSpecs + 1] = spec
    local h = table.remove(S.boxes, 1)
    if not h then return { result = 1 } end
    return h(spec)
  end
  function G.PopupInput(spec)
    local h = table.remove(S.popups, 1)
    if not h then error("unexpected PopupInput: " .. tostring(spec.title)) end
    return h(spec)
  end
  function G.TextInput(title)
    S.textTitles[#S.textTitles + 1] = title
    local v = table.remove(S.texts, 1)
    if v == nil then error("unexpected TextInput: " .. tostring(title)) end
    if v == false then return nil end
    return v
  end
  S.globals = G

  function S.install()
    for k, v in pairs(G) do _G[k] = v end
    _G.Enums = nil
  end
  return S
end

-- Dialog helpers ---------------------------------------------------------------
function M.pick(text)
  return function(spec)
    for i, item in ipairs(spec.items) do
      if item:find(text, 1, true) then return i - 1, item end
    end
    error("popup has no item matching " .. text)
  end
end

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

return M
