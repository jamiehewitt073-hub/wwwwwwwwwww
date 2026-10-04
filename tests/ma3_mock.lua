-- Minimal grandMA3 stand-in for running the plugin offline.
-- It models just enough of the console for the plugin's calls: fixtures with
-- subfixture trees, the selection grid driven by "Grid x/y" + "Fixture ...",
-- group and layout pools, dialogs answered by scripted handlers.

local M = {}

local function makeHandle(props, children, class)
  local h = { _props = props or {}, _children = children or {}, _class = class or "Fixture" }
  return setmetatable(h, {
    __index = function(t, k)
      if k == "Children" then return function(self) return rawget(self, "_children") end end
      if k == "ToAddr" then return function(self) return rawget(self, "_props").addr end end
      if k == "GetClass" then return function(self) return rawget(self, "_class") end end
      if k == "Count" then return function(self) return #rawget(self, "_children") end end
      if type(k) == "number" then return rawget(t, "_children")[k] end
      return rawget(t, "_props")[tostring(k):lower()]
    end,
    __newindex = function(t, k, v) rawget(t, "_props")[tostring(k):lower()] = v end,
    __len = function(t) return #rawget(t, "_children") end,
  })
end
M.makeHandle = makeHandle

function M.new()
  local S = {
    fixtures = {}, byAddr = {}, patch = {}, patchIndexOf = {},
    selection = {}, cursor = { 0, 0 },
    groups = {}, layouts = {},
    commands = {}, unknown = {}, cmdErrors = {}, collisions = {}, undoUsed = 0,
    log = {}, errors = {}, vars = {},
    popups = {}, boxes = {}, texts = {}, boxSpecs = {},
    gridStore = nil,
  }

  local function register(h)
    S.patch[#S.patch + 1] = h
    S.patchIndexOf[h] = #S.patch - 1 -- 0-based like the console
    S.byAddr[h._props.addr] = h
  end

  -- spec: number = flat pixels; table = list of branch sizes, "leaf" = single leaf
  function S.addFixture(fid, spec, name)
    local fx = makeHandle({ addr = "Fixture " .. fid, fid = fid, name = name or ("Fix " .. fid) }, {})
    register(fx)
    local function leaf(addr, n)
      local h = makeHandle({ addr = addr, name = "Pixel " .. n }, {})
      register(h)
      return h
    end
    if type(spec) == "number" then
      for i = 1, spec do fx._children[i] = leaf("Fixture " .. fid .. "." .. i, i) end
    else
      for i, part in ipairs(spec) do
        if part == "leaf" then
          fx._children[i] = leaf("Fixture " .. fid .. "." .. i, i)
        else
          local branch = makeHandle({ addr = "Fixture " .. fid .. "." .. i, name = "Part " .. i }, {})
          register(branch)
          for j = 1, part do
            branch._children[j] = leaf("Fixture " .. fid .. "." .. i .. "." .. j, j)
          end
          fx._children[i] = branch
        end
      end
    end
    S.fixtures[fid] = fx
    return fx
  end

  -- Pre-select main fixtures at grid positions: { {fid, x, y}, ... }
  function S.preselect(list)
    S.selection = {}
    for _, e in ipairs(list) do
      S.selection[#S.selection + 1] = { h = S.fixtures[e[1]], x = e[2], y = e[3] }
    end
  end

  local function pool(store)
    return setmetatable({}, { __index = function(_, k) return store[k] and store[k].handle or nil end })
  end

  local function selectHandle(h)
    for _, e in ipairs(S.selection) do
      if e.h == h then S.cmdErrors[#S.cmdErrors + 1] = "selected twice: " .. h._props.addr return end
      if e.x == S.cursor[1] and e.y == S.cursor[2] then
        S.collisions[#S.collisions + 1] = h._props.addr .. " @ " .. e.x .. "/" .. e.y
      end
    end
    S.selection[#S.selection + 1] = { h = h, x = S.cursor[1], y = S.cursor[2] }
    S.cursor = { S.cursor[1] + 1, S.cursor[2] }
  end

  local function copySel()
    local out = {}
    for i, e in ipairs(S.selection) do out[i] = { h = e.h, x = e.x, y = e.y, addr = e.h._props.addr } end
    return out
  end

  local function exec(c)
    local n
    if c == "ClearSelection" then
      S.selection, S.cursor = {}, { 0, 0 }
      return "Ok"
    end
    local x, y = c:match("^Grid (%-?%d+)/(%-?%d+)$")
    if x then S.cursor = { tonumber(x), tonumber(y) } return "Ok" end
    local addr = c:match("^Fixture ([%d%.]+)$")
    if addr then
      local h = S.byAddr["Fixture " .. addr]
      if not h then S.cmdErrors[#S.cmdErrors + 1] = "no such fixture: " .. addr return "Error" end
      selectHandle(h)
      return "Ok"
    end
    n = c:match("^Group (%d+)$")
    if n then
      local g = S.groups[tonumber(n)]
      if not g then return "Error" end
      for _, e in ipairs(g.cells) do S.selection[#S.selection + 1] = { h = e.h, x = e.x, y = e.y } end
      return "Ok"
    end
    n = c:match("^Store Group (%d+) /Overwrite$")
    if n then
      n = tonumber(n)
      local g = S.groups[n] or { handle = makeHandle({ no = n }, {}, "Group") }
      g.cells = copySel()
      S.groups[n] = g
      return "Ok"
    end
    local name
    n, name = c:match('^Label Group (%d+) "(.*)"$')
    if n then S.groups[tonumber(n)].name = name return "Ok" end
    n = c:match("^Store Layout (%d+)$")
    if n then
      n = tonumber(n)
      if not S.layouts[n] then S.layouts[n] = { handle = makeHandle({ no = n }, {}, "Layout") } end
      return "Ok"
    end
    n = c:match("^Delete Layout (%d+) /NoConfirmation$")
    if n then S.layouts[tonumber(n)] = nil return "Ok" end
    n, name = c:match('^Label Layout (%d+) "(.*)"$')
    if n then S.layouts[tonumber(n)].name = name return "Ok" end
    local fa
    fa, n = c:match("^Assign Fixture ([%d%.]+) At Layout (%d+)$")
    if fa then
      local h = S.byAddr["Fixture " .. fa]
      local L = S.layouts[tonumber(n)]
      if not h or not L then S.cmdErrors[#S.cmdErrors + 1] = "assign failed: " .. c return "Error" end
      local kids = L.handle._children
      kids[#kids + 1] = makeHandle({ object = h, addr = "Layout " .. n .. "." .. (#kids + 1) }, {}, "Element")
      return "Ok"
    end
    if c == "GridStore" then S.gridStore = copySel() return "Ok" end
    S.unknown[#S.unknown + 1] = c
    return "Syntax Error"
  end

  -- UI objects ---------------------------------------------------------------
  -- Plain tables: properties are stored as fields. [1] / [2] are the row /
  -- column definition collections of a grid.
  local UIMT = {}
  local function uiObj(cls, parent)
    return setmetatable({ _class = cls, _children = {}, _parent = parent, _valid = true }, UIMT)
  end
  local function invalidate(o)
    o._valid = false
    for _, c in ipairs(o._children) do invalidate(c) end
  end
  UIMT.__index = function(t, k)
    if k == "Append" then
      return function(self, cls)
        if S.failAppend then error("Append is not available") end
        local child = uiObj(cls, self)
        self._children[#self._children + 1] = child
        return child
      end
    end
    if k == "ClearUIChildren" then
      return function(self)
        for _, c in ipairs(self._children) do invalidate(c) end
        self._children = {}
      end
    end
    if k == 1 or k == 2 then
      local coll = setmetatable({}, { __index = function(c, i) local d = {}; rawset(c, i, d); return d end })
      rawset(t, k, coll)
      return coll
    end
    return nil
  end
  -- Optionally fire TextChanged as soon as an edit gets its first Content,
  -- the way a console might while the window is being built.
  UIMT.__newindex = function(t, k, v)
    rawset(t, k, v)
    if S.fireOnContent and (k == "Content" or k == "TextChanged")
      and rawget(t, "Content") ~= nil and rawget(t, "TextChanged") and S.signals[rawget(t, "TextChanged")] then
      S.signals[rawget(t, "TextChanged")](t)
    end
  end
  S.overlay = uiObj("ScreenOverlay")
  S.display = { ScreenOverlay = S.overlay, W = 1920, H = 1080 }
  S.signals = {}

  function S.find(name, node)
    node = node or S.overlay
    for _, c in ipairs(node._children) do
      if c.Name == name then return c end
      local hit = S.find(name, c)
      if hit then return hit end
    end
    return nil
  end
  function S.findAll(cls, node, out)
    node, out = node or S.overlay, out or {}
    for _, c in ipairs(node._children) do
      if c._class == cls then out[#out + 1] = c end
      S.findAll(cls, c, out)
    end
    return out
  end
  function S.click(name)
    local o = assert(S.find(name), "no UI object named " .. name)
    S.signals[o.Clicked](o)
    return o
  end
  function S.type(name, text)
    local o = assert(S.find(name), "no UI object named " .. name)
    o.Content = text
    S.signals[o.TextChanged](o)
    return o
  end
  function S.window() return S.overlay._children[1] end

  local G = {}
  G.Obj = {
    Index = function(o)
      local parent = type(o) == "table" and rawget(o, "_parent")
      if not parent then return 1 end
      for i, c in ipairs(parent._children) do if c == o then return i end end
      return nil
    end,
    Delete = function(parent, index)
      local o = table.remove(parent._children, index)
      if o then invalidate(o) end
    end,
  }
  function G.IsObjectValid(o) return type(o) == "table" and o._valid == true or nil end
  function G.GetDisplayByIndex() return S.display end
  function G.Root()
    return { ColorTheme = { ColorGroups = {
      Global = { Transparent = "transparent", Selected = "selected", PartlySelected = "partly",
        PartlySelectedPreset = "partlyPreset", ErrorText = "errorText", Text = "text" },
      Button = { Background = "bg", BackgroundPlease = "please", BackgroundClear = "clear" },
    } } }
  end

  function G.Cmd(c, undo)
    S.commands[#S.commands + 1] = c
    if undo then S.undoUsed = S.undoUsed + 1 end
    return exec(c)
  end
  function G.Printf(fmt, ...) S.log[#S.log + 1] = string.format(fmt, ...) end
  function G.ErrPrintf(fmt, ...) S.errors[#S.errors + 1] = string.format(fmt, ...) end
  function G.Echo(fmt, ...) S.log[#S.log + 1] = string.format(fmt, ...) end
  function G.ObjectList(addr)
    local fid = tonumber(addr:match("^Fixture (%d+)$"))
    if fid and S.fixtures[fid] then return { S.fixtures[fid] } end
    return {}
  end
  function G.DataPool()
    return { Groups = pool(S.groups), Layouts = pool(S.layouts) }
  end
  function G.SelectionCount() return #S.selection end
  function G.SelectionFirst()
    local e = S.selection[1]
    if not e then return nil end
    return S.patchIndexOf[e.h], e.x, e.y, 0
  end
  function G.SelectionNext(idx)
    for i, e in ipairs(S.selection) do
      if S.patchIndexOf[e.h] == idx then
        local nx = S.selection[i + 1]
        if not nx then return nil end
        return S.patchIndexOf[nx.h], nx.x, nx.y, 0
      end
    end
    return nil
  end
  function G.GetSubfixture(idx) return S.patch[idx + 1] end
  function G.GetFocusDisplay() return S.display end
  function G.UserVars() return "uservars" end
  function G.GetVar(_, k) return S.vars[k] end
  function G.SetVar(_, k, v) S.vars[k] = v end
  function G.CreateUndo(text) return { undo = text } end
  function G.CloseUndo() return true end
  function G.StartProgress() return "progress" end
  function G.SetProgressRange() end
  function G.SetProgress() end
  function G.StopProgress() end
  function G.MessageBox(spec)
    S.boxSpecs[#S.boxSpecs + 1] = spec
    local h = table.remove(S.boxes, 1)
    if not h then error("unexpected MessageBox: " .. tostring(spec.title)) end
    return h(spec)
  end
  function G.PopupInput(spec)
    local h = table.remove(S.popups, 1)
    if not h then error("unexpected PopupInput: " .. tostring(spec.title)) end
    return h(spec)
  end
  function G.TextInput(title)
    local h = table.remove(S.texts, 1)
    if not h then error("unexpected TextInput: " .. tostring(title)) end
    return h
  end
  S.globals = G

  function S.install()
    for k, v in pairs(G) do _G[k] = v end
  end
  return S
end

-- Dialog answer helpers -------------------------------------------------------

-- Choose an item from a PopupInput by (part of) its label.
function M.pick(text)
  return function(spec)
    for i, item in ipairs(spec.items) do
      if item:find(text, 1, true) then return i - 1, item end
    end
    error("popup has no item matching " .. text)
  end
end

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

return M
