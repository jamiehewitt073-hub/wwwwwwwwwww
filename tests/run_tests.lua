-- Offline tests for Pixel Grid Builder.  Run from the repo root:
--   lua tests/run_tests.lua

package.path = "./tests/?.lua;" .. package.path
local mock = require("ma3_mock")

local PLUGIN = "PixelGridBuilder/PixelGridBuilder.lua"

local passed, failed = 0, 0
local function test(name, fn)
  local ok, err = xpcall(fn, debug.traceback)
  if ok then
    passed = passed + 1
    print("ok    " .. name)
  else
    failed = failed + 1
    print("FAIL  " .. name .. "\n      " .. tostring(err):gsub("\n", "\n      "))
  end
end

local function eq(a, b, msg)
  if a ~= b then error((msg or "values differ") .. ": expected " .. tostring(b) .. ", got " .. tostring(a), 2) end
end
local function truthy(v, msg) if not v then error(msg or "expected a true value", 2) end end
local function listEq(a, b, msg)
  eq(#a, #b, (msg or "list") .. " length")
  for i = 1, #b do eq(a[i], b[i], (msg or "list") .. " item " .. i) end
end

-- Loads a fresh copy of the plugin against a fresh mock console.
local function load()
  local S = mock.new()
  S.install()
  PGB_TEST_HOOK = {}
  local chunk = assert(loadfile(PLUGIN))
  local main = chunk("Pixel Grid Builder", "PixelGridBuilder", S.signals, { component = true })
  local hook = PGB_TEST_HOOK
  PGB_TEST_HOOK = nil
  return S, main, hook
end

local function uniquePositions(cells, key)
  local seen = {}
  for _, c in ipairs(cells) do
    local k = c.x .. "/" .. c.y
    if seen[k] then return false, k end
    seen[k] = true
  end
  return true
end

local function extent(cells)
  local w, h = 0, 0
  for _, c in ipairs(cells) do w = math.max(w, c.x + 1); h = math.max(h, c.y + 1) end
  return w, h
end

local function cellAt(cells, addr)
  for _, c in ipairs(cells) do if c.addr == addr then return c end end
end

local function noProblems(S)
  eq(#S.unknown, 0, "unknown commands: " .. table.concat(S.unknown, " | "))
  eq(#S.cmdErrors, 0, "command errors: " .. table.concat(S.cmdErrors, " | "))
  eq(#S.collisions, 0, "grid collisions: " .. table.concat(S.collisions, " | "))
end

--------------------------------------------------------------------------------
-- Parsing
--------------------------------------------------------------------------------
local _, _, H = load()
local P = H.P

test("parseIdList ranges, plus and commas", function()
  listEq(P.parseIdList("101 Thru 104 + 201-202, 301"), { 101, 102, 103, 104, 201, 202, 301 })
  listEq(P.parseIdList("110 thru 108"), { 110, 109, 108 })
  listEq(P.parseIdList("5 - 7"), { 5, 6, 7 })
  local ids, err = P.parseIdList("abc")
  eq(ids, nil); truthy(err)
end)

test("parseSubIdList ranges and nested IDs", function()
  listEq(P.parseSubIdList("1 Thru 3, 2.1-2.3, .7"), { "1", "2", "3", "2.1", "2.2", "2.3", "7" })
  listEq(P.parseSubIdList("15-17 1-2"), { "15", "16", "17", "1", "2" })
  listEq(P.parseSubIdList("3 thru 1"), { "3", "2", "1" })
  local l, err = P.parseSubIdList("1.1-2.3")
  eq(l, nil); truthy(err)
end)

test("parseNumberList / parseNameList", function()
  listEq(P.parseNumberList("1,6, 12", 1, 100), { 1, 6, 12 })
  eq(P.parseNumberList("1,x", 1, 100), nil)
  listEq(P.parseNameList("Tube A, Face ,Tube B"), { "Tube A", "Face", "Tube B" })
end)

--------------------------------------------------------------------------------
-- Shapes
--------------------------------------------------------------------------------
local function byOrder(shape)
  local t = {}
  for _, c in ipairs(shape.cells) do t[c.order] = c end
  return t
end

local function shapeUnique(shape)
  local seen = {}
  for _, c in ipairs(shape.cells) do
    local k = c.gx .. "/" .. c.gy
    if seen[k] then return false end
    seen[k] = true
  end
  return true
end

test("line shape", function()
  local s = P.buildShape("line", { count = 10 })
  eq(#s.cells, 10); eq(s.gw, 10); eq(s.gh, 1)
  s = P.buildShape("line", { count = 4, vertical = true, reverse = true })
  eq(s.gw, 1); eq(s.gh, 4)
  eq(byOrder(s)[1].gy, 3, "pixel 1 at the end")
end)

test("matrix shape: rows, snake, corners", function()
  local s = P.buildShape("matrix", { cols = 3, rows = 2, snake = true })
  local o = byOrder(s)
  eq(o[1].gx, 0); eq(o[3].gx, 2); eq(o[4].gx, 2); eq(o[4].gy, 1); eq(o[6].gx, 0)
  s = P.buildShape("matrix", { cols = 3, rows = 2, columnOrder = true, startBottom = true })
  o = byOrder(s)
  eq(o[1].gx, 0); eq(o[1].gy, 1); eq(o[2].gy, 0); eq(o[3].gx, 1)
  truthy(shapeUnique(s))
end)

test("rows shape: STRIKE M style parts", function()
  local s = P.buildShape("rows", { counts = "14,14,14", names = "Tubes,Face,Tubes" })
  eq(#s.cells, 42); eq(s.gw, 14); eq(s.gh, 3)
  listEq(s.parts, { "Tubes", "Face" })
  local o = byOrder(s)
  eq(o[15].part, "Face"); eq(o[15].gy, 1); eq(o[29].part, "Tubes"); eq(o[29].gy, 2)
  s = P.buildShape("rows", { counts = "3,5", names = "" })
  o = byOrder(s)
  eq(o[1].gx, 1, "short row centered on grid"); eq(o[1].lx, 1, "short row centered on layout")
  listEq(s.parts, { "Row 1", "Row 2" })
end)

test("hex shape: counts, ring order, start at 12 o'clock clockwise", function()
  for R, n in pairs({ [1] = 7, [2] = 19, [3] = 37, [4] = 61 }) do
    local s = P.buildShape("hex", { rings = R, start = 0 })
    eq(#s.cells, n, "hex rings " .. R); truthy(shapeUnique(s), "unique hex grid " .. R)
  end
  local s = P.buildShape("hex", { rings = 1, start = 0 })
  local o = byOrder(s)
  eq(o[1].part, "Center")
  eq(o[2].gy, 0, "first ring pixel is on the top row")
  truthy(o[2].gx > o[1].gx, "first ring pixel is right of center (clockwise from 12)")
  eq(o[3].gy, 1, "then the right-hand pixel"); truthy(o[3].gx > o[2].gx)
  listEq(s.parts, { "Center", "Ring 1" })
  s = P.buildShape("hex", { rings = 2, start = 0, outsideIn = true })
  eq(byOrder(s)[1].part, "Ring 2")
end)

test("rings shape: quantized without collisions", function()
  local s = P.buildShape("rings", { counts = "1,8,16", start = 0 })
  eq(#s.cells, 25); truthy(shapeUnique(s))
  local o = byOrder(s)
  eq(o[1].part, "Center"); eq(o[2].part, "Ring 1")
  eq(o[2].gx, o[1].gx, "ring starts at 12 o'clock"); truthy(o[2].gy < o[1].gy)
  eq(o[3].gx > o[2].gx, true, "clockwise")
  s = P.buildShape("rings", { counts = "12", start = 90, ccw = true })
  eq(#s.cells, 12); truthy(shapeUnique(s))
end)

test("rings shape: symmetric grid, layout pixels at least one cell apart", function()
  local s = P.buildShape("rings", { counts = "1,6,12" })
  local o = byOrder(s)
  local cx, cy = o[1].gx, o[1].gy
  local seen = {}
  for _, c in ipairs(s.cells) do seen[(c.gx - cx) .. "/" .. (c.gy - cy)] = true end
  for _, c in ipairs(s.cells) do
    truthy(seen[(cx - c.gx) .. "/" .. (c.gy - cy)], "mirror image of every cell exists")
  end
  s = P.buildShape("rings", { counts = "1,8,16" })
  for i = 1, #s.cells do
    for j = i + 1, #s.cells do
      local a, b = s.cells[i], s.cells[j]
      local d = math.sqrt((a.lx - b.lx) ^ 2 + (a.ly - b.ly) ^ 2)
      truthy(d > 0.999, "layout cells overlap: " .. d)
    end
  end
end)

test("custom map: parts, gaps, ranges, thru", function()
  local s = P.buildShape("custom", { map = "Tubes: 1-3 / Face: 4 . 6 / Tubes: 9 thru 7" })
  eq(#s.cells, 8); listEq(s.parts, { "Tubes", "Face" })
  local bySub = {}
  for _, c in ipairs(s.cells) do bySub[c.sub] = c end
  eq(bySub["6"].gx, 2, "gap kept"); eq(bySub["6"].gy, 1)
  eq(bySub["9"].gx, 0); eq(bySub["7"].gx, 2); eq(bySub["7"].part, "Tubes")
  truthy(s.literal)
  local bad, err = P.buildShape("custom", { map = "1 2 / 2" })
  eq(bad, nil); truthy(err:find("twice"))
  bad, err = P.buildShape("custom", { map = "1 x 3" })
  eq(bad, nil); truthy(err:find("x"))
  s = P.buildShape("custom", { map = "1.1-1.3 // 2.1-2.3" })
  eq(s.gh, 3, "empty row kept between rows")
end)

test("shape dialog validation", function()
  local s, err = P.buildShape("line", { count = "0" })
  eq(s, nil); truthy(err:find("Pixels"))
  s, err = P.buildShape("rows", { counts = "14,,a" })
  eq(s, nil); truthy(err)
end)

--------------------------------------------------------------------------------
-- Transforms and placement
--------------------------------------------------------------------------------
test("rotate and flip", function()
  local s = P.buildShape("matrix", { cols = 3, rows = 2 })
  local r = P.transform(s, 90, false, false)
  eq(r.gw, 2); eq(r.gh, 3)
  local o = byOrder(r)
  eq(o[1].gx, 1, "top-left goes to top-right"); eq(o[1].gy, 0)
  local back = P.transform(P.transform(s, 180), 180)
  for i, c in ipairs(back.cells) do eq(c.gx, s.cells[i].gx); eq(c.gy, s.cells[i].gy) end
  local f = P.transform(s, 0, true, false)
  eq(byOrder(f)[1].gx, 2)
  local v = P.transform(s, 0, false, true)
  eq(byOrder(v)[1].gy, 1)
end)

test("placement: gap, fixtures per row, alternate", function()
  local s = P.buildShape("line", { count = 3 })
  P.assignSubs(s, { "1", "2", "3" })
  local fx = { { fid = 1 }, { fid = 2 }, { fid = 3 } }
  local placed = P.place(fx, P.slotsInRows(3, 2), s, P.transform(s, 180), 1)
  eq(#placed, 9)
  local function find(fid, sub)
    for _, c in ipairs(placed) do if c.fid == fid and c.sub == sub then return c end end
  end
  eq(find(2, "3").gx, 4, "fixture 2 turned around starts at x 4")
  eq(find(2, "1").gx, 6)
  eq(find(3, "1").gx, 0); eq(find(3, "1").gy, 2, "third fixture on the next row (gap 1)")
end)

test("slotsFromGrid packs used rows and columns", function()
  local slots = P.slotsFromGrid({ { x = 0, y = 0 }, { x = 4, y = 0 }, { x = 0, y = 7 }, { x = 4, y = 7 } })
  eq(slots[2].x, 1); eq(slots[3].y, 1); eq(slots[4].x, 1); eq(slots[4].y, 1)
end)

test("selection commands are in reading order", function()
  local cmds = P.selectionCommands({
    { fid = 1, sub = "2", gx = 1, gy = 0 }, { fid = 1, sub = "3", gx = 0, gy = 1 }, { fid = 1, sub = "1", gx = 0, gy = 0 },
  })
  listEq(cmds, { "ClearSelection", "Grid 0/0", "Fixture 1.1", "Grid 1/0", "Fixture 1.2", "Grid 0/1", "Fixture 1.3" })
end)

test("layout elements are positive and Y-up by default", function()
  local els = P.layoutElements({ { fid = 1, sub = "1", gx = 0, gy = 0, lx = 0, ly = 0 },
    { fid = 1, sub = "2", gx = 0, gy = 1, lx = 0, ly = 1 } }, 40, 0.9, true)
  eq(els[1].addr, "1.1"); eq(els[1].y > els[2].y, true, "top row has the higher PosY")
  eq(els[2].y >= 0, true); eq(els[1].w, 36)
end)

--------------------------------------------------------------------------------
-- End to end against the mock console
--------------------------------------------------------------------------------
test("STRIKE M preset: 4 fixtures, auto sub-IDs, groups + part groups + layout", function()
  local S, main = load()
  for fid = 101, 104 do S.addFixture(fid, { 14, 14, 14 }) end
  S.popups = { mock.pick("STRIKE M") }
  local summary
  S.boxes = {
    mock.form({}),
    mock.form({ Fixtures = "101 Thru 104", ["Group no. (0 = none)"] = 50, ["Layout no. (0 = none)"] = 7 }),
    function(spec) summary = spec.message return { result = 1 } end,
  }
  main(nil, "classic")
  noProblems(S)
  truthy(summary:find("4 fixtures x 42 pixels = 168 cells"), summary)

  local g = S.groups[50]
  eq(g.name, "StrikeM Grid"); eq(#g.cells, 168)
  truthy(uniquePositions(g.cells))
  local w, h = extent(g.cells)
  eq(w, 4 * 14 + 3, "grid width with 1-cell gaps"); eq(h, 3)
  local c = cellAt(g.cells, "Fixture 101.1.1"); eq(c.x, 0); eq(c.y, 0)
  c = cellAt(g.cells, "Fixture 102.2.1"); eq(c.x, 15); eq(c.y, 1)

  eq(S.groups[51].name, "StrikeM Tubes"); eq(#S.groups[51].cells, 112)
  eq(S.groups[52].name, "StrikeM Face"); eq(#S.groups[52].cells, 56)
  for _, e in ipairs(S.groups[52].cells) do eq(e.y, 0, "face group starts at row 0") end

  local L = S.layouts[7]
  eq(L.name, "StrikeM Pixels"); eq(#L.handle._children, 168)
  for _, el in ipairs(L.handle._children) do
    truthy(el.posx >= 0 and el.posy >= 0, "layout positions >= 0")
    eq(el.positionw, 36)
  end
  eq(#S.selection, 168, "full grid left selected")
  truthy(S.undoUsed > 0, "commands grouped into one undo")
  eq(S.vars["PGB_rig.group"], "50")
end)

test("Hex 19 from the selection grid, extra master subfixture, use last 19", function()
  local S, main = load()
  for fid = 201, 204 do S.addFixture(fid, { "leaf", 19 }) end
  -- leaf 1 = master, branch 2 holds the 19 pixels: flatten to 20 leaves
  S.preselect({ { 201, 0, 0 }, { 202, 3, 0 }, { 203, 0, 5 }, { 204, 3, 5 } })
  S.popups = { mock.pick("Hex 19") }
  S.boxes = {
    mock.form({}),
    mock.form({ ["Group no. (0 = none)"] = 60, ["Layout no. (0 = none)"] = 0 }),
    function(spec) truthy(spec.message:find("20 pixels")) return { result = 2 } end, -- Use last 19
    mock.button(1),
  }
  main(nil, "classic")
  noProblems(S)
  local g = S.groups[60]
  eq(#g.cells, 4 * 19)
  local w, h = extent(g.cells)
  eq(w, 9 * 2 + 1); eq(h, 5 * 2 + 1)
  truthy(uniquePositions(g.cells))
  eq(cellAt(g.cells, "Fixture 201.1"), nil, "master subfixture skipped")
  truthy(cellAt(g.cells, "Fixture 204.2.19"))
  eq(S.groups[61].name, "Hex19 Center"); eq(#S.groups[61].cells, 4)
  eq(S.groups[62].name, "Hex19 Ring 1"); eq(#S.groups[62].cells, 24)
  eq(S.groups[63].name, "Hex19 Ring 2"); eq(#S.groups[63].cells, 48)
  eq(S.layouts[0], nil)
end)

test("custom map, rotate 90, alternate, layout only, selection cleared", function()
  local S, main = load()
  S.addFixture(301, 9); S.addFixture(302, 9)
  S.popups = { mock.pick("Custom pixel map") }
  S.boxes = {
    mock.form({ ["Pixel map"] = "1 2 3 / 4 5 6 / 7 8 9" }),
    mock.form({ Fixtures = "301, 302", ["Rotate (0/90/180/270)"] = 90, ["Turn every 2nd fixture 180"] = true,
      ["Group no. (0 = none)"] = 0, ["Layout no. (0 = none)"] = 3, ["Keep the grid selected"] = false }),
    mock.button(1),
  }
  main(nil, "classic")
  noProblems(S)
  eq(next(S.groups), nil, "no groups stored")
  eq(#S.layouts[3].handle._children, 18)
  eq(#S.selection, 0)
  -- the sub-ID field is hidden for literal maps
  for _, input in ipairs(S.boxSpecs[2].inputs) do truthy(not input.name:find("sub%-IDs")) end
end)

test("GridStore uses the first fixture's pixels in local grid positions", function()
  local S, main = load()
  S.addFixture(101, 6); S.addFixture(102, 6)
  S.popups = { mock.pick("Matrix / panel") }
  S.boxes = {
    mock.form({ Columns = 3, Rows = 2 }),
    mock.form({ Fixtures = "101-102", ["Group no. (0 = none)"] = 5, ["Layout no. (0 = none)"] = 0,
      ["GridStore shape to fixture type"] = true }),
    mock.button(1),
  }
  main(nil, "classic")
  noProblems(S)
  eq(#S.gridStore, 6)
  for _, e in ipairs(S.gridStore) do truthy(e.addr:find("^Fixture 101%.")) end
  local w, h = extent(S.gridStore); eq(w, 3); eq(h, 2)
  eq(#S.groups[5].cells, 12)
end)

test("existing objects are flagged, missing fixtures skipped", function()
  local S, main = load()
  S.addFixture(1, 10); S.addFixture(3, 10)
  S.globals.Cmd("ClearSelection"); S.globals.Cmd("Store Group 9 /Overwrite")
  S.popups = { mock.pick("Pixel line / bar") }
  local summary
  S.boxes = {
    mock.form({ Pixels = 10 }),
    mock.form({ Fixtures = "1 Thru 3", ["Group no. (0 = none)"] = 9, ["Layout no. (0 = none)"] = 0 }),
    function(spec) summary = spec.message return { result = 0 } end,
  }
  main(nil, "classic")
  truthy(summary:find("WILL BE OVERWRITTEN: Group 9"), summary)
  truthy(summary:find("Skipped, not patched: 2"), summary)
end)

test("bad input shows a problem and returns to the form", function()
  local S, main = load()
  S.addFixture(1, 10)
  S.popups = { mock.pick("Pixel line / bar") }
  local problem
  S.boxes = {
    mock.form({ Pixels = 10 }),
    mock.form({ Fixtures = "999" }),
    function(spec) problem = spec.message return { result = 1 } end,
    mock.form({}, 0),
  }
  main(nil, "classic")
  truthy(problem and problem:find("999"), tostring(problem))
end)

test("sub-ID list in custom order (face first in patch)", function()
  local S, main = load()
  S.addFixture(101, 42)
  S.popups = { mock.pick("STRIKE M") }
  S.boxes = {
    mock.form({}),
    mock.form({ Fixtures = "101", ["Pixel sub-IDs"] = "15-28, 1-14, 29-42", ["Group no. (0 = none)"] = 1,
      ["Layout no. (0 = none)"] = 0 }),
    mock.button(1),
  }
  main(nil, "classic")
  noProblems(S)
  local g = S.groups[1]
  eq(cellAt(g.cells, "Fixture 101.15").y, 0, "sub 15 is pixel 1 (top tube)")
  eq(cellAt(g.cells, "Fixture 101.1").y, 1, "sub 1 is on the face row")
end)

test("Group N as the fixture source keeps its arrangement", function()
  local S, main = load()
  for fid = 1, 4 do S.addFixture(fid, 4) end
  S.preselect({ { 1, 0, 0 }, { 2, 1, 0 }, { 3, 0, 1 }, { 4, 1, 1 } })
  S.globals.Cmd("Store Group 20 /Overwrite")
  S.globals.Cmd("ClearSelection")
  S.popups = { mock.pick("Pixel line / bar") }
  S.boxes = {
    mock.form({ Pixels = 4 }),
    mock.form({ Fixtures = "Group 20", Gap = 0, ["Group no. (0 = none)"] = 21, ["Layout no. (0 = none)"] = 0 }),
    mock.button(1),
  }
  main(nil, "classic")
  noProblems(S)
  local w, h = extent(S.groups[21].cells)
  eq(w, 8); eq(h, 2)
end)

test("dialogs retry without optional input keys", function()
  local S, main = load()
  S.addFixture(101, 10)
  local strict = S.globals.MessageBox
  _G.MessageBox = function(spec)
    for _, i in ipairs(spec.inputs or {}) do
      if i.maxTextLength or i.vkPlugin then error("unknown key") end
    end
    return strict(spec)
  end
  S.popups = { mock.pick("Pixel line / bar") }
  S.boxes = {
    mock.form({ Pixels = 10 }),
    mock.form({ Fixtures = "101", ["Group no. (0 = none)"] = 2, ["Layout no. (0 = none)"] = 0 }),
    mock.button(1),
  }
  main(nil, "classic")
  noProblems(S)
  eq(#S.groups[2].cells, 10)
end)

test("inspect prints the subfixture tree", function()
  local S, main = load()
  S.addFixture(101, { "leaf", 14, 14 })
  S.popups = { mock.pick("Inspect fixture") }
  S.texts = { "101" }
  local text
  S.boxes = { function(spec) text = spec.message return { result = 1 } end }
  main(nil, "classic")
  truthy(text:find("29 pixels"), text)
  local all = table.concat(S.log, "\n")
  truthy(all:find("%.2%.14"), all)
end)

test("remembered values come back next run", function()
  local S, main = load()
  S.addFixture(101, 12)
  S.popups = { mock.pick("Pixel line / bar") }
  S.boxes = {
    mock.form({ Pixels = 12 }),
    mock.form({ Fixtures = "101", ["Group no. (0 = none)"] = 30, ["Layout no. (0 = none)"] = 0 }),
    mock.button(1),
  }
  main(nil, "classic")
  S.popups = { mock.pick("Pixel line / bar") }
  local shapeSpec, rigSpec
  S.boxes = {
    function(spec) shapeSpec = spec return mock.form({})(spec) end,
    function(spec) rigSpec = spec return { result = 0 } end,
  }
  main(nil, "classic")
  eq(shapeSpec.inputs[1].value, "12")
  local group
  for _, i in ipairs(rigSpec.inputs) do if i.name:find("Group no") then group = i.value end end
  eq(group, "31", "next free group suggested after the last build")
end)

--------------------------------------------------------------------------------
-- Window
--------------------------------------------------------------------------------
local function info(H) return tostring(H.GUI.w.info.Text) end
local function note(H) return tostring(H.GUI.w.note.Text) end

-- Runs the plugin inside a coroutine, like the console does.
local function startModal(main, H)
  H.SETTINGS.yieldEvery = 0
  local co = coroutine.create(function() main() end)
  local ok, err = coroutine.resume(co)
  assert(ok, err)
  return function()
    local ok2, err2 = coroutine.resume(co)
    assert(ok2, err2)
    return co
  end, co
end

test("window opens: tiles, live info, preview cells", function()
  local S, main, H = load()
  for fid = 101, 104 do S.addFixture(fid, 10) end
  main()
  eq(S.window()._class, "BaseInput")
  truthy(S.find("pgb_kind_line")); truthy(S.find("pgb_presets")); truthy(S.find("pgb_build"))
  eq(S.find("pgb_txt_shape_count").Content, "10")
  S.type("pgb_txt_rig_fixtures", "101 Thru 104")
  truthy(info(H):find("4 fixtures x 10 px = 40 pixels", 1, true), info(H))
  truthy(info(H):find("grid 40 x 1", 1, true), info(H))
  truthy(note(H):find("Fixture 101: 10 pixels, matches", 1, true), note(H))
  eq(H.GUI.w.build.Enabled, "Yes")
  eq(#H.GUI.w.preview._children, 10)
  eq(H.GUI.w.preview._children[1].Text, "1")
end)

test("window, run like the console: STRIKE M preset, build, rebuild, close", function()
  local S, main, H = load()
  for fid = 101, 104 do S.addFixture(fid, { 14, 14, 14 }) end
  local step, co = startModal(main, H)
  truthy(H.GUI.modal, "waits in its loop inside the coroutine")
  S.popups = { mock.pick("STRIKE M") }
  S.click("pgb_presets"); step()
  eq(H.GUI.state.kind, "rows")
  eq(S.find("pgb_txt_shape_counts").Content, "14,14,14")
  S.type("pgb_txt_rig_fixtures", "101 Thru 104")
  S.type("pgb_txt_rig_group", "50")
  S.type("pgb_txt_rig_layout", "7")
  truthy(info(H):find("4 fixtures x 42 px = 168 pixels", 1, true), info(H))
  truthy(info(H):find("grid 59 x 3", 1, true), info(H))
  truthy(info(H):find("parts: Tubes, Face", 1, true), info(H))
  eq(#H.GUI.w.preview._children, 42)

  S.click("pgb_build"); step()
  noProblems(S)
  eq(#S.groups[50].cells, 168); eq(S.groups[51].name, "StrikeM Tubes"); eq(S.groups[52].name, "StrikeM Face")
  eq(#S.layouts[7].handle._children, 168)
  truthy(note(H):find("Built Groups 50-52, Layout 7", 1, true), note(H))

  -- Building again replaces what this window built, without asking.
  S.click("pgb_build"); step()
  noProblems(S)
  eq(#S.groups[50].cells, 168)

  S.click("pgb_close"); step()
  eq(coroutine.status(co), "dead")
  eq(S.vars["PGB_gui.kind"], "rows")
end)

test("window: closing with the title bar X ends the plugin", function()
  local S, main, H = load()
  local step, co = startModal(main, H)
  S.globals.Obj.Delete(S.overlay, 1)
  step()
  eq(coroutine.status(co), "dead")
end)

test("window: bad shape values disable Build and say why", function()
  local S, main, H = load()
  S.addFixture(101, 42)
  main()
  S.click("pgb_kind_rows")
  S.type("pgb_txt_shape_counts", "14,x")
  eq(H.GUI.w.build.Enabled, "No")
  eq(H.GUI.w.note.TextColor, "errorText")
  truthy(note(H):find("Pixels per row"), note(H))
  S.type("pgb_txt_shape_counts", "14,14,14")
  S.type("pgb_txt_rig_fixtures", "101")
  eq(H.GUI.w.build.Enabled, "Yes")
end)

test("window: +/- buttons, advanced view, rotate and flip", function()
  local S, main, H = load()
  main()
  S.click("pgb_kind_line")
  S.click("pgb_inc_shape_count")
  eq(S.find("pgb_txt_shape_count").Content, "11")
  eq(S.find("pgb_rotate"), nil, "advanced is hidden at first")
  S.click("pgb_adv")
  local rot = S.click("pgb_rotate")
  eq(rot.Text, "Rotate 90")
  truthy(H.GUI.previewSig:find("^1x11"), "preview turned to a vertical line")
  local flip = S.click("pgb_chk_rig_flipH")
  eq(flip.State, 1); eq(H.GUI.state.rig.flipH, true)
  truthy(S.find("pgb_txt_rig_subs")); truthy(S.find("pgb_chk_shape_reverse"))
  S.click("pgb_adv")
  eq(S.find("pgb_rotate"), nil)
end)

test("window: selection is used and keeps its arrangement", function()
  local S, main, H = load()
  for fid = 1, 4 do S.addFixture(fid, 6) end
  S.preselect({ { 1, 0, 0 }, { 2, 1, 0 }, { 3, 0, 1 }, { 4, 1, 1 } })
  main()
  eq(S.find("pgb_txt_rig_fixtures").Content, "sel")
  S.click("pgb_kind_line")
  truthy(note(H):find("has 6 pixels, the shape 10", 1, true), note(H))
  S.type("pgb_txt_shape_count", "6")
  truthy(info(H):find("4 fixtures x 6 px = 24 pixels   |   grid 12 x 2", 1, true), info(H))
  truthy(info(H):find("selection", 1, true))
  S.type("pgb_txt_rig_fixtures", "3")
  S.click("pgb_sel")
  eq(S.find("pgb_txt_rig_fixtures").Content, "sel")
end)

test("window: save, apply and delete your own preset", function()
  local S, main, H = load()
  main()
  S.click("pgb_kind_hex")
  S.type("pgb_txt_rig_name", "MyWash")
  S.click("pgb_adv")
  S.click("pgb_inc_shape_start")
  S.texts = { "My Wash" }
  S.click("pgb_save")
  truthy(S.vars["PGB_presets"]:find("My Wash", 1, true))
  S.click("pgb_kind_line")
  eq(H.GUI.state.rig.name, "Line")
  S.popups = { mock.pick("Saved: My Wash") }
  S.click("pgb_presets")
  eq(H.GUI.state.kind, "hex"); eq(H.GUI.state.rig.name, "MyWash")
  eq(tostring(H.GUI.state.shape.hex.start), "30")
  S.popups = { mock.pick("Delete a saved preset"), mock.pick("My Wash") }
  S.click("pgb_presets")
  eq(#H.GUI.loadSaved(), 0)
end)

test("window: asks before overwriting a group it didn't build", function()
  local S, main, H = load()
  S.addFixture(101, 10)
  S.globals.Cmd("ClearSelection"); S.globals.Cmd("Store Group 5 /Overwrite")
  main()
  S.click("pgb_kind_line")
  S.type("pgb_txt_rig_fixtures", "101")
  S.type("pgb_txt_rig_group", "5")
  S.click("pgb_chk_rig_layoutOn")
  truthy(note(H):find("Will overwrite Group 5", 1, true), note(H))
  local asked
  S.boxes = { function(spec) asked = spec.message return { result = 0 } end }
  S.click("pgb_build")
  truthy(asked and asked:find("Group 5"))
  eq(#S.groups[5].cells, 0, "cancelled")
  S.boxes = { mock.button(1) }
  S.click("pgb_build")
  eq(#S.groups[5].cells, 10)
  eq(S.layouts[1], nil, "layout was unticked")
end)

test("window: Group N as source, custom map labels, too-big preview", function()
  local S, main, H = load()
  for fid = 1, 2 do S.addFixture(fid, 9) end
  S.preselect({ { 1, 0, 0 }, { 2, 0, 1 } })
  S.globals.Cmd("Store Group 20 /Overwrite")
  S.globals.Cmd("ClearSelection")
  main()
  S.click("pgb_kind_custom")
  S.type("pgb_txt_shape_map", "Ring: 1 2 3 / 8 . 4 / 7 6 5 // Center: 9")
  eq(H.GUI.w.preview._children[1].Text, "1")
  S.type("pgb_txt_rig_fixtures", "Group 20")
  truthy(info(H):find("Fixtures from Group 20", 1, true), info(H))
  S.type("pgb_txt_rig_group", "30")
  S.click("pgb_build")
  noProblems(S)
  local w, h = extent(S.groups[30].cells)
  eq(w, 3); eq(h, 5 * 2 + 1, "two fixtures stacked as in the group")
  S.click("pgb_kind_line")
  S.type("pgb_txt_shape_count", "200")
  eq(#H.GUI.w.preview._children, 1)
  truthy(H.GUI.w.preview._children[1].Text:find("too big"))
end)

test("window: Inspect button shows the first fixture", function()
  local S, main, H = load()
  S.addFixture(101, { 14, 14, 14 })
  main()
  S.type("pgb_txt_rig_fixtures", "101")
  S.click("pgb_adv")
  local text
  S.boxes = { function(spec) text = spec.message return { result = 1 } end }
  S.click("pgb_inspect")
  truthy(text and text:find("42 pixels"), tostring(text))
end)

test("window: change signals while the window is built don't misplace the preview", function()
  local S, main, H = load()
  S.addFixture(101, 10)
  S.fireOnContent = true
  main()
  S.click("pgb_adv")
  local preview = H.GUI.w.preview
  eq(preview.Anchors, "0," .. H.GUI.w.previewRow)
  local grids = 0
  for _, c in ipairs(H.GUI.w.frame._children) do
    if c.Anchors == "0," .. H.GUI.w.previewRow then grids = grids + 1 end
  end
  eq(grids, 1, "exactly one thing in the preview row")
  eq(#S.errors, 0, table.concat(S.errors, " | "))
end)

test("falls back to the classic dialogs if the window can't open", function()
  local S, main = load()
  S.failAppend = true
  local title
  S.popups = { function(spec) title = spec.title return nil end }
  main()
  truthy(title and title:find("what are you building"), tostring(title))
  truthy(table.concat(S.errors, "\n"):find("Couldn't open the window", 1, true))
end)

print(string.format("\n%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
