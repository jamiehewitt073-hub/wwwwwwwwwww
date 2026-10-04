--[[
================================================================================
  PIXEL GRID BUILDER - grandMA3 plugin                                  v2.0.0
================================================================================
  Quickly builds SELECTION GRIDS (stored as groups) and LAYOUT VIEWS for
  multi-instance pixel fixtures:

    * pixel washes   - hex layouts (1-6-12-18 ...) or any ring counts
    * pixel lines    - bars, battens, tubes
    * matrices       - panels, blinders
    * multi-row bars - strobe tube + RGB rows (Color STRIKE M / JDC1 style)
    * anything else  - type a custom pixel map

  Run the plugin: a window opens. Tap a shape, check the live preview, enter
  your fixtures, tick Group / Layout and tap Build. "Advanced..." shows the
  rest (rotation, fixtures per row, pixel order, sub-IDs, saved presets).

  For every fixture it places each pixel (subfixture) in the selection grid
  with the "Grid x/y" keyword, then stores:
    * one group with the whole pixel grid
    * optionally one group per part (e.g. "Tubes" / "Face", "Center" / "Ring 1")
    * optionally a layout view with every pixel at its physical position
    * optionally the pixel shape to the fixture type (GridStore)

  Run it with the argument "classic" for the old step-by-step dialogs:
    Plugin "Pixel Grid Builder" "classic"

  Edit SETTINGS and USER_PRESETS below to taste.
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
  -- Layout view Y axis. true = a higher PosY is further up the screen.
  -- If your layouts come out upside down, set this to false.
  layoutYUp = true,

  -- How much of each layout cell the element fills (0.5 - 1.0).
  layoutFill = 0.9,

  -- Remember the values you typed last time (stored as user variables).
  rememberValues = true,

  -- Print every command the plugin sends to the System Monitor.
  echoCommands = false,

  -- Let the console redraw (progress bar) every N commands. 0 = never.
  yieldEvery = 100,
}

--------------------------------------------------------------------------------
-- USER PRESETS
-- Add your own fixtures here. They show up at the top of the Presets list.
-- (You can also save presets straight from the window: Advanced > Save preset.)
--   kind   = "line" | "matrix" | "rows" | "hex" | "rings" | "custom"
--   values = shape fields (see KIND_INFO below), anything left out uses
--            the normal default
--   name   = default name for groups / layout
--   gap    = default gap (cells) between fixtures
--------------------------------------------------------------------------------
local USER_PRESETS = {
  -- { label = "My JDC1s: tube + plates, 2 x 12", kind = "rows",
  --   values = { counts = "12,12", names = "Tube,Plates" }, name = "JDC1", gap = 1 },
  -- { label = "My odd fixture", kind = "custom",
  --   values = { map = "Ring: . 1 2 . / 8 . . 3 / 7 . . 4 / . 6 5 . // Center: 9" },
  --   name = "Odd", gap = 1 },
}

--------------------------------------------------------------------------------
-- BUILT-IN PRESETS
--------------------------------------------------------------------------------
local PRESETS = {
  { label = "Color STRIKE M style - tube/face/tube 3 x 14", kind = "rows",
    values = { counts = "14,14,14", names = "Tubes,Face,Tubes" }, name = "StrikeM", gap = 1 },
  { label = "Hex 19 - Spiider / B-EYE K10 style", kind = "hex",
    values = { rings = 2 }, name = "Hex19", gap = 1 },
  { label = "Hex 37 - B-EYE K20 style", kind = "hex",
    values = { rings = 3 }, name = "Hex37", gap = 1 },
  { label = "Matrix 5 x 5 - MagicPanel FX style", kind = "matrix",
    values = { cols = 5, rows = 5 }, name = "Panel5x5", gap = 1 },
  { label = "Matrix 6 x 6 - MagicPanel 602 style", kind = "matrix",
    values = { cols = 6, rows = 6 }, name = "Panel6x6", gap = 1 },
  { label = "Pixel bar 20 - impression X4 Bar 20 style", kind = "line",
    values = { count = 20 }, name = "Bar20", gap = 0 },
}

local TITLE = "Pixel Grid Builder"
local ITEM_INSPECT = "Inspect fixture (list its subfixtures)"
local ITEM_HELP = "Help"

--------------------------------------------------------------------------------
-- SHAPE FIELDS
-- type: "int" | "text" | "bool"
-- basic = shown in the simple window, the rest live under Advanced.
-- short = label used in the window.
--------------------------------------------------------------------------------
local KIND_ORDER = { "line", "matrix", "rows", "hex", "rings", "custom" }

local KIND_INFO = {
  line = {
    title = "Pixel line", menu = "Pixel line / bar", short = "Line",
    name = "Line",
    gap = 0,
    fields = {
      { key = "count",    label = "Pixels",             type = "int",  default = 10, min = 1, max = 2048, basic = true },
      { key = "vertical", label = "Vertical",           type = "bool", default = false },
      { key = "reverse",  label = "Pixel 1 at the end", type = "bool", default = false, short = "Pixel 1 at end" },
    },
  },
  matrix = {
    title = "Matrix / panel", menu = "Matrix / panel", short = "Matrix",
    name = "Matrix",
    gap = 1,
    fields = {
      { key = "cols",        label = "Columns",                  type = "int",  default = 6, min = 1, max = 512, basic = true },
      { key = "rows",        label = "Rows",                     type = "int",  default = 6, min = 1, max = 512, basic = true },
      { key = "columnOrder", label = "Count down columns first", type = "bool", default = false, short = "Columns first" },
      { key = "snake",       label = "Snake / zig-zag",          type = "bool", default = false, short = "Snake" },
      { key = "startRight",  label = "Pixel 1 on the right",     type = "bool", default = false, short = "Start right" },
      { key = "startBottom", label = "Pixel 1 at the bottom",    type = "bool", default = false, short = "Start bottom" },
    },
  },
  rows = {
    title = "Multi-row bar", menu = "Multi-row bar (strobe tube + RGB rows)", short = "Multi-row",
    name = "Bar",
    gap = 1,
    message = "One number per row, top to bottom, in the order the pixels are numbered.\n"
      .. "Rows with the same name end up in the same part group.",
    fields = {
      { key = "counts", label = "Pixels per row",       type = "text", default = "14,14,14", basic = true },
      { key = "names",  label = "Row names (parts)",    type = "text", default = "Tubes,Face,Tubes", short = "Row names" },
      { key = "rtl",    label = "Pixel 1 on the right", type = "bool", default = false, short = "Start right" },
      { key = "snake",  label = "Snake rows",           type = "bool", default = false },
    },
  },
  hex = {
    title = "Hex pixel wash", menu = "Hex pixel wash (center + rings)", short = "Hex",
    name = "Hex",
    gap = 1,
    message = "Rings around the center: 1 = 7 pixels, 2 = 19, 3 = 37, 4 = 61.",
    fields = {
      { key = "rings",     label = "Rings",                        type = "int",  default = 2, min = 0, max = 10, basic = true },
      { key = "start",     label = "Start angle (0 = 12 o'clock)", type = "int",  default = 0, min = 0, max = 359, step = 30, short = "Start angle" },
      { key = "ccw",       label = "Counter-clockwise",            type = "bool", default = false },
      { key = "outsideIn", label = "Outer ring first",             type = "bool", default = false },
    },
  },
  rings = {
    title = "Ring pixel wash", menu = "Ring pixel wash (your own ring counts)", short = "Rings",
    name = "Rings",
    gap = 1,
    message = "Pixels per ring from the inside out. Start with 1 for a center pixel.\n"
      .. "Example: 1,6,12  or  8,16,24",
    fields = {
      { key = "counts",    label = "Pixels per ring",              type = "text", default = "1,6,12", basic = true },
      { key = "start",     label = "Start angle (0 = 12 o'clock)", type = "int",  default = 0, min = 0, max = 359, step = 30, short = "Start angle" },
      { key = "scale",     label = "Grid scale (0 = auto)",        type = "int",  default = 0, min = 0, max = 32, short = "Grid scale" },
      { key = "ccw",       label = "Counter-clockwise",            type = "bool", default = false },
      { key = "outsideIn", label = "Outer ring first",             type = "bool", default = false },
    },
  },
  custom = {
    title = "Custom pixel map", menu = "Custom pixel map (type the layout)", short = "Custom",
    name = "Custom",
    gap = 1,
    message = "Type the pixel sub-IDs as they sit on the fixture.\n"
      .. "  /  starts a new row      .  is an empty cell\n"
      .. "  4-9  or  4 Thru 9  fills a run of cells      2.3  is a nested sub-ID\n"
      .. "  Name:  at the start of a row starts a new part (group)\n"
      .. "Example:  Tubes: 1-14 / Face: 15-28 / Tubes: 29-42",
    fields = {
      { key = "map", label = "Pixel map", type = "text", default = "1 2 3 / 8 . 4 / 7 6 5", basic = true },
    },
  },
}

local RIG_FIELDS = {
  { key = "fixtures",   label = "Fixtures",                        type = "text", default = "101 Thru 110" },
  { key = "subs",       label = "Pixel sub-IDs",                   type = "text", default = "auto" },
  { key = "perRow",     label = "Fixtures per row (0 = one row)",  type = "int",  default = 0, min = 0, max = 9999, short = "Per row" },
  { key = "gap",        label = "Gap between fixtures",            type = "int",  default = 1, min = 0, max = 100, short = "Gap" },
  { key = "rotate",     label = "Rotate (0/90/180/270)",           type = "int",  default = 0, min = 0, max = 270 },
  { key = "name",       label = "Name",                            type = "text", default = "Pixels" },
  { key = "group",      label = "Group no. (0 = none)",            type = "int",  default = 1, min = 0, max = 99999, guiMin = 1 },
  { key = "layout",     label = "Layout no. (0 = none)",           type = "int",  default = 1, min = 0, max = 99999, guiMin = 1 },
  { key = "cellSize",   label = "Layout cell size",                type = "int",  default = 40, min = 4, max = 1000, step = 5, short = "Cell size" },
  { key = "flipH",      label = "Flip left-right",                 type = "bool", default = false },
  { key = "flipV",      label = "Flip up-down",                    type = "bool", default = false },
  { key = "alternate",  label = "Turn every 2nd fixture 180",      type = "bool", default = false },
  { key = "partGroups", label = "Also store one group per part",   type = "bool", default = true },
  { key = "gridStore",  label = "GridStore shape to fixture type", type = "bool", default = false },
  { key = "keepSel",    label = "Keep the grid selected",          type = "bool", default = true },
}

local HELP_TEXT = [[
1. Patch your pixel fixtures (all the same type and mode).
2. Run the plugin and pick a shape, or a Quick preset.
3. Set the shape (pixels, rows, rings ...).
4. Set the rig:
   Fixtures  -  101 Thru 116,  101-108 + 201-208,  Group 5,  or  sel  for
                the current selection. With Group / sel and Fixtures per
                row = 0, the grid arrangement of the main fixtures is kept.
   Pixel sub-IDs  -  auto  uses the fixture's subfixtures in patch order.
                Or type them in pixel order:  1 Thru 42,  2-43,
                15-28, 1-14, 29-42,  1.1-1.14 ...
   Group / Layout no.  -  where to store (0 = don't store).
5. Check the summary and press Build.

Not sure how your fixture's pixels are numbered? Use "Inspect fixture"
- it prints the subfixture tree to the System Monitor.

Pixels in the wrong order? Change the start angle / direction / snake
options, or reorder the Pixel sub-IDs list.]]

local GUI_HELP = [[
1. Tap the shape of your fixture (Line, Matrix, Multi-row, Hex, Rings,
   Custom) or pick one from Presets.
2. Set the pixel count. The preview shows pixel 1, 2, 3 ... of one fixture.
3. Fixtures: type  101 Thru 116,  101-108 + 201-208,  Group 5,
   or tap Use selection.
4. Tick Group and / or Layout, check the numbers, tap Build.
   The window stays open: change something and Build again to replace it.

Advanced...
  Rotate / flip       how the fixtures hang
  Per row / Gap       how the fixtures sit next to each other
                      (with a selection or a group and Per row 0, their
                      own grid arrangement is kept)
  Pixel order         start corner, direction, snake ...
  Pixel sub-IDs       auto = patch order, or type them in pixel order,
                      e.g. 15-28, 1-14, 29-42.  Inspect shows the numbering.
  Part groups         one extra group per part (Tubes / Face, rings ...)
  GridStore           store the shape on the fixture type
  Save preset         keep the current setup in the Presets list]]

--------------------------------------------------------------------------------
-- PURE HELPERS (no grandMA3 API in here)
--------------------------------------------------------------------------------
local P = {}

local SQRT3_2 = math.sqrt(3) / 2
local atan2 = math.atan2 or math.atan

function P.trim(s)
  return (tostring(s == nil and "" or s):gsub("^%s+", ""):gsub("%s+$", ""))
end

function P.round(v)
  return math.floor(v + 0.5)
end

function P.clean(s)
  -- Names end up inside "quotes" on the command line.
  local out = P.trim(s):gsub('[%%";]', "")
  return out
end

function P.toBool(v)
  if type(v) == "boolean" then return v end
  if type(v) == "number" then return v ~= 0 end
  local s = P.trim(v):lower()
  return s == "1" or s == "true" or s == "yes" or s == "on"
end

function P.toInt(v, min, max)
  local n = tonumber(P.trim(v))
  if not n or n ~= math.floor(n) then return nil end
  n = math.floor(n)
  if (min and n < min) or (max and n > max) then return nil end
  return n
end

function P.isSubId(s)
  return type(s) == "string" and s:match("^[%d%.]+$") ~= nil and not s:find("%.%.")
    and not s:match("^%.") and not s:match("%.$")
end

-- "2.1","2.14" -> {"2.1", ..., "2.14"}; "14","1" -> {"14", ..., "1"}
function P.expandSubRange(a, b)
  local pa, la = a:match("^(.-)(%d+)$")
  local pb, lb = b:match("^(.-)(%d+)$")
  if not pa or not pb or pa ~= pb then return nil end
  la, lb = tonumber(la), tonumber(lb)
  if math.abs(lb - la) > 4096 then return nil end
  local out = {}
  local step = (lb >= la) and 1 or -1
  for v = la, lb, step do out[#out + 1] = pa .. string.format("%d", v) end
  return out
end

local function normalizeRanges(s)
  s = s:gsub("%s+[Tt][Hh][Rr][Uu]%s+", "-"):gsub("%s*%-%s*", "-")
  return s
end

-- "101 Thru 110 + 201-204, 301" -> {101, ..., 110, 201, ..., 204, 301}
function P.parseIdList(text)
  local s = normalizeRanges(" " .. P.trim(text) .. " ")
  local ids, seen = {}, {}
  local function add(v)
    if not seen[v] then seen[v] = true; ids[#ids + 1] = v end
  end
  for item in s:gmatch("[^,%+%s]+") do
    local a, b = item:match("^(%d+)%-(%d+)$")
    if a then
      a, b = tonumber(a), tonumber(b)
      if math.abs(b - a) > 10000 then return nil, "Range too large: " .. item end
      for v = a, b, (b >= a) and 1 or -1 do add(v) end
    elseif item:match("^%d+$") then
      add(tonumber(item))
    else
      return nil, "Can't read '" .. item .. "' in the fixture list."
    end
  end
  if #ids == 0 then return nil, "No fixture IDs given." end
  return ids
end

-- "1 Thru 14, 2.1-2.5, 30" -> {"1", ..., "14", "2.1", ..., "2.5", "30"}
function P.parseSubIdList(text)
  local s = normalizeRanges(" " .. P.trim(text) .. " ")
  local list = {}
  for item in s:gmatch("[^,%+%s]+") do
    local a, b = item:match("^%.?([%d%.]+)%-%.?([%d%.]+)$")
    if a then
      local r = P.isSubId(a) and P.isSubId(b) and P.expandSubRange(a, b)
      if not r then
        return nil, "Can't read the range '" .. item .. "'. Both ends need the same prefix, e.g. 2.1 Thru 2.14."
      end
      for _, v in ipairs(r) do list[#list + 1] = v end
    else
      local id = item:gsub("^%.", "")
      if not P.isSubId(id) then return nil, "Can't read '" .. item .. "' in the sub-ID list." end
      list[#list + 1] = id
    end
  end
  if #list == 0 then return nil, "No sub-IDs given." end
  return list
end

function P.parseNumberList(text, min, max)
  local out = {}
  for item in tostring(text or ""):gmatch("[^,%+%s/]+") do
    local n = P.toInt(item, min, max)
    if not n then return nil, "Can't read '" .. item .. "' (numbers " .. min .. "-" .. max .. ")." end
    out[#out + 1] = n
  end
  if #out == 0 then return nil, "No numbers given." end
  return out
end

function P.parseNameList(text)
  local out = {}
  for item in (tostring(text or "") .. ","):gmatch("([^,]*),") do
    out[#out + 1] = P.clean(item)
  end
  return out
end

--------------------------------------------------------------------------------
-- SHAPES
-- A shape is a list of cells. Each cell has:
--   gx, gy  integer selection grid position (x right, y down)
--   lx, ly  layout position in pixel units (x right, y down)
--   part    part name (one group per part)
--   order   pixel number in the fixture's pixel order (generated shapes), or
--   sub     a literal sub-ID like "3" or "2.5" (custom maps)
--------------------------------------------------------------------------------
local function newShape(kind)
  return { kind = kind, cells = {}, parts = {}, partSeen = {} }
end

local function addCell(shape, c)
  shape.cells[#shape.cells + 1] = c
  if not shape.partSeen[c.part] then
    shape.partSeen[c.part] = true
    shape.parts[#shape.parts + 1] = c.part
  end
end

function P.normalize(shape)
  local minGX, minGY, minLX, minLY = math.huge, math.huge, math.huge, math.huge
  local maxGX, maxGY, maxLX, maxLY = -math.huge, -math.huge, -math.huge, -math.huge
  for _, c in ipairs(shape.cells) do
    minGX = math.min(minGX, c.gx); maxGX = math.max(maxGX, c.gx)
    minGY = math.min(minGY, c.gy); maxGY = math.max(maxGY, c.gy)
    minLX = math.min(minLX, c.lx); maxLX = math.max(maxLX, c.lx)
    minLY = math.min(minLY, c.ly); maxLY = math.max(maxLY, c.ly)
  end
  for _, c in ipairs(shape.cells) do
    c.gx, c.gy = c.gx - minGX, c.gy - minGY
    c.lx, c.ly = c.lx - minLX, c.ly - minLY
  end
  shape.gw, shape.gh = maxGX - minGX + 1, maxGY - minGY + 1
  shape.lw, shape.lh = maxLX - minLX, maxLY - minLY
  return shape
end

-- Rounds float positions to the grid, growing the scale until no two cells
-- share a grid position. Returns the scale used.
function P.quantize(cells, minScale)
  -- Round halves away from zero so shapes stay symmetric.
  local function round(v)
    if v >= 0 then return math.floor(v + 0.5 + 1e-9) end
    return -math.floor(-v + 0.5 + 1e-9)
  end
  for s = math.max(1, minScale or 1), 64 do
    local used, ok = {}, true
    for _, c in ipairs(cells) do
      local gx, gy = round(c.lx * s), round(c.ly * s)
      local key = gx .. "/" .. gy
      if used[key] then ok = false; break end
      used[key] = true
      c.gx, c.gy = gx, gy
    end
    if ok then return s end
  end
  return nil
end

-- Clock-style sort key: 0 at the start angle, growing in the chosen direction.
local function angleKey(x, y, start, ccw)
  if math.abs(x) < 1e-9 and math.abs(y) < 1e-9 then return 0 end
  local a = math.deg(atan2(y, x)) + 90 - start   -- 0 = 12 o'clock (y is down)
  if ccw then a = -a end
  a = a % 360
  if a > 360 - 1e-6 then a = 0 end
  return a
end

function P.shapeLine(v)
  local shape = newShape("line")
  for i = 1, v.count do
    local p = v.reverse and (v.count - i) or (i - 1)
    local x, y = p, 0
    if v.vertical then x, y = 0, p end
    addCell(shape, { gx = x, gy = y, lx = x, ly = y, part = "Pixels", order = i })
  end
  return shape
end

function P.shapeMatrix(v)
  local shape = newShape("matrix")
  local cols, rows = v.cols, v.rows
  for i = 0, cols * rows - 1 do
    local c, r
    if v.columnOrder then
      c, r = math.floor(i / rows), i % rows
      if v.snake and c % 2 == 1 then r = rows - 1 - r end
    else
      r, c = math.floor(i / cols), i % cols
      if v.snake and r % 2 == 1 then c = cols - 1 - c end
    end
    if v.startRight then c = cols - 1 - c end
    if v.startBottom then r = rows - 1 - r end
    addCell(shape, { gx = c, gy = r, lx = c, ly = r, part = "Pixels", order = i + 1 })
  end
  return shape
end

function P.shapeRows(v)
  local counts, err = P.parseNumberList(v.counts, 1, 2048)
  if not counts then return nil, "Pixels per row: " .. err end
  local names = P.parseNameList(v.names)
  local shape = newShape("rows")
  local maxLen = 0
  for _, n in ipairs(counts) do maxLen = math.max(maxLen, n) end
  local order = 0
  for j, n in ipairs(counts) do
    local part = names[j]
    if not part or part == "" then part = "Row " .. j end
    local offG = math.floor((maxLen - n) / 2)
    local offL = (maxLen - n) / 2
    local rtl = v.rtl
    if v.snake and j % 2 == 0 then rtl = not rtl end
    for k = 0, n - 1 do
      local c = rtl and (n - 1 - k) or k
      order = order + 1
      addCell(shape, { gx = offG + c, gy = j - 1, lx = offL + c, ly = j - 1, part = part, order = order })
    end
  end
  return shape
end

function P.shapeHex(v)
  local R = v.rings
  local list = {}
  for q = -R, R do
    for r = -R, R do
      local ring = math.max(math.abs(q), math.abs(r), math.abs(q + r))
      if ring <= R then
        local x, y = q + r / 2, r * SQRT3_2
        list[#list + 1] = { ring = ring, gx = 2 * q + r, gy = r, lx = x, ly = y,
          key = angleKey(x, y, v.start, v.ccw) }
      end
    end
  end
  table.sort(list, function(a, b)
    if a.ring ~= b.ring then
      if v.outsideIn then return a.ring > b.ring end
      return a.ring < b.ring
    end
    return a.key < b.key
  end)
  local shape = newShape("hex")
  for i, c in ipairs(list) do
    addCell(shape, { gx = c.gx, gy = c.gy, lx = c.lx, ly = c.ly, order = i,
      part = (c.ring == 0) and "Center" or ("Ring " .. c.ring) })
  end
  return shape
end

function P.shapeRings(v)
  local counts, err = P.parseNumberList(v.counts, 1, 1024)
  if not counts then return nil, "Pixels per ring: " .. err end
  local hasCenter = counts[1] == 1
  local ringOrder = {}
  for j = 1, #counts do ringOrder[#ringOrder + 1] = j end
  if v.outsideIn then
    for j = 1, #counts do ringOrder[j] = #counts - j + 1 end
  end
  local shape = newShape("rings")
  local cells = {}
  for _, j in ipairs(ringOrder) do
    local n = counts[j]
    local radius = hasCenter and (j - 1) or j
    for i = 0, n - 1 do
      local a = math.rad((v.start - 90) + (v.ccw and -1 or 1) * i * 360 / n)
      local x, y = radius * math.cos(a), radius * math.sin(a)
      if math.abs(x) < 1e-9 then x = 0 end
      if math.abs(y) < 1e-9 then y = 0 end
      cells[#cells + 1] = { lx = x, ly = y, order = #cells + 1,
        part = (radius == 0) and "Center" or ("Ring " .. radius) }
    end
  end
  -- Spread the layout so the closest two pixels are one cell apart.
  local minDist = math.huge
  for i = 1, #cells do
    for j = i + 1, #cells do
      local dx, dy = cells[i].lx - cells[j].lx, cells[i].ly - cells[j].ly
      minDist = math.min(minDist, math.sqrt(dx * dx + dy * dy))
    end
  end
  if minDist > 1e-6 and minDist < 1 then
    for _, c in ipairs(cells) do c.lx, c.ly = c.lx / minDist, c.ly / minDist end
  end
  local scale = P.quantize(cells, v.scale)
  if not scale then return nil, "These rings don't fit on a grid. Try fewer pixels per ring." end
  for _, c in ipairs(cells) do addCell(shape, c) end
  shape.scale = scale
  return shape
end

function P.shapeCustom(v)
  local map = tostring(v.map or ""):gsub("\r", "")
  if P.trim(map) == "" then return nil, "The pixel map is empty." end
  local shape = newShape("custom")
  local part, y, seen = "Pixels", 0, {}
  for rowText in (map .. "/"):gmatch("([^/|\n]*)[/|\n]") do
    local text = rowText
    local label, rest = text:match("^%s*(%a[^:]*):(.*)$")
    if label then
      part = P.clean(label)
      if part == "" then part = "Pixels" end
      text = rest
    end
    local tokens = {}
    for tok in text:gmatch("[^%s,]+") do tokens[#tokens + 1] = tok end
    local x, i = 0, 1
    while i <= #tokens do
      local t = tokens[i]
      if tokens[i + 1] and tokens[i + 1]:lower() == "thru" and tokens[i + 2] then
        t = t .. "-" .. tokens[i + 2]
        i = i + 3
      else
        i = i + 1
      end
      if t == "." or t == "-" or t == "_" then
        x = x + 1
      else
        local subs
        local a, b = t:match("^%.?([%d%.]+)%-%.?([%d%.]+)$")
        if a then
          subs = P.isSubId(a) and P.isSubId(b) and P.expandSubRange(a, b)
        else
          local id = t:gsub("^%.", "")
          if P.isSubId(id) then subs = { id } end
        end
        if not subs then
          return nil, "Pixel map row " .. (y + 1) .. ": can't read '" .. t .. "'."
        end
        for _, s in ipairs(subs) do
          if seen[s] then return nil, "Pixel map: sub-ID " .. s .. " is used twice." end
          seen[s] = true
          addCell(shape, { gx = x, gy = y, lx = x, ly = y, part = part, sub = s })
          x = x + 1
        end
      end
    end
    y = y + 1
  end
  if #shape.cells == 0 then return nil, "The pixel map has no pixels in it." end
  shape.literal = true
  return shape
end

local SHAPE_BUILDERS = {
  line = P.shapeLine, matrix = P.shapeMatrix, rows = P.shapeRows,
  hex = P.shapeHex, rings = P.shapeRings, custom = P.shapeCustom,
}

-- Converts dialog values (strings / booleans) into typed values.
function P.coerce(fields, values)
  local out = {}
  for _, f in ipairs(fields) do
    local raw = values[f.key]
    if raw == nil then raw = f.default end
    if f.type == "int" then
      local n = P.toInt(raw, f.min, f.max)
      if not n then
        return nil, string.format("%s must be a whole number from %d to %d.", f.label, f.min, f.max)
      end
      out[f.key] = n
    elseif f.type == "bool" then
      out[f.key] = P.toBool(raw)
    else
      out[f.key] = raw == nil and "" or tostring(raw)
    end
  end
  return out
end

function P.buildShape(kind, values)
  local info = KIND_INFO[kind]
  local v, err = P.coerce(info.fields, values)
  if not v then return nil, err end
  local shape
  shape, err = SHAPE_BUILDERS[kind](v)
  if not shape then return nil, err end
  if #shape.cells == 0 then return nil, "The shape has no pixels." end
  shape.pixelCount = #shape.cells
  return P.normalize(shape)
end

function P.copyShape(shape)
  local out = {}
  for k, val in pairs(shape) do out[k] = val end
  out.cells = {}
  for i, c in ipairs(shape.cells) do
    local cc = {}
    for k, val in pairs(c) do cc[k] = val end
    out.cells[i] = cc
  end
  return out
end

-- Gives each generated cell its sub-ID: pixel n gets subs[n].
function P.assignSubs(shape, subs)
  for _, c in ipairs(shape.cells) do
    if c.order then c.sub = subs[c.order] end
  end
end

-- Flip, then rotate clockwise by 0/90/180/270. Returns a new, normalized shape.
function P.transform(shape, rot, flipH, flipV)
  local out = P.copyShape(shape)
  local gw, gh, lw, lh = shape.gw, shape.gh, shape.lw, shape.lh
  rot = rot % 360
  for _, c in ipairs(out.cells) do
    local gx, gy, lx, ly = c.gx, c.gy, c.lx, c.ly
    if flipH then gx, lx = gw - 1 - gx, lw - lx end
    if flipV then gy, ly = gh - 1 - gy, lh - ly end
    if rot == 90 then
      gx, gy, lx, ly = gh - 1 - gy, gx, lh - ly, lx
    elseif rot == 180 then
      gx, gy, lx, ly = gw - 1 - gx, gh - 1 - gy, lw - lx, lh - ly
    elseif rot == 270 then
      gx, gy, lx, ly = gy, gw - 1 - gx, ly, lw - lx
    end
    c.gx, c.gy, c.lx, c.ly = gx, gy, lx, ly
  end
  return P.normalize(out)
end

--------------------------------------------------------------------------------
-- RIG
--------------------------------------------------------------------------------
-- Fixture k -> slot (column, row), perRow fixtures per row (0 = one row).
function P.slotsInRows(count, perRow)
  local slots = {}
  for k = 1, count do
    if perRow and perRow > 0 then
      slots[k] = { x = (k - 1) % perRow, y = math.floor((k - 1) / perRow) }
    else
      slots[k] = { x = k - 1, y = 0 }
    end
  end
  return slots
end

-- Keeps the arrangement of selection grid positions, packing used columns
-- and rows together.
function P.slotsFromGrid(list)
  local function ranks(key)
    local vals, seen = {}, {}
    for _, f in ipairs(list) do
      local v = f[key] or 0
      if not seen[v] then seen[v] = true; vals[#vals + 1] = v end
    end
    table.sort(vals)
    local rank = {}
    for i, v in ipairs(vals) do rank[v] = i - 1 end
    return rank
  end
  local rx, ry = ranks("x"), ranks("y")
  local slots = {}
  for k, f in ipairs(list) do slots[k] = { x = rx[f.x or 0], y = ry[f.y or 0] } end
  return slots
end

-- Places every pixel of every fixture. shapeB is used for every 2nd fixture.
function P.place(fixtures, slots, shapeA, shapeB, gap)
  local pitchX, pitchY = shapeA.gw + gap, shapeA.gh + gap
  local lPitchX, lPitchY = shapeA.lw + 1 + gap, shapeA.lh + 1 + gap
  local placed = {}
  for k, fx in ipairs(fixtures) do
    local s = slots[k]
    local shape = (k % 2 == 0) and shapeB or shapeA
    for _, c in ipairs(shape.cells) do
      if c.sub then
        placed[#placed + 1] = {
          fid = fx.fid, sub = c.sub, part = c.part, fixture = k,
          gx = s.x * pitchX + c.gx, gy = s.y * pitchY + c.gy,
          lx = s.x * lPitchX + c.lx, ly = s.y * lPitchY + c.ly,
        }
      end
    end
  end
  return placed
end

-- Width and height of the whole pixel grid, as P.place would lay it out.
function P.gridSize(shape, slots, gap)
  local mx, my = 0, 0
  for _, s in ipairs(slots) do
    mx = math.max(mx, s.x); my = math.max(my, s.y)
  end
  return (mx + 1) * (shape.gw + gap) - gap, (my + 1) * (shape.gh + gap) - gap
end

-- Top-to-bottom, left-to-right: the order a grid is read in.
function P.sortCells(cells)
  local out = {}
  for i, c in ipairs(cells) do out[i] = c end
  table.sort(out, function(a, b)
    if a.gy ~= b.gy then return a.gy < b.gy end
    if a.gx ~= b.gx then return a.gx < b.gx end
    return (a.fixture or 0) < (b.fixture or 0)
  end)
  return out
end

-- Copies cells and moves them so the top-left used cell is 0/0.
function P.toOrigin(cells)
  local minX, minY = math.huge, math.huge
  for _, c in ipairs(cells) do
    minX = math.min(minX, c.gx); minY = math.min(minY, c.gy)
  end
  local out = {}
  for i, c in ipairs(cells) do
    local cc = {}
    for k, v in pairs(c) do cc[k] = v end
    cc.gx, cc.gy = c.gx - minX, c.gy - minY
    out[i] = cc
  end
  return out
end

function P.addr(c)
  return string.format("%d.%s", c.fid, c.sub)
end

-- Commands that build a selection grid from cells.
function P.selectionCommands(cells)
  local cmds = { "ClearSelection" }
  for _, c in ipairs(P.sortCells(cells)) do
    cmds[#cmds + 1] = string.format("Grid %d/%d", c.gx, c.gy)
    cmds[#cmds + 1] = "Fixture " .. P.addr(c)
  end
  return cmds
end

function P.storeGroupCommands(no, name)
  return {
    string.format("Store Group %d /Overwrite", no),
    string.format('Label Group %d "%s"', no, P.clean(name)),
  }
end

-- Layout element positions: all coordinates >= 0, one cell = cellSize.
function P.layoutElements(cells, cellSize, fill, yUp)
  local maxX, maxY = 0, 0
  for _, c in ipairs(cells) do
    maxX = math.max(maxX, c.lx); maxY = math.max(maxY, c.ly)
  end
  local size = math.max(1, P.round(cellSize * fill))
  local margin = P.round((cellSize - size) / 2)
  local out = {}
  for _, c in ipairs(P.sortCells(cells)) do
    local y = yUp and (maxY - c.ly) or c.ly
    out[#out + 1] = {
      addr = P.addr(c),
      x = P.round(c.lx * cellSize) + margin,
      y = P.round(y * cellSize) + margin,
      w = size, h = size,
    }
  end
  return out
end

-- Text picture of a shape, one string per row.
function P.preview(shape)
  local w, h = shape.gw, shape.gh
  local grid, width = {}, 1
  for _, c in ipairs(shape.cells) do
    local label = c.sub or "?"
    grid[c.gy * w + c.gx] = label
    width = math.max(width, #label)
  end
  local lines = {}
  for y = 0, h - 1 do
    local row = {}
    for x = 0, w - 1 do
      local label = grid[y * w + x] or "."
      row[#row + 1] = string.rep(" ", width - #label) .. label
    end
    lines[#lines + 1] = table.concat(row, " ")
  end
  return lines
end

--------------------------------------------------------------------------------
-- grandMA3 API WRAPPERS
--------------------------------------------------------------------------------
local MA = {}
local undoHandle

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

function MA.cmd(command)
  if SETTINGS.echoCommands then MA.log("> " .. command) end
  if undoHandle then return Cmd(command, undoHandle) end
  return Cmd(command)
end

function MA.beginUndo(text)
  local ok, h = pcall(function() return CreateUndo(text) end)
  undoHandle = (ok and h) or nil
end

function MA.endUndo()
  if undoHandle then pcall(function() CloseUndo(undoHandle) end) end
  undoHandle = nil
end

function MA.getVarRaw(key, default)
  local ok, v = pcall(function() return GetVar(UserVars(), "PGB_" .. key) end)
  if ok and v ~= nil and tostring(v) ~= "" then return tostring(v) end
  return default
end

function MA.setVarRaw(key, value)
  if type(value) == "boolean" then value = value and "1" or "0" end
  pcall(function() SetVar(UserVars(), "PGB_" .. key, tostring(value)) end)
end

function MA.getVar(key, default)
  if not SETTINGS.rememberValues then return default end
  return MA.getVarRaw(key, default)
end

function MA.setVar(key, value)
  if SETTINGS.rememberValues then MA.setVarRaw(key, value) end
end

function MA.poolObject(pool, no)
  local ok, obj = pcall(function() return DataPool()[pool][no] end)
  if ok then return obj end
  return nil
end

function MA.firstFree(pool, count, start)
  for no = math.max(1, start), 9999 do
    local free = true
    for j = 0, count - 1 do
      if MA.poolObject(pool, no + j) then free = false; break end
    end
    if free then return no end
  end
  return start
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
  if ok and type(a) == "string" then return P.trim(a) end
  return nil
end

function MA.prop(h, key)
  local ok, v = pcall(function() return h[key] end)
  if ok then return v end
  return nil
end

function MA.setProp(h, key, value)
  local ok = pcall(function() h[key] = value end)
  if not ok then ok = pcall(function() h:Set(key, tostring(value)) end) end
  return ok
end

function MA.fixtureHandle(fid)
  local ok, list = pcall(ObjectList, "Fixture " .. fid)
  if ok and type(list) == "table" and list[1] then return list[1] end
  return nil
end

-- Walks the subfixture tree of a fixture.
-- Returns leaves (sub-IDs of pixels, in patch order) and the full tree.
function MA.subfixtureTree(fid)
  local h = MA.fixtureHandle(fid)
  if not h then return nil, nil, "Fixture " .. fid .. " doesn't exist." end
  local leaves, tree = {}, {}
  local pattern = "^Fixture%s+" .. fid .. "%.([%d%.]+)$"
  local function walk(node, prefix, depth)
    if depth > 8 then return 0 end
    local found, index = 0, 0
    for _, k in ipairs(MA.children(node)) do
      index = index + 1
      -- Subfixtures address as "Fixture 101.2.5". Fall back to the child
      -- index path if the address comes back in some other form.
      local sub
      local a = MA.addrOf(k)
      if a and a:match("^Fixture") then
        sub = a:match(pattern)
      else
        sub = (prefix == "" and "" or (prefix .. ".")) .. index
      end
      if sub then
        found = found + 1
        local entry = { sub = sub, name = tostring(MA.prop(k, "name") or ""), depth = depth }
        tree[#tree + 1] = entry
        entry.children = walk(k, sub, depth + 1)
        if entry.children == 0 then leaves[#leaves + 1] = sub end
      end
    end
    return found
  end
  walk(h, "", 0)
  return leaves, tree, nil, tostring(MA.prop(h, "name") or "")
end

function MA.fidOf(h)
  local fid = tonumber(MA.prop(h, "fid"))
  if fid then return fid end
  local a = MA.addrOf(h)
  return a and tonumber(a:match("^Fixture%s+(%d+)")) or nil
end

-- Main fixtures of the current selection, with their selection grid position.
function MA.readSelection()
  local list, seen = {}, {}
  local ok, idx, x, y = pcall(SelectionFirst)
  local guard = 0
  while ok and idx and guard < 100000 do
    guard = guard + 1
    local okh, h = pcall(GetSubfixture, idx)
    local fid = okh and h and MA.fidOf(h)
    if fid and not seen[fid] then
      seen[fid] = true
      list[#list + 1] = { fid = fid, x = x or 0, y = y or 0 }
    end
    ok, idx, x, y = pcall(SelectionNext, idx)
  end
  return list
end

function MA.selectionCount()
  local ok, n = pcall(SelectionCount)
  if ok and type(n) == "number" then return n end
  return 0
end

local Progress = {}
function Progress.start(total)
  local ok, h = pcall(function() return StartProgress(TITLE) end)
  if not ok or not h then return nil end
  pcall(function() SetProgressRange(h, 0, total) end)
  return h
end
function Progress.set(h, value)
  if h then pcall(function() SetProgress(h, value) end) end
end
function Progress.stop(h)
  if h then pcall(function() StopProgress(h) end) end
end

local function breathe()
  if coroutine.isyieldable and coroutine.isyieldable() then
    pcall(coroutine.yield, 0)
  end
end

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

-- Returns true / false.
function UI.ask(title, text, yes, no)
  local ok, res = pcall(MessageBox, {
    title = title, message = text,
    commands = { { value = 1, name = yes or "Yes" }, { value = 0, name = no or "Cancel" } },
  })
  return ok and type(res) == "table" and res.result == 1
end

-- Shows a list, returns the chosen item string (or nil).
function UI.choose(title, items, caller)
  local ok, idx, value = pcall(PopupInput, { title = title, caller = caller or focusDisplay(), items = items })
  if ok then
    if type(value) == "string" and value ~= "" then return value end
    if type(idx) == "number" then return items[idx] end
    return nil
  end
  -- Fallback when PopupInput isn't available: pick by number.
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
    if not f.hidden then
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
          input.maxTextLength = 2048
        end
        inputs[#inputs + 1] = input
      end
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
    if not f.hidden then
      local label = labels[f.key]
      if f.type == "bool" then
        if res.states and res.states[label] ~= nil then out[f.key] = P.toBool(res.states[label]) end
      elseif res.inputs and res.inputs[label] ~= nil then
        out[f.key] = res.inputs[label]
      end
    end
  end
  return out, res.result
end

--------------------------------------------------------------------------------
-- INSPECT
--------------------------------------------------------------------------------
local function Inspect(fid)
  if not fid then
    local default = MA.getVar("inspect", "101")
    local sel = MA.readSelection()
    if #sel > 0 then default = tostring(sel[1].fid) end
    local ok, text = pcall(TextInput, "Inspect fixture - fixture ID", default)
    if not ok or not text or P.trim(text) == "" then return end
    fid = P.toInt(text, 1)
    if not fid then UI.error("'" .. tostring(text) .. "' isn't a fixture ID.") return end
  end
  MA.setVar("inspect", fid)

  local leaves, tree, err, name = MA.subfixtureTree(fid)
  if not leaves then UI.error(err) return end
  local lines = {}
  lines[#lines + 1] = string.format('Fixture %d "%s": %d subfixtures, %d pixels (subfixtures without children)',
    fid, name or "", #tree, #leaves)
  for _, e in ipairs(tree) do
    lines[#lines + 1] = string.format("%s.%s  %s%s", string.rep("    ", e.depth), e.sub, e.name,
      (e.children > 0) and ("  (" .. e.children .. " inside)") or "")
  end
  for _, l in ipairs(lines) do MA.log(l) end

  local summary = lines[1]
  if #leaves > 0 then
    summary = summary .. "\n\nPixels in patch order:  " .. leaves[1] .. "  ...  " .. leaves[#leaves]
      .. "\n'auto' uses all " .. #leaves .. " of them in this order."
  else
    summary = summary .. "\n\nThis fixture has no subfixtures, so there is nothing to grid."
  end
  local shown = {}
  for i = 2, math.min(#lines, 26) do shown[#shown + 1] = lines[i] end
  if #lines > 26 then shown[#shown + 1] = "... (full list in the System Monitor)" end
  UI.message(TITLE .. " - Fixture " .. fid, summary .. "\n\n" .. table.concat(shown, "\n"))
end

--------------------------------------------------------------------------------
-- BUILD
--------------------------------------------------------------------------------
local function shapeSummary(shape)
  return string.format("%d pixels, %d x %d cells, parts: %s",
    shape.pixelCount, shape.gw, shape.gh, table.concat(shape.parts, ", "))
end

-- Returns fixtures, slots, missing  or  nil, error
local function resolveFixtures(text, perRow)
  local t = P.trim(text):lower()
  local groupNo = t:match("^group%s*(%d+)$")
  if groupNo then
    -- Select the group so its fixtures and grid arrangement can be read.
    MA.cmd("ClearSelection")
    MA.cmd("Group " .. groupNo)
    t = "sel"
  end
  if t == "sel" or t == "selection" or t == "*" then
    local list = MA.readSelection()
    if #list == 0 then
      return nil, "Nothing is selected. Select the fixtures first, or type a list like 101 Thru 116."
    end
    if perRow > 0 then return list, P.slotsInRows(#list, perRow), {} end
    return list, P.slotsFromGrid(list), {}
  end
  local ids, err = P.parseIdList(text)
  if not ids then return nil, err end
  local list, missing = {}, {}
  for _, id in ipairs(ids) do
    if MA.fixtureHandle(id) then list[#list + 1] = { fid = id } else missing[#missing + 1] = id end
  end
  if #list == 0 then return nil, "None of these fixtures exist: " .. P.trim(text) end
  return list, P.slotsInRows(#list, perRow), missing
end

-- Returns the sub-ID list in pixel order, or nil + error (nil + nil = go back).
local function resolvePixels(text, fid, need)
  local t = P.trim(text):lower()
  if t == "" or t == "auto" then
    local leaves, _, err = MA.subfixtureTree(fid)
    if not leaves then return nil, err end
    if #leaves == 0 then
      return nil, "Fixture " .. fid .. " has no subfixtures. Is it patched in a pixel mode?"
    end
    if #leaves == need then return leaves end
    local msg = string.format("Fixture %d has %d pixels (subfixtures), the shape has %d.\n\n"
      .. "Use Inspect fixture to see them, or type the Pixel sub-IDs yourself.", fid, #leaves, need)
    if #leaves > need then
      local ok, res = pcall(MessageBox, {
        title = TITLE, message = msg,
        commands = {
          { value = 1, name = "Use first " .. need },
          { value = 2, name = "Use last " .. need },
          { value = 0, name = "Back" },
        },
      })
      local r = ok and type(res) == "table" and res.result
      local out = {}
      if r == 1 then
        for i = 1, need do out[#out + 1] = leaves[i] end
      elseif r == 2 then
        for i = #leaves - need + 1, #leaves do out[#out + 1] = leaves[i] end
      else
        return nil, nil
      end
      return out
    end
    if UI.ask(TITLE, msg .. "\n\nBuild anyway and leave " .. (need - #leaves) .. " cells empty?", "Build anyway", "Back") then
      return leaves
    end
    return nil, nil
  end
  local list, err = P.parseSubIdList(text)
  if not list then return nil, err end
  if #list ~= need then
    local msg = string.format("You typed %d sub-IDs, the shape has %d pixels.\n%s", #list, need,
      (#list > need) and "The extra sub-IDs will be ignored." or "The remaining cells stay empty.")
    if not UI.ask(TITLE, msg, "Build anyway", "Back") then return nil, nil end
  end
  return list
end

-- Turns dialog values into a full build plan.
local function makePlan(def, shape, values)
  local v, err = P.coerce(RIG_FIELDS, values)
  if not v then return nil, err end
  if v.rotate % 90 ~= 0 then return nil, "Rotate must be 0, 90, 180 or 270." end
  local name = P.clean(v.name)
  if name == "" then name = KIND_INFO[def.kind].name end

  local fixtures, slots, missing = resolveFixtures(v.fixtures, v.perRow)
  if not fixtures then return nil, slots end

  local work = P.copyShape(shape)
  if not shape.literal then
    local subs
    subs, err = resolvePixels(v.subs, fixtures[1].fid, shape.pixelCount)
    if not subs then return nil, err end
    P.assignSubs(work, subs)
  end

  local shapeA = P.transform(work, v.rotate, v.flipH, v.flipV)
  local shapeB = shapeA
  if v.alternate then shapeB = P.transform(work, v.rotate + 180, v.flipH, v.flipV) end
  local placed = P.place(fixtures, slots, shapeA, shapeB, v.gap)
  if #placed == 0 then return nil, "Nothing to build - no pixels were mapped." end

  local plan = {
    v = v, name = name, shape = shapeA, fixtures = fixtures, missing = missing or {},
    placed = placed, groups = {}, existing = {},
  }

  local gw, gh = 0, 0
  for _, c in ipairs(placed) do
    gw = math.max(gw, c.gx + 1); gh = math.max(gh, c.gy + 1)
  end
  plan.gridW, plan.gridH = gw, gh

  if v.group > 0 then
    plan.groups[#plan.groups + 1] = { no = v.group, name = name .. " Grid", cells = placed, full = true }
    if v.partGroups and #shape.parts > 1 then
      for i, part in ipairs(shape.parts) do
        local cells = {}
        for _, c in ipairs(placed) do
          if c.part == part then cells[#cells + 1] = c end
        end
        if #cells > 0 then
          plan.groups[#plan.groups + 1] = { no = v.group + i, name = name .. " " .. part, cells = P.toOrigin(cells) }
        end
      end
    end
    for _, g in ipairs(plan.groups) do
      if MA.poolObject("Groups", g.no) then plan.existing[#plan.existing + 1] = "Group " .. g.no end
    end
  end
  if v.layout > 0 then
    plan.layout = { no = v.layout, name = name .. " Pixels",
      elements = P.layoutElements(placed, v.cellSize, SETTINGS.layoutFill, SETTINGS.layoutYUp) }
    if MA.poolObject("Layouts", v.layout) then plan.existing[#plan.existing + 1] = "Layout " .. v.layout end
  end
  if v.gridStore then
    local cells = {}
    for _, c in ipairs(shapeA.cells) do
      if c.sub then cells[#cells + 1] = { fid = fixtures[1].fid, sub = c.sub, gx = c.gx, gy = c.gy } end
    end
    plan.gridStore = cells
  end
  if #plan.groups == 0 and not plan.layout and not plan.gridStore and not v.keepSel then
    return nil, "Nothing to do: set a Group no., a Layout no., GridStore or Keep the grid selected."
  end
  return plan
end

local function planSummary(plan)
  local v = plan.v
  local lines = {}
  lines[#lines + 1] = string.format("%d fixtures x %d pixels = %d cells,  grid %d x %d",
    #plan.fixtures, plan.shape.pixelCount, #plan.placed, plan.gridW, plan.gridH)
  lines[#lines + 1] = ""
  for _, g in ipairs(plan.groups) do
    lines[#lines + 1] = string.format('Group %d  "%s"  (%d cells)', g.no, g.name, #g.cells)
  end
  if plan.layout then
    lines[#lines + 1] = string.format('Layout %d  "%s"  (%d elements)', plan.layout.no, plan.layout.name,
      #plan.layout.elements)
  end
  if plan.gridStore then
    lines[#lines + 1] = "GridStore: pixel shape -> fixture type of Fixture " .. plan.fixtures[1].fid
  end
  if #plan.groups == 0 and v.keepSel then
    lines[#lines + 1] = "Grid selection only (nothing stored)"
  end
  if #plan.missing > 0 then
    local ids = {}
    for i = 1, math.min(#plan.missing, 12) do ids[i] = tostring(plan.missing[i]) end
    lines[#lines + 1] = ""
    lines[#lines + 1] = "Skipped, not patched: " .. table.concat(ids, ", ") .. (#plan.missing > 12 and " ..." or "")
  end
  if #plan.existing > 0 then
    lines[#lines + 1] = ""
    lines[#lines + 1] = "WILL BE OVERWRITTEN: " .. table.concat(plan.existing, ", ")
  end
  lines[#lines + 1] = ""
  lines[#lines + 1] = "First fixture's pixels (also in the System Monitor):"
  local preview = P.preview(plan.shape)
  for i = 1, math.min(#preview, 12) do lines[#lines + 1] = preview[i] end
  if #preview > 12 then lines[#lines + 1] = "..." end
  return table.concat(lines, "\n"), preview
end

local function execute(plan)
  local v = plan.v
  local batches = {}
  if plan.gridStore then
    local cmds = P.selectionCommands(plan.gridStore)
    cmds[#cmds + 1] = "GridStore"
    batches[#batches + 1] = { cmds = cmds }
  end
  for i = 2, #plan.groups do
    local g = plan.groups[i]
    local cmds = P.selectionCommands(g.cells)
    for _, c in ipairs(P.storeGroupCommands(g.no, g.name)) do cmds[#cmds + 1] = c end
    batches[#batches + 1] = { cmds = cmds }
  end
  if plan.layout then batches[#batches + 1] = { layout = plan.layout } end
  if plan.groups[1] or v.keepSel then
    local cmds = P.selectionCommands(plan.placed)
    if plan.groups[1] then
      for _, c in ipairs(P.storeGroupCommands(plan.groups[1].no, plan.groups[1].name)) do cmds[#cmds + 1] = c end
    end
    batches[#batches + 1] = { cmds = cmds, final = true }
  end
  if not v.keepSel then batches[#batches + 1] = { cmds = { "ClearSelection" } } end

  local total = 0
  for _, b in ipairs(batches) do total = total + (b.cmds and #b.cmds or #b.layout.elements + 4) end

  local done, layoutFailed, selected = 0, 0, nil
  local progress = Progress.start(total)
  local function step()
    done = done + 1
    if done % 20 == 0 then Progress.set(progress, done) end
    if SETTINGS.yieldEvery > 0 and done % SETTINGS.yieldEvery == 0 then breathe() end
  end

  MA.beginUndo(TITLE .. " " .. plan.name)
  local ok, err = pcall(function()
    for _, b in ipairs(batches) do
      if b.layout then
        local L = b.layout
        MA.cmd("ClearSelection")
        if MA.poolObject("Layouts", L.no) then MA.cmd(string.format("Delete Layout %d /NoConfirmation", L.no)) end
        MA.cmd(string.format("Store Layout %d", L.no))
        MA.cmd(string.format('Label Layout %d "%s"', L.no, P.clean(L.name)))
        local layout = MA.poolObject("Layouts", L.no)
        if not layout then error("Layout " .. L.no .. " could not be created.") end
        for _, e in ipairs(L.elements) do
          local before = MA.count(layout)
          MA.cmd(string.format("Assign Fixture %s At Layout %d", e.addr, L.no))
          local n = MA.count(layout)
          if n > before then
            local el = layout[n]
            MA.setProp(el, "posx", e.x)
            MA.setProp(el, "posy", e.y)
            MA.setProp(el, "positionw", e.w)
            MA.setProp(el, "positionh", e.h)
          else
            layoutFailed = layoutFailed + 1
          end
          step()
        end
      else
        for _, c in ipairs(b.cmds) do
          MA.cmd(c)
          step()
        end
        if b.final then selected = MA.selectionCount() end
      end
    end
  end)
  MA.endUndo()
  Progress.stop(progress)

  if not ok then
    UI.error("The build stopped part way: " .. tostring(err))
    return false
  end

  local problems = {}
  if layoutFailed > 0 then
    problems[#problems + 1] = layoutFailed .. " pixels could not be added to the layout."
  end
  if selected and selected > 0 and selected ~= #plan.placed then
    problems[#problems + 1] = string.format("The grid selection has %d of %d pixels. "
      .. "Some sub-IDs may not exist - check with Inspect fixture.", selected, #plan.placed)
  end
  MA.log(string.format("Done: %d fixtures, %d pixels.", #plan.fixtures, #plan.placed))
  if #problems > 0 then
    for _, p in ipairs(problems) do MA.err(p) end
    UI.message(TITLE .. " - finished with warnings", table.concat(problems, "\n\n"))
  end
  return true
end

local function initialValues(fields, prefix, overrides)
  local values = {}
  for _, f in ipairs(fields) do
    local saved = MA.getVar(prefix .. f.key, nil)
    local value = f.default
    if saved ~= nil then
      if f.type == "bool" then value = P.toBool(saved) else value = saved end
    end
    if overrides and overrides[f.key] ~= nil then value = overrides[f.key] end
    values[f.key] = value
  end
  return values
end

local function saveValues(fields, prefix, values)
  for _, f in ipairs(fields) do
    if values[f.key] ~= nil then MA.setVar(prefix .. f.key, values[f.key]) end
  end
end

local function Build(def)
  local info = KIND_INFO[def.kind]
  local shapePrefix = "shape." .. def.kind .. "."

  -- 1. Shape
  local shapeValues = initialValues(info.fields, shapePrefix, def.values)
  local shape
  while true do
    local vals = UI.form(TITLE .. " - " .. info.title, info.message or def.label, info.fields, shapeValues,
      { { value = 1, name = "Next" }, { value = 0, name = "Cancel" } })
    if not vals then return end
    shapeValues = vals
    local s, err = P.buildShape(def.kind, vals)
    if s then shape = s; break end
    UI.error(err)
  end

  -- 2. Rig + output
  local overrides = { gap = def.gap or info.gap, name = def.name or info.name }
  local rigValues = initialValues(RIG_FIELDS, "rig.", nil)
  if def.values or MA.getVar("rig.kind", "") ~= def.kind then
    rigValues.gap, rigValues.name = overrides.gap, overrides.name
  end
  if MA.selectionCount() > 0 then rigValues.fixtures = "sel" end
  -- Suggest the next free pool slots from where the last build went.
  local groupCount = (#shape.parts > 1) and (#shape.parts + 1) or 1
  local lastGroup, lastLayout = P.toInt(rigValues.group, 0), P.toInt(rigValues.layout, 0)
  if lastGroup ~= 0 then rigValues.group = MA.firstFree("Groups", groupCount, lastGroup or 1) end
  if lastLayout ~= 0 then rigValues.layout = MA.firstFree("Layouts", 1, lastLayout or 1) end

  local rigFields = {}
  for i, f in ipairs(RIG_FIELDS) do
    rigFields[i] = f
    if f.key == "subs" and shape.literal then
      rigFields[i] = { key = f.key, label = f.label, type = f.type, default = f.default, hidden = true }
    end
  end

  local message = "Shape: " .. shapeSummary(shape) .. "\n"
    .. "Fixtures: 101 Thru 116  /  101-108 + 201-208  /  Group 5  /  sel = current selection\n"
    .. (shape.literal and "" or "Pixel sub-IDs: auto, or in pixel order e.g. 1 Thru 42 or 15-28, 1-14, 29-42")

  while true do
    local vals = UI.form(TITLE .. " - rig & output", message, rigFields, rigValues,
      { { value = 1, name = "Next" }, { value = 0, name = "Cancel" } })
    if not vals then return end
    rigValues = vals
    local plan, err = makePlan(def, shape, vals)
    if plan then
      local summary, preview = planSummary(plan)
      MA.log("Preview of fixture " .. plan.fixtures[1].fid .. ":")
      for _, line in ipairs(preview) do MA.log("  " .. line) end
      local ok, res = pcall(MessageBox, {
        title = TITLE .. " - ready",
        message = summary,
        commands = { { value = 1, name = "Build" }, { value = 2, name = "Back" }, { value = 0, name = "Cancel" } },
      })
      local r = ok and type(res) == "table" and res.result
      if r == 1 then
        saveValues(info.fields, shapePrefix, shapeValues)
        saveValues(RIG_FIELDS, "rig.", rigValues)
        MA.setVar("rig.kind", def.kind)
        execute(plan)
        return
      elseif r ~= 2 then
        return
      end
    elseif err then
      UI.error(err)
    end
  end
end

--------------------------------------------------------------------------------
-- CLASSIC DIALOGS (fallback, or run the plugin with the argument "classic")
--------------------------------------------------------------------------------
local function classicEntries()
  local list = {}
  for _, p in ipairs(USER_PRESETS) do
    if KIND_INFO[p.kind] then list[#list + 1] = p end
  end
  for _, kind in ipairs(KIND_ORDER) do
    list[#list + 1] = { label = KIND_INFO[kind].menu, kind = kind }
  end
  for _, p in ipairs(PRESETS) do
    list[#list + 1] = { label = "Quick: " .. p.label, kind = p.kind, values = p.values, name = p.name, gap = p.gap }
  end
  return list
end

local function Classic()
  local presets = classicEntries()
  local items = {}
  for i, p in ipairs(presets) do items[i] = p.label end
  items[#items + 1] = ITEM_INSPECT
  items[#items + 1] = ITEM_HELP

  local choice = UI.choose(TITLE .. " - what are you building?", items)
  if not choice then return end
  if choice == ITEM_INSPECT then return Inspect() end
  if choice == ITEM_HELP then return UI.message(TITLE .. " - help", HELP_TEXT) end
  for _, p in ipairs(presets) do
    if p.label == choice then return Build(p) end
  end
end

--------------------------------------------------------------------------------
-- WINDOW
-- One window built from grandMA3 UI objects on the screen overlay. Buttons,
-- edits and check boxes call the PGB_* signal handlers below. While the
-- window is open the plugin waits in GUI.loop(); slow work (build, popups,
-- redrawing the window) is handed to that loop so it runs in the plugin's
-- own coroutine.
--------------------------------------------------------------------------------
local GUI = { created = {}, leafCache = {}, session = 0, w = {} }

local SIG_TEXT, SIG_TOGGLE, SIG_CLICK = "PGB_Text", "PGB_Toggle", "PGB_Click"
local NEXT_ROTATION = { [0] = 90, [90] = 180, [180] = 270, [270] = 0 }
local PRESET_RIG_KEYS = { "subs", "perRow", "gap", "rotate", "flipH", "flipV", "alternate", "partGroups", "name", "cellSize" }
local PART_COLORS = { "Global.Selected", "Global.PartlySelected", "Global.PartlySelectedPreset", "Button.BackgroundPlease" }

-- Sets UI properties one by one, so one unknown property can't stop the rest.
local function uiSet(obj, props)
  if obj == nil then return nil end
  for k, v in pairs(props) do
    pcall(function() obj[k] = v end)
  end
  return obj
end

local function themeColor(path)
  local ok, c = pcall(function()
    local node = Root().ColorTheme.ColorGroups
    for part in path:gmatch("[^%.]+") do node = node[part] end
    return node
  end)
  if ok then return c end
  return nil
end

local function isValid(obj)
  if obj == nil then return false end
  if IsObjectValid then
    local ok, v = pcall(IsObjectValid, obj)
    if ok then return v and true or false end
  end
  return (pcall(function() return obj.Name end))
end

-- Widget specs -----------------------------------------------------------------
local function Lbl(text, w, align, id) return { type = "label", text = text, w = w, align = align, id = id } end
local function Edit(scope, key, w) return { type = "edit", scope = scope, key = key, w = w } end
local function Btn(text, name, w, opts)
  local s = { type = "button", text = text, name = name, w = w }
  for k, v in pairs(opts or {}) do s[k] = v end
  return s
end
local function Chk(scope, key, text, w) return { type = "check", scope = scope, key = key, text = text, w = w } end
local function Space(w) return { type = "space", w = w } end
local function Num(scope, key, label, labelW)
  if labelW == nil then labelW = 150 end
  return {
    Lbl(label, labelW or nil, "Right"),
    Btn("-", "pgb_dec_" .. scope .. "_" .. key, 56),
    Edit(scope, key, 90),
    Btn("+", "pgb_inc_" .. scope .. "_" .. key, 56),
  }
end

-- Collects specs and lists of specs into one flat list.
local function specList()
  local list = {}
  local function push(...)
    for _, item in ipairs({ ... }) do
      if item.type then
        list[#list + 1] = item
      else
        for _, s in ipairs(item) do list[#list + 1] = s end
      end
    end
  end
  return list, push
end

-- State --------------------------------------------------------------------------
function GUI.fieldDef(scope, key)
  local fields = (scope == "shape") and KIND_INFO[GUI.state.kind].fields or RIG_FIELDS
  for _, f in ipairs(fields) do
    if f.key == key then return f end
  end
  return nil
end

function GUI.value(scope, key)
  if scope == "shape" then return GUI.state.shape[GUI.state.kind][key] end
  return GUI.state.rig[key]
end

function GUI.setValue(scope, key, v)
  if scope == "shape" then
    GUI.state.shape[GUI.state.kind][key] = v
  else
    GUI.state.rig[key] = v
  end
end

function GUI.loadState()
  local st = { shape = {}, advanced = P.toBool(MA.getVar("gui.advanced", "0")) }
  st.kind = MA.getVar("gui.kind", "line")
  if not KIND_INFO[st.kind] then st.kind = "line" end
  st.presetLabel = MA.getVar("gui.preset", nil)
  for kind, info in pairs(KIND_INFO) do
    st.shape[kind] = initialValues(info.fields, "shape." .. kind .. ".", nil)
  end
  st.rig = initialValues(RIG_FIELDS, "rig.", nil)
  if MA.getVar("rig.gap", nil) == nil then st.rig.gap = KIND_INFO[st.kind].gap end
  if MA.getVar("rig.name", nil) == nil then st.rig.name = KIND_INFO[st.kind].name end
  st.rig.groupOn = P.toBool(MA.getVar("rig.groupOn", "1"))
  st.rig.layoutOn = P.toBool(MA.getVar("rig.layoutOn", "1"))
  if MA.selectionCount() > 0 then st.rig.fixtures = "sel" end
  -- Suggest the next free pool slots from where the last build went.
  local shape = P.buildShape(st.kind, st.shape[st.kind])
  local parts = shape and #shape.parts or 1
  st.rig.group = MA.firstFree("Groups", (parts > 1) and (parts + 1) or 1, P.toInt(st.rig.group, 1) or 1)
  st.rig.layout = MA.firstFree("Layouts", 1, P.toInt(st.rig.layout, 1) or 1)
  return st
end

function GUI.saveState()
  local st = GUI.state
  if not st then return end
  MA.setVar("gui.kind", st.kind)
  MA.setVar("gui.advanced", st.advanced)
  MA.setVar("gui.preset", st.presetLabel or "")
  for kind, info in pairs(KIND_INFO) do
    saveValues(info.fields, "shape." .. kind .. ".", st.shape[kind])
  end
  saveValues(RIG_FIELDS, "rig.", st.rig)
  MA.setVar("rig.groupOn", P.toBool(st.rig.groupOn))
  MA.setVar("rig.layoutOn", P.toBool(st.rig.layoutOn))
end

function GUI.rigValues()
  local r = {}
  for k, v in pairs(GUI.state.rig) do r[k] = v end
  if not P.toBool(r.groupOn) then r.group = 0 end
  if not P.toBool(r.layoutOn) then r.layout = 0 end
  return r
end

-- Saved presets: one user variable, "|" between presets, ";" between fields.
local function encode(s)
  return (tostring(s):gsub("[^%w _%.,%-]", function(c) return string.format("%%%02X", c:byte()) end))
end
local function decode(s)
  return (s:gsub("%%(%x%x)", function(h) return string.char(tonumber(h, 16)) end))
end

function GUI.loadSaved()
  local list = {}
  for entry in MA.getVarRaw("presets", ""):gmatch("[^|]+") do
    local p = { values = {}, rig = {} }
    for field in entry:gmatch("[^;]+") do
      local k, v = field:match("^([^=]*)=(.*)$")
      if k then
        k, v = decode(k), decode(v)
        if k == "label" then p.label = v
        elseif k == "kind" then p.kind = v
        elseif k:sub(1, 2) == "s." then p.values[k:sub(3)] = v
        elseif k:sub(1, 2) == "r." then p.rig[k:sub(3)] = v end
      end
    end
    if p.label and KIND_INFO[p.kind] then list[#list + 1] = p end
  end
  return list
end

function GUI.storeSaved(list)
  local entries = {}
  for _, p in ipairs(list) do
    local fields = { "label=" .. encode(p.label), "kind=" .. encode(p.kind) }
    for k, v in pairs(p.values) do fields[#fields + 1] = "s." .. encode(k) .. "=" .. encode(v) end
    for k, v in pairs(p.rig) do fields[#fields + 1] = "r." .. encode(k) .. "=" .. encode(v) end
    entries[#entries + 1] = table.concat(fields, ";")
  end
  MA.setVarRaw("presets", table.concat(entries, "|"))
end

function GUI.applyPreset(p, label)
  local st, info = GUI.state, KIND_INFO[p.kind]
  st.kind = p.kind
  local vals = {}
  for _, f in ipairs(info.fields) do vals[f.key] = f.default end
  for k, v in pairs(p.values or {}) do vals[k] = v end
  st.shape[p.kind] = vals
  st.rig.name = p.name or info.name
  st.rig.gap = p.gap or info.gap
  for k, v in pairs(p.rig or {}) do st.rig[k] = v end
  st.presetLabel = label or p.label
  GUI.lastResult = nil
end

-- Drawing ------------------------------------------------------------------------
function GUI.widget(grid, col, s)
  local anchors = col .. ",0"
  local margin = { left = 2, right = 2, top = 4, bottom = 4 }
  local o
  if s.type == "label" then
    o = grid:Append("UIObject")
    uiSet(o, { Anchors = anchors, Text = s.text, TextalignmentH = s.align or "Left", HasHover = "No",
      BackColor = themeColor("Global.Transparent"), Font = "Medium20", TextAutoAdjust = "Yes",
      Padding = { left = 8, right = 8, top = 0, bottom = 0 } })
  elseif s.type == "edit" then
    o = grid:Append("LineEdit")
    local f = GUI.fieldDef(s.scope, s.key)
    local numeric = f and f.type == "int"
    local value = GUI.value(s.scope, s.key)
    uiSet(o, { Anchors = anchors, Name = "pgb_txt_" .. s.scope .. "_" .. s.key,
      Content = tostring(value == nil and "" or value), Message = f and f.label or s.key,
      TextChanged = SIG_TEXT, PluginComponent = myHandle,
      Filter = numeric and "0123456789" or nil, VkPluginName = numeric and "TextInputNumOnly" or "TextInput",
      MaxTextLength = numeric and 6 or 1024, Font = "Medium20", TextAutoAdjust = "Yes", Margin = margin })
    GUI.w.edits[s.scope .. "_" .. s.key] = o
  elseif s.type == "button" then
    o = grid:Append("Button")
    local color = (s.please and themeColor("Button.BackgroundPlease"))
      or (s.selected and themeColor("Global.Selected")) or nil
    uiSet(o, { Anchors = anchors, Name = s.name, Text = s.text, Clicked = SIG_CLICK, PluginComponent = myHandle,
      Font = "Medium20", HasHover = "Yes", TextalignmentH = "Centre", Textshadow = 1, BackColor = color,
      Margin = margin })
  elseif s.type == "check" then
    o = grid:Append("CheckBox")
    uiSet(o, { Anchors = anchors, Name = "pgb_chk_" .. s.scope .. "_" .. s.key, Text = s.text,
      State = P.toBool(GUI.value(s.scope, s.key)) and 1 or 0, Clicked = SIG_TOGGLE, PluginComponent = myHandle,
      TextalignmentH = "Left", ColorIndicator = themeColor("Global.Selected"), Font = "Medium20", Margin = margin })
  end
  if o and s.id then GUI.w[s.id] = o end
  return o
end

-- One row of the window: a 1-row grid, fixed-width columns where w is set.
function GUI.row(frame, index, specs)
  local g = frame:Append("UILayoutGrid")
  uiSet(g, { Anchors = "0," .. index })
  uiSet(g, { Columns = #specs, Rows = 1 })
  for i, s in ipairs(specs) do
    if s.w then
      local size = tostring(math.floor(s.w * (GUI.scale or 1)))
      pcall(function() uiSet(g[2][i], { SizePolicy = "Fixed", Size = size }) end)
    end
  end
  for i, s in ipairs(specs) do GUI.widget(g, i - 1, s) end
  return g
end

function GUI.displaySize()
  local ok, w, h = pcall(function() return tonumber(GUI.display.W), tonumber(GUI.display.H) end)
  if ok and w and h and w > 0 and h > 0 then return w, h end
  return 1920, 1080
end

-- Builds (or rebuilds) the whole window from GUI.state.
function GUI.render()
  local st = GUI.state
  local info = KIND_INFO[st.kind]
  if isValid(GUI.dialog) then pcall(function() Obj.Delete(GUI.overlay, Obj.Index(GUI.dialog)) end) end
  GUI.w = { edits = {} }
  GUI.previewSig = nil

  local rows = {}
  local function addRow(h, specs) rows[#rows + 1] = { h = h, specs = specs } end

  -- Shape tiles
  local tiles = {}
  for _, kind in ipairs(KIND_ORDER) do
    tiles[#tiles + 1] = Btn(KIND_INFO[kind].short, "pgb_kind_" .. kind, nil, { selected = (kind == st.kind) })
  end
  tiles[#tiles + 1] = Btn("Presets...", "pgb_presets")
  addRow(64, tiles)

  -- Main shape fields
  local basic, push = specList()
  local stretch = false
  for _, f in ipairs(info.fields) do
    if f.basic then
      if f.type == "int" then
        push(Num("shape", f.key, f.short or f.label))
      else
        push(Lbl(f.short or f.label, 200, "Right"), Edit("shape", f.key))
        stretch = true
      end
    end
  end
  if not stretch then push(Space()) end
  addRow(56, basic)

  -- Preview (drawn by GUI.drawPreview)
  rows[#rows + 1] = { h = 0, preview = true }
  local previewIndex = #rows

  -- Fixtures and output
  addRow(56, { Lbl("Fixtures", 150, "Right"), Edit("rig", "fixtures"), Btn("Use selection", "pgb_sel", 220) })
  local out
  out, push = specList()
  push(Chk("rig", "groupOn", "Group", 150), Btn("-", "pgb_dec_rig_group", 56), Edit("rig", "group", 90),
    Btn("+", "pgb_inc_rig_group", 56), Space(24), Chk("rig", "layoutOn", "Layout", 150),
    Btn("-", "pgb_dec_rig_layout", 56), Edit("rig", "layout", 90), Btn("+", "pgb_inc_rig_layout", 56),
    Lbl("Name", 100, "Right"), Edit("rig", "name"))
  addRow(56, out)

  -- Advanced
  if st.advanced then
    addRow(52, { Btn("Rotate " .. (P.toInt(st.rig.rotate) or 0), "pgb_rotate", 190),
      Chk("rig", "flipH", "Flip left-right"), Chk("rig", "flipV", "Flip up-down"),
      Chk("rig", "alternate", "Turn every 2nd") })
    local arr
    arr, push = specList()
    push(Num("rig", "perRow", "Per row", false), Num("rig", "gap", "Gap", false), Num("rig", "cellSize", "Cell size", false))
    addRow(52, arr)
    local values, pushValue = specList()
    local checks, pushCheck = specList()
    for _, f in ipairs(info.fields) do
      if not f.basic then
        if f.type == "int" then pushValue(Num("shape", f.key, f.short or f.label, 170))
        elseif f.type == "text" then pushValue(Lbl(f.short or f.label, 170, "Right"), Edit("shape", f.key))
        else pushCheck(Chk("shape", f.key, f.short or f.label)) end
      end
    end
    if #values > 0 then
      local hasStretch = false
      for _, s in ipairs(values) do if not s.w then hasStretch = true end end
      if not hasStretch then pushValue(Space()) end
      addRow(52, values)
    end
    if #checks > 0 then addRow(52, checks) end
    if st.kind == "custom" then
      addRow(52, { Lbl("Custom map: the numbers you type are the sub-IDs."), Btn("Inspect", "pgb_inspect", 160) })
    else
      addRow(52, { Lbl("Pixel sub-IDs", 170, "Right"), Edit("rig", "subs"), Btn("Inspect", "pgb_inspect", 160) })
    end
    addRow(52, { Chk("rig", "partGroups", "Part groups"), Chk("rig", "gridStore", "GridStore to type"),
      Chk("rig", "keepSel", "Keep selected"), Btn("Save preset...", "pgb_save", 220) })
  end

  -- Status and actions
  addRow(36, { Lbl("", nil, "Left", "info") })
  addRow(36, { Lbl("", nil, "Left", "note") })
  addRow(64, { Btn(st.advanced and "Simple view" or "Advanced...", "pgb_adv", 230), Btn("Help", "pgb_help", 130),
    Space(), Btn("Build", "pgb_build", 260, { please = true, id = "build" }), Btn("Close", "pgb_close", 170) })

  -- Size: the preview gets whatever height is left.
  local dispW, dispH = GUI.displaySize()
  local W = math.min(1180, math.floor(dispW * 0.95))
  GUI.scale = math.min(1, W / 1180)
  local used = 0
  for _, r in ipairs(rows) do used = used + r.h end
  local previewH = st.advanced and 180 or 270
  local maxH = math.floor(dispH * 0.94)
  if 80 + used + previewH > maxH then
    previewH = math.max(110, maxH - 80 - used)
    if 80 + used + previewH > maxH then
      -- Small screen: squeeze the rows too.
      local f = math.max(0.7, (maxH - 80 - previewH) / used)
      used = 0
      for _, r in ipairs(rows) do
        r.h = math.floor(r.h * f)
        used = used + r.h
      end
    end
  end
  rows[previewIndex].h = previewH
  GUI.previewW, GUI.previewH = W - 40, previewH

  local base = GUI.overlay:Append("BaseInput")
  GUI.dialog = base
  uiSet(base, { Name = "PixelGridBuilderWindow", W = W, H = 80 + used + previewH, AutoClose = "No", CloseOnEscape = "Yes" })
  uiSet(base, { Columns = 1, Rows = 2 })
  pcall(function() uiSet(base[1][1], { SizePolicy = "Fixed", Size = "60" }) end)
  pcall(function() uiSet(base[1][2], { SizePolicy = "Stretch" }) end)

  local titleBar = base:Append("TitleBar")
  uiSet(titleBar, { Anchors = "0,0", Texture = "corner2" })
  uiSet(titleBar, { Columns = 2, Rows = 1 })
  pcall(function() uiSet(titleBar[2][2], { SizePolicy = "Fixed", Size = "50" }) end)
  uiSet(titleBar:Append("TitleButton"), { Anchors = "0,0", Texture = "corner1", Icon = "star",
    Text = TITLE .. "   -   " .. (st.presetLabel or info.title) })
  uiSet(titleBar:Append("CloseButton"), { Anchors = "1,0", Texture = "corner2" })

  local frame = base:Append("DialogFrame")
  uiSet(frame, { H = "100%", W = "100%", Anchors = { left = 0, right = 0, top = 1, bottom = 1 } })
  uiSet(frame, { Columns = 1, Rows = #rows })
  for i, r in ipairs(rows) do
    pcall(function() uiSet(frame[1][i], { SizePolicy = "Fixed", Size = tostring(r.h) }) end)
  end
  GUI.w.frame = frame
  GUI.w.previewRow = previewIndex - 1
  -- Edits may fire their change signal while being filled in: hold refreshes.
  GUI.building = true
  local ok, err = pcall(function()
    for i, r in ipairs(rows) do
      if not r.preview then GUI.row(frame, i - 1, r.specs) end
    end
  end)
  GUI.building = false
  if not ok then error(err, 0) end
  GUI.refresh()
end

-- The first fixture's pixels as coloured, numbered cells.
function GUI.drawPreview(shape, message)
  local sig = message or "x"
  if shape then
    local parts = {}
    for _, c in ipairs(shape.cells) do
      parts[#parts + 1] = c.gx .. "," .. c.gy .. "," .. tostring(c.order or c.sub) .. "," .. tostring(c.part)
    end
    sig = shape.gw .. "x" .. shape.gh .. ":" .. table.concat(parts, ";")
  end
  if sig == GUI.previewSig and GUI.w.preview then return end

  local frame = GUI.w.frame
  if GUI.w.preview then pcall(function() Obj.Delete(frame, Obj.Index(GUI.w.preview)) end) end
  local box = frame:Append("UILayoutGrid")
  GUI.w.preview = box
  GUI.previewSig = sig
  uiSet(box, { Anchors = "0," .. GUI.w.previewRow })

  local tooBig = shape and (shape.gw > 64 or shape.gh > 40 or #shape.cells > 500)
  if not shape or tooBig then
    uiSet(box, { Columns = 1, Rows = 1 })
    local text = message or string.format("%d x %d cells - too big to draw here, the build is fine.", shape.gw, shape.gh)
    uiSet(box:Append("UIObject"), { Anchors = "0,0", Text = text, HasHover = "No", Font = "Medium20",
      BackColor = themeColor("Global.Transparent"), TextAutoAdjust = "Yes" })
    return
  end

  -- Pad the grid so cells stay square, and centre the shape.
  local aspect = GUI.previewW / GUI.previewH
  local cols = math.max(shape.gw, math.ceil(shape.gh * aspect))
  local rows = math.max(shape.gh, math.ceil(shape.gw / aspect))
  if (cols - shape.gw) % 2 == 1 then cols = cols + 1 end
  if (rows - shape.gh) % 2 == 1 then rows = rows + 1 end
  local ox, oy = math.floor((cols - shape.gw) / 2), math.floor((rows - shape.gh) / 2)
  uiSet(box, { Columns = cols, Rows = rows })
  local showText = math.min(GUI.previewW / cols, GUI.previewH / rows) >= 18
  local partIndex = {}
  for i, p in ipairs(shape.parts) do partIndex[p] = i end
  for _, c in ipairs(shape.cells) do
    local label = shape.literal and c.sub or c.order
    uiSet(box:Append("UIObject"), {
      Anchors = (ox + c.gx) .. "," .. (oy + c.gy),
      Text = showText and tostring(label or "") or "",
      BackColor = themeColor(PART_COLORS[((partIndex[c.part] or 1) - 1) % #PART_COLORS + 1]),
      HasHover = "No", TextAutoAdjust = "Yes", Margin = { left = 1, right = 1, top = 1, bottom = 1 },
    })
  end
end

function GUI.setStatus(info, note, isError)
  if info then uiSet(GUI.w.info, { Text = info }) end
  uiSet(GUI.w.note, { Text = note or "", TextColor = themeColor(isError and "Global.ErrorText" or "Global.Text") })
end

function GUI.setBuildEnabled(on)
  uiSet(GUI.w.build, { Enabled = on and "Yes" or "No",
    BackColor = themeColor(on and "Button.BackgroundPlease" or "Button.BackgroundClear") })
end

-- Reads every edit box back into the state (in case a change signal was missed).
function GUI.syncEdits()
  for id, o in pairs(GUI.w.edits or {}) do
    local scope, key = id:match("^(%a+)_(%w+)$")
    local ok, content = pcall(function() return o.Content end)
    if scope and ok and content ~= nil then GUI.setValue(scope, key, tostring(content)) end
  end
end

-- Live check -------------------------------------------------------------------
function GUI.fixtureInfo(rv)
  local t = P.trim(rv.fixtures):lower()
  if t == "sel" or t == "selection" or t == "*" then
    local list = MA.readSelection()
    if #list == 0 then return { error = "Nothing is selected - select the fixtures or type a list." } end
    local slots = (rv.perRow > 0) and P.slotsInRows(#list, rv.perRow) or P.slotsFromGrid(list)
    return { count = #list, slots = slots, first = list[1].fid, source = "selection" }
  end
  local g = t:match("^group%s*(%d+)$")
  if g then return { group = tonumber(g) } end
  local ids, err = P.parseIdList(rv.fixtures)
  if not ids then return { error = err } end
  return { count = #ids, slots = P.slotsInRows(#ids, rv.perRow), first = ids[1] }
end

function GUI.leaves(fid)
  if GUI.leafCache[fid] == nil then
    GUI.leafCache[fid] = MA.subfixtureTree(fid) or false
  end
  return GUI.leafCache[fid]
end

-- Returns text, isError about how the pixels will be numbered.
function GUI.pixelNote(fid, subs, need)
  local t = P.trim(subs):lower()
  if t == "" or t == "auto" then
    local leaves = GUI.leaves(fid)
    if leaves == false then return "Fixture " .. fid .. " isn't patched." end
    if #leaves == 0 then return "Fixture " .. fid .. " has no subfixtures - is it in a pixel mode?" end
    if #leaves ~= need then
      return string.format("Fixture %d has %d pixels, the shape %d - you'll be asked which to use.", fid, #leaves, need)
    end
    return string.format("Fixture %d: %d pixels, matches.", fid, #leaves)
  end
  local list, err = P.parseSubIdList(subs)
  if not list then return err, true end
  if #list ~= need then return string.format("%d sub-IDs typed, the shape has %d pixels.", #list, need) end
  return nil
end

function GUI.overwriteList(rv, shape)
  local list = {}
  if rv.group > 0 then
    local extra = (rv.partGroups and #shape.parts > 1) and #shape.parts or 0
    for no = rv.group, rv.group + extra do
      if MA.poolObject("Groups", no) and not GUI.created["Group " .. no] then list[#list + 1] = "Group " .. no end
    end
  end
  if rv.layout > 0 and MA.poolObject("Layouts", rv.layout) and not GUI.created["Layout " .. rv.layout] then
    list[#list + 1] = "Layout " .. rv.layout
  end
  return list
end

-- Recomputes the preview, the info line and whether Build is possible.
function GUI.refresh()
  local st = GUI.state
  if GUI.building or not (GUI.w and GUI.w.frame) then return end
  GUI.syncEdits()
  local shape, err = P.buildShape(st.kind, st.shape[st.kind])
  local rv
  if shape then rv, err = P.coerce(RIG_FIELDS, GUI.rigValues()) end
  if not shape or not rv then
    GUI.drawPreview(nil, err)
    GUI.setStatus("", err, true)
    GUI.setBuildEnabled(false)
    return
  end
  local shapeA = P.transform(shape, rv.rotate, rv.flipH, rv.flipV)
  GUI.drawPreview(shapeA)

  local fx = GUI.fixtureInfo(rv)
  local parts = (#shape.parts > 1) and ("   |   parts: " .. table.concat(shape.parts, ", ")) or ""
  local info, problem, notes = nil, nil, {}
  if fx.error then
    problem = fx.error
    info = string.format("%d pixels per fixture%s", shape.pixelCount, parts)
  elseif fx.group then
    info = string.format("Fixtures from Group %d  x  %d pixels%s", fx.group, shape.pixelCount, parts)
  else
    local gw, gh = P.gridSize(shapeA, fx.slots, rv.gap)
    info = string.format("%d fixture%s x %d px = %d pixels   |   grid %d x %d%s%s", fx.count,
      (fx.count == 1) and "" or "s", shape.pixelCount, fx.count * shape.pixelCount, gw, gh, parts,
      fx.source and ("   |   " .. fx.source) or "")
  end
  if not problem and not shape.literal and fx.first then
    local text, bad = GUI.pixelNote(fx.first, rv.subs, shape.pixelCount)
    if bad then problem = text elseif text then notes[#notes + 1] = text end
  end
  local over = GUI.overwriteList(rv, shape)
  if #over > 0 then notes[#notes + 1] = "Will overwrite " .. table.concat(over, ", ") .. "." end
  if rv.group == 0 and rv.layout == 0 and not rv.gridStore and not rv.keepSel then
    problem = problem or "Tick Group or Layout to store something."
  end
  if st.kind == "custom" and #notes == 0 then
    notes[1] = "/ new row    . empty cell    4-9 run    2.3 nested    Name: new part"
  end
  GUI.setStatus(info, problem or GUI.lastResult or table.concat(notes, "    "), problem ~= nil)
  GUI.setBuildEnabled(problem == nil)
end

-- Actions ------------------------------------------------------------------------
function GUI.build()
  GUI.syncEdits()
  local st = GUI.state
  local shape, err = P.buildShape(st.kind, st.shape[st.kind])
  if not shape then UI.error(err) return end
  GUI.busy = true
  GUI.setStatus(nil, "Building ...", false)
  local plan
  plan, err = makePlan({ kind = st.kind }, shape, GUI.rigValues())
  if not plan then
    GUI.busy = false
    if err then UI.error(err) end
    return GUI.refresh()
  end
  local foreign = {}
  for _, e in ipairs(plan.existing) do
    if not GUI.created[e] then foreign[#foreign + 1] = e end
  end
  if #foreign > 0 and not UI.ask(TITLE, "Overwrite " .. table.concat(foreign, ", ") .. "?", "Overwrite", "Cancel") then
    GUI.busy = false
    return GUI.refresh()
  end
  local ok = execute(plan)
  GUI.busy = false
  if ok then
    local done = {}
    for _, g in ipairs(plan.groups) do GUI.created["Group " .. g.no] = true end
    if #plan.groups > 0 then
      local a, b = plan.groups[1].no, plan.groups[#plan.groups].no
      done[#done + 1] = (a == b) and ("Group " .. a) or ("Groups " .. a .. "-" .. b)
    end
    if plan.layout then
      GUI.created["Layout " .. plan.layout.no] = true
      done[#done + 1] = "Layout " .. plan.layout.no
    end
    if plan.gridStore then done[#done + 1] = "GridStore" end
    if #done == 0 then done[1] = "the grid selection" end
    GUI.lastResult = "Built " .. table.concat(done, ", ") .. "  (" .. #plan.placed .. " pixels)."
    GUI.saveState()
  end
  GUI.leafCache = {}
  GUI.refresh()
end

function GUI.firstFixture()
  local rv = P.coerce(RIG_FIELDS, GUI.rigValues())
  if not rv then return nil end
  local fx = GUI.fixtureInfo(rv)
  return fx.first
end

function GUI.choosePreset()
  local entries = {}
  for _, p in ipairs(USER_PRESETS) do
    if KIND_INFO[p.kind] then entries[#entries + 1] = { label = p.label, preset = p } end
  end
  for _, p in ipairs(PRESETS) do entries[#entries + 1] = { label = p.label, preset = p } end
  local saved = GUI.loadSaved()
  for _, p in ipairs(saved) do entries[#entries + 1] = { label = "Saved: " .. p.label, preset = p, name = p.label } end
  if #saved > 0 then entries[#entries + 1] = { label = "Delete a saved preset...", delete = true } end
  local items = {}
  for i, e in ipairs(entries) do items[i] = e.label end
  local choice = UI.choose("Presets", items, GUI.lastCaller)
  for _, e in ipairs(entries) do
    if e.label == choice then
      if e.delete then return GUI.deletePreset(saved) end
      GUI.applyPreset(e.preset, e.name)
      return GUI.render()
    end
  end
end

function GUI.deletePreset(saved)
  local items = {}
  for i, p in ipairs(saved) do items[i] = p.label end
  local choice = UI.choose("Delete a saved preset", items, GUI.lastCaller)
  if not choice then return end
  local keep = {}
  for _, p in ipairs(saved) do
    if p.label ~= choice then keep[#keep + 1] = p end
  end
  GUI.storeSaved(keep)
  GUI.lastResult = "Deleted preset '" .. choice .. "'."
  GUI.refresh()
end

function GUI.savePreset()
  GUI.syncEdits()
  local st = GUI.state
  local ok, name = pcall(TextInput, "Save preset - name", st.presetLabel or st.rig.name or "")
  name = ok and P.clean(name or "") or ""
  if name == "" then return end
  local list = {}
  for _, p in ipairs(GUI.loadSaved()) do
    if p.label ~= name then list[#list + 1] = p end
  end
  local p = { label = name, kind = st.kind, values = {}, rig = {} }
  for k, v in pairs(st.shape[st.kind]) do p.values[k] = v end
  for _, k in ipairs(PRESET_RIG_KEYS) do p.rig[k] = st.rig[k] end
  list[#list + 1] = p
  GUI.storeSaved(list)
  st.presetLabel = name
  GUI.lastResult = "Saved preset '" .. name .. "' - it's in Presets now."
  GUI.refresh()
end

function GUI.step(scope, key, dir)
  local f = GUI.fieldDef(scope, key)
  if not f then return end
  local v = (P.toInt(GUI.value(scope, key)) or f.default) + dir * (f.step or 1)
  v = math.max(f.guiMin or f.min, math.min(f.max, v))
  GUI.setValue(scope, key, tostring(v))
  uiSet(GUI.w.edits[scope .. "_" .. key], { Content = tostring(v) })
  GUI.lastResult = nil
  GUI.refresh()
end

-- Work that opens popups or redraws the window goes through the loop.
function GUI.request(action, arg)
  if GUI.busy then return end
  if GUI.modal then GUI.pending = { action, arg } else GUI.run(action, arg) end
end

function GUI.run(action, arg)
  local st = GUI.state
  if action == "kind" then
    st.kind, st.presetLabel = arg, nil
    st.rig.name, st.rig.gap = KIND_INFO[arg].name, KIND_INFO[arg].gap
    GUI.lastResult = nil
    GUI.render()
  elseif action == "adv" then
    GUI.syncEdits()
    st.advanced = not st.advanced
    GUI.render()
  elseif action == "presets" then
    GUI.syncEdits()
    GUI.choosePreset()
  elseif action == "build" then
    GUI.build()
  elseif action == "inspect" then
    local fid = GUI.firstFixture()
    if fid then Inspect(fid) else UI.error("Enter the fixtures first, then Inspect shows the first one.") end
  elseif action == "save" then
    GUI.savePreset()
  elseif action == "help" then
    UI.message(TITLE .. " - help", GUI_HELP)
  end
end

function GUI.close()
  GUI.syncEdits()
  GUI.saveState()
  if isValid(GUI.dialog) then pcall(function() Obj.Delete(GUI.overlay, Obj.Index(GUI.dialog)) end) end
  GUI.dialog = nil
end

-- Signal handlers ------------------------------------------------------------------
local function guard(fn)
  return function(caller, ...)
    local ok, err = pcall(fn, caller, ...)
    if not ok then MA.err("Window error: " .. tostring(err)) end
  end
end

function GUI.onText(caller)
  local scope, key = tostring(caller.Name or ""):match("^pgb_txt_(%a+)_(%w+)$")
  if not scope then return end
  GUI.setValue(scope, key, tostring(caller.Content or ""))
  GUI.lastResult = nil
  GUI.refresh()
end

function GUI.onToggle(caller)
  local scope, key = tostring(caller.Name or ""):match("^pgb_chk_(%a+)_(%w+)$")
  if not scope then return end
  local state = (tonumber(caller.State) == 1) and 0 or 1
  uiSet(caller, { State = state })
  GUI.setValue(scope, key, state == 1)
  GUI.lastResult = nil
  GUI.refresh()
end

function GUI.onClick(caller)
  local name = tostring(caller.Name or "")
  GUI.lastCaller = caller
  local dir, scope, key = name:match("^pgb_(%a%a%a)_(%a+)_(%w+)$")
  if dir == "inc" or dir == "dec" then return GUI.step(scope, key, (dir == "inc") and 1 or -1) end
  local kind = name:match("^pgb_kind_(%a+)$")
  if kind then return GUI.request("kind", kind) end
  local st = GUI.state
  if name == "pgb_rotate" then
    local r = NEXT_ROTATION[(P.toInt(st.rig.rotate) or 0) % 360] or 0
    st.rig.rotate = tostring(r)
    uiSet(caller, { Text = "Rotate " .. r })
    GUI.lastResult = nil
    GUI.refresh()
  elseif name == "pgb_sel" then
    st.rig.fixtures = "sel"
    uiSet(GUI.w.edits.rig_fixtures, { Content = "sel" })
    GUI.lastResult = nil
    GUI.refresh()
  elseif name == "pgb_close" then
    GUI.close()
  else
    GUI.request((name:gsub("^pgb_", "")))
  end
end

local function pickDisplay()
  local ok, display = pcall(GetFocusDisplay)
  if not ok then display = nil end
  local okIndex, index = pcall(function() return Obj.Index(display) end)
  if display == nil or (okIndex and type(index) == "number" and index > 5) then
    local okD, d = pcall(GetDisplayByIndex, 1)
    if okD and d then display = d end
  end
  local okO, overlay = pcall(function() return display.ScreenOverlay end)
  return display, okO and overlay or nil
end

function GUI.open()
  GUI.session = GUI.session + 1
  GUI.pending, GUI.busy, GUI.lastResult = nil, false, nil
  GUI.state = GUI.loadState()
  GUI.display, GUI.overlay = pickDisplay()
  if not GUI.overlay then error("no screen overlay found") end
  pcall(function() GUI.overlay:ClearUIChildren() end)
  signalTable[SIG_TEXT] = guard(GUI.onText)
  signalTable[SIG_TOGGLE] = guard(GUI.onToggle)
  signalTable[SIG_CLICK] = guard(GUI.onClick)
  GUI.modal = (coroutine.isyieldable ~= nil) and coroutine.isyieldable() or false
  GUI.render()
end

-- Waits while the window is open and runs the work its buttons hand over.
function GUI.loop()
  local me, ticks = GUI.session, 0
  while GUI.session == me and isValid(GUI.dialog) do
    local job = GUI.pending
    GUI.pending = nil
    if job then guard(function() GUI.run(job[1], job[2]) end)() end
    ticks = ticks + 1
    -- Keep "sel" up to date when the selection changes elsewhere.
    if ticks % 20 == 0 and not GUI.busy and P.trim(GUI.state.rig.fixtures):lower() == "sel" then
      guard(GUI.refresh)()
    end
    coroutine.yield(0.05)
  end
  if GUI.session == me then GUI.saveState() end
end

--------------------------------------------------------------------------------
-- MAIN
--------------------------------------------------------------------------------
local function Main(displayHandle, argument)
  if P.trim(argument):lower() == "classic" then return Classic() end
  local ok, err = pcall(GUI.open)
  if not ok then
    MA.err("Couldn't open the window (" .. tostring(err) .. "). Using the classic dialogs instead.")
    pcall(GUI.close)
    return Classic()
  end
  if GUI.modal then GUI.loop() end
end

-- Test hook: lets the offline test suite reach the internals. Never set on a console.
if type(PGB_TEST_HOOK) == "table" then
  PGB_TEST_HOOK.P, PGB_TEST_HOOK.MA, PGB_TEST_HOOK.UI, PGB_TEST_HOOK.GUI = P, MA, UI, GUI
  PGB_TEST_HOOK.SETTINGS, PGB_TEST_HOOK.PRESETS, PGB_TEST_HOOK.KIND_INFO = SETTINGS, PRESETS, KIND_INFO
  PGB_TEST_HOOK.makePlan, PGB_TEST_HOOK.execute = makePlan, execute
end

return Main
