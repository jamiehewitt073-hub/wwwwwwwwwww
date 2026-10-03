-- Offline tests for Speed Master LEDs.  Run from the repo root:
--   lua tests/run_speed_master_leds_tests.lua

package.path = "./tests/?.lua;" .. package.path
local mock = require("speed_master_leds_mock")

local PLUGIN = "SpeedMasterLEDs/SpeedMasterLEDs.lua"

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
local function near(a, b, tol, msg)
  if type(a) ~= "number" or math.abs(a - b) > tol then
    error((msg or "values differ") .. ": expected " .. tostring(b) .. " +-" .. tol .. ", got " .. tostring(a), 2)
  end
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
  _G.SpeedMasterLEDs_State = nil
  SML_TEST_HOOK = {}
  local chunk = assert(loadfile(PLUGIN))
  local main = chunk("Speed Master LEDs", "SpeedMasterLEDs", {}, {})
  local hook = SML_TEST_HOOK
  SML_TEST_HOOK = nil
  return S, main, hook
end

local function noViolations(S)
  eq(#S.violations, 0, "LED violations: " .. table.concat(S.violations, " | "))
end

-- A full-size style console: master module + both fader modules.
local function fullSize(S, how)
  S.addModule("UsbDeviceMA3 1", "Control", how)
  S.addModule("UsbDeviceMA3 2", "MM", how)
  S.addModule("UsbDeviceMA3 3", "MFE", how)
  S.addModule("UsbDeviceMA3 4", "MFX", how)
end

-- Counts off -> on edges of one LED between t0 and t1, sampled every dt.
local function countFlashes(S, module, index, t0, t1, dt)
  local n, was = 0, false
  for t = t0, t1, dt or 0.01 do
    local on = (S.ledAt(module, index, t) or 0) > 0
    if on and not was then n = n + 1 end
    was = on
  end
  return n
end

-- Starts the plugin with the given setup values and lets it run.
local function startWith(S, main, overrides, seconds)
  S.boxes = { mock.form(overrides, 1) }
  local co = S.start(main, nil, "")
  S.drive(co, seconds or 2)
  return co
end

--------------------------------------------------------------------------------
-- Hardware map against the tables in the grandMA3 manual
--------------------------------------------------------------------------------
local _, _, H = load()
local P, HW = H.P, H.HW

local function xKey(exec)
  if exec >= 291 then return "X" .. (exec - 290) end
  return "X" .. (exec - 182)
end

test("key LEDs match the manual", function()
  for t, hw in pairs(HW) do
    local names = mock.LED_NAMES[t]
    for exec, idx in pairs(hw.keys) do
      local name = names[idx] or "<none>"
      local okName = name == ("Executor " .. exec .. " Button")
        or name:find('^Executor ' .. exec .. ' "' .. xKey(exec) .. '[ "|]')
      truthy(okName, t .. " key " .. exec .. " -> LED " .. idx .. " is " .. name)
    end
  end
end)

test("knob and fader LEDs match the manual", function()
  local colors = { "Red", "Green", "Blue" }
  for t, hw in pairs(HW) do
    local names = mock.LED_NAMES[t]
    for exec, rgb in pairs(hw.rgb) do
      for c = 1, 3 do
        local name = names[rgb[c]] or "<none>"
        local want = (t == "MM" and "Knob" or "Fader")
        local ok = name == ("Executor " .. exec .. " " .. want .. " " .. colors[c])
          or (t == "MFX" and exec == 307 and c == 1 and name == "Executor 307 Fader")
        truthy(ok, t .. " " .. exec .. " " .. colors[c] .. " -> LED " .. rgb[c] .. " is " .. name)
      end
    end
  end
end)

test("screen encoder LEDs match the manual", function()
  local colors = { "Red", "Green", "Blue" }
  for i, rgb in ipairs(HW.MM.encoders) do
    local n = math.floor((i + 1) / 2)
    local side = (i % 2 == 1) and "INSIDE" or "OUTSIDE"
    for c = 1, 3 do
      local name = (mock.LED_NAMES.MM[rgb[c]] or ""):gsub("%s+", " ")
      eq(name, "ENCODER_" .. side .. n .. " " .. colors[c], "encoder " .. i)
    end
  end
end)

test("key and fader-touch buttons match the manual", function()
  for t, hw in pairs(HW) do
    local names = mock.BUTTON_NAMES[t]
    for exec, idx in pairs(hw.buttons) do
      local want = (t == "MM") and xKey(exec) or ("EXEC_" .. exec)
      eq(names[idx], want, t .. " button of " .. exec)
    end
    for exec, idx in pairs(hw.touch) do
      eq(names[idx], "FADER_" .. exec, t .. " touch of " .. exec)
    end
  end
end)

test("every executor LED in the manual is in the map", function()
  for t, names in pairs(mock.LED_NAMES) do
    for idx, name in pairs(names) do
      local exec = tonumber(name:match("^Executor (%d+)"))
      if exec then
        local covered = HW[t].keys[exec] == idx
        for _, c in ipairs(HW[t].rgb[exec] or {}) do covered = covered or c == idx end
        truthy(covered, t .. " LED " .. idx .. " (" .. name .. ") isn't mapped")
      end
    end
  end
end)

test("LEDs 1-140 are ordinary LEDs on every module", function()
  for idx = 1, H.GUESSED_MAX do
    for t, names in pairs(mock.LED_NAMES) do
      local name = names[idx]
      truthy(name, t .. " has no LED " .. idx)
      truthy(not name:find("Backlight") and not name:find("Desklights") and not name:find("All LEDs"),
        t .. " LED " .. idx .. " is " .. name)
    end
  end
end)

test("every writable LED exists on its module", function()
  for t, set in pairs(H.ALLOWED) do
    local n = 0
    for idx in pairs(set) do
      n = n + 1
      truthy(mock.LED_NAMES[t][idx], t .. " LED " .. idx .. " isn't in the manual")
    end
    truthy(n > 0)
  end
end)

--------------------------------------------------------------------------------
-- Parsing
--------------------------------------------------------------------------------
test("executor lists", function()
  local e = P.parseExecs("auto")
  truthy(e.auto); eq(#e.list, 0)
  e = P.parseExecs("291, 293 - 295 + 191")
  local nums = {}
  for i, x in ipairs(e.list) do nums[i] = x.exec; eq(x.mod, nil) end
  listEq(nums, { 291, 293, 294, 295, 191 })
  e = P.parseExecs("291 thru 293")
  eq(#e.list, 3)
  e = P.parseExecs("mfe:401-403, MFX : 201, auto")
  truthy(e.auto)
  eq(e.list[1].mod, "MFE"); eq(e.list[1].exec, 401)
  eq(e.list[4].mod, "MFX"); eq(e.list[4].exec, 201)
  truthy(P.parseExecs("216")) -- second fader section: placed later
  for _, bad in ipairs({ "", "999", "1", "MM:401", "MFE:291", "MFE:216", "XY:291", "abc", "101-300" }) do
    local v, err = P.parseExecs(bad)
    eq(v, nil, "'" .. bad .. "' should fail")
    truthy(err)
  end
end)

test("rates and colours", function()
  eq(P.parseRate("1"), 1)
  eq(P.parseRate("1/2"), 0.5)
  eq(P.parseRate("0,25"), 0.25)
  eq(P.parseRate("4"), 4)
  eq(P.parseRate("0"), nil)
  eq(P.parseRate("1/0"), nil)
  eq(P.parseRate("x"), nil)
  listEq(P.parseColor("White"), { 255, 255, 255 })
  listEq(P.parseColor(" red "), { 255, 0, 0 })
  listEq(P.parseColor("0, 128, 255"), { 0, 128, 255 })
  listEq(P.parseColor("10 20 30"), { 10, 20, 30 })
  listEq(P.parseColor("#FF8000"), { 255, 128, 0 })
  eq(P.parseColor("300,0,0"), nil)
  eq(P.parseColor("teal"), nil)
end)

test("BPM from the master text and fader", function()
  local function faderFor(bpm) return 100 * (bpm / 225) ^ (1 / 1.90689062) end
  -- The fader position adds the decimals the text hides.
  local bpm, src = P.chooseBpm("123", faderFor(123.4), 0)
  near(bpm, 123.4, 1e-6); eq(src, "fader")
  bpm, src = P.chooseBpm("123.4 BPM", faderFor(123.43), 0)
  near(bpm, 123.43, 1e-6); eq(src, "fader")
  -- When the fader disagrees the text wins.
  bpm, src = P.chooseBpm("128", faderFor(100), 0)
  eq(bpm, 128); eq(src, "text")
  -- Other readouts.
  near(P.chooseBpm("2.00 Hz", nil, 0), 120, 1e-9)
  near(P.chooseBpm("0.5s", nil, 0), 120, 1e-9)
  near(P.chooseBpm("1,5 Hz", nil, 0), 90, 1e-9)
  -- Scale x2: the fader curve doubled matches the text.
  bpm, src = P.chooseBpm("240", faderFor(120), 1)
  near(bpm, 240, 1e-6); eq(src, "fader")
  -- No text: the curve on its own.
  near(P.chooseBpm(nil, faderFor(90), 0), 90, 1e-6)
  eq(P.chooseBpm(nil, nil, 0), nil)
  eq(P.chooseBpm("0", 0, 0), 0)
  eq(P.scaleExponent("Mul4"), 2)
  eq(P.scaleExponent("Div2"), -1)
  eq(P.scaleExponent(nil), 0)
  eq(P.scaleExponent(-3), -3)
end)

test("config from dialog values", function()
  local cfg = H.makeConfig({ master = "1", execs = "auto", rate = "1", duty = "50", color = "Red", dim = "10",
    keys = true, rings = "0", screenEncoders = false, pulse = false, resync = true })
  eq(cfg.master, 1); eq(cfg.rate, 1); eq(cfg.duty, 50); eq(cfg.dim, 10)
  eq(cfg.keys, true); eq(cfg.rings, false)
  local base = { master = "1", execs = "auto", rate = "1", duty = "50", color = "White", dim = "0", keys = true }
  for field, bad in pairs({ master = "17", duty = "100", dim = "95", color = "nope", rate = "-1", execs = "" }) do
    local v = {}
    for k, x in pairs(base) do v[k] = x end
    v[field] = bad
    eq(H.makeConfig(v), nil, field .. " = " .. bad)
  end
  eq(H.makeConfig({ master = "1", execs = "auto", rate = "1", duty = "50", color = "White", dim = "0",
    keys = false, rings = false, screenEncoders = false }), nil, "nothing to flash")
end)

--------------------------------------------------------------------------------
-- Flash engine
--------------------------------------------------------------------------------
local function engine(over)
  local cfg = { rate = 1, duty = 50, pulse = false, resync = true }
  for k, v in pairs(over or {}) do cfg[k] = v end
  return H.Engine.new(cfg)
end

test("blinks on the beat", function()
  local e = engine()
  eq(e:update(10, 120), 1)       -- a beat starts when the BPM is first seen
  eq(e:update(10.2, 120), 1)
  eq(e:update(10.3, 120), 0)     -- off after half a beat (0.25 s)
  eq(e:update(10.5, 120), 1)     -- next beat
  eq(e:update(20.1, 120), 1)     -- still in step much later (20 beats)
  eq(e:update(20.26, 120), 0)
  eq(e:update(21, nil), nil)     -- no BPM: let the console have the LEDs
  eq(e:update(21, 0), nil)
end)

test("flashes per beat and pulse", function()
  local e = engine({ rate = 2 })
  eq(e:update(0, 120), 1)
  eq(e:update(0.13, 120), 0)
  eq(e:update(0.25, 120), 1)
  local p = engine({ pulse = true, duty = 100 })
  eq(p:update(0, 60), 1)
  near(p:update(0.5, 60), 0.25, 1e-9)
  near(p:update(0.999, 60), 0, 1e-3)
end)

test("taps and BPM changes line up the beat", function()
  local e = engine()
  e:update(0, 120)
  -- Riding the fader: quick changes keep the phase.
  e:update(0.1, 121)
  e:update(0.12, 122)
  near(e:phase(0.12), 0.24, 0.01)
  -- A change after a quiet spell (a tap tempo) restarts the beat.
  e:update(5.0, 100)
  eq(e.origin, 5.0)
  -- A key tap restarts it too, and a BPM change right after keeps the tap time.
  e:tap(7.03)
  e:update(7.05, 110)
  eq(e.origin, 7.03)
  -- Without "line up with taps" a BPM change never restarts the beat.
  local f = engine({ resync = false })
  f:update(0, 120)
  f:update(5.1, 100)
  near(f:phase(5.1), 0.2, 1e-9) -- 10.2 beats at 120 -> phase 0.2 carried over
end)

--------------------------------------------------------------------------------
-- Hardware detection
--------------------------------------------------------------------------------
test("module types come from the module's product", function()
  for _, how in ipairs({ "product", "text" }) do
    local S, _, h = load()
    S.host = { "Console", "Light" }
    fullSize(S, how)
    local mods = h.MA.modules()
    eq(#mods, 4)
    eq(mods[1].type, nil, how .. ": control module isn't used")
    eq(mods[2].type, "MM", how)
    eq(mods[3].type, "MFE", how)
    eq(mods[4].type, "MFX", how)
  end
end)

test("full-size names are a fallback, nothing is guessed elsewhere", function()
  local S, _, h = load()
  fullSize(S, "none")
  local mods = h.MA.modules()
  eq(mods[2].type, "MM"); eq(mods[3].type, "MFE"); eq(mods[4].type, "MFX")
  eq(mods[2].how, "full-size module name")
  eq(mods[2].guessed, true)
  eq(mods[1].type, nil)
  S, _, h = load()
  S.host = { "Console", "Light" }
  fullSize(S, "none")
  for _, m in ipairs(h.MA.modules()) do eq(m.type, nil, m.name) end
  S, _, h = load()
  S.host = { "Console", "Light" }
  fullSize(S, "none")
  h.SETTINGS.moduleTypes = { ["UsbDeviceMA3 2"] = "MM" }
  eq(h.MA.modules()[2].type, "MM")
end)

--------------------------------------------------------------------------------
-- Running
--------------------------------------------------------------------------------
test("auto: flashes the X-key and knob holding Speed Master 1", function()
  local S, main = load()
  fullSize(S)
  S.setMaster(1, "120", nil)
  S.assign(291, 1)
  S.assign(292, false) -- something else on the next executor
  local co = startWith(S, main, {}, 4)
  noViolations(S)
  truthy(coroutine.status(co) ~= "dead", "still running")
  -- Only the master module is touched, only X1's key (135) and knob (108/113/125).
  for _, c in ipairs(S.ledCalls) do eq(c.module, "UsbDeviceMA3 2") end
  listEq(S.litIndices("UsbDeviceMA3 2"), { 108, 113, 125, 135 })
  -- 120 BPM: a flash every 0.5 s.
  local t0 = 100.5
  eq(countFlashes(S, "UsbDeviceMA3 2", 135, t0, t0 + 2.99), 6)
  eq(countFlashes(S, "UsbDeviceMA3 2", 108, t0, t0 + 2.99), 6)
  eq(S.ledAt("UsbDeviceMA3 2", 135, 101.1), 255)
  eq(S.ledAt("UsbDeviceMA3 2", 135, 101.3), 0)
  eq(S.ledAt("UsbDeviceMA3 2", 113, 101.1), 255)
  -- Stop from a second run of the plugin: every LED goes back to the console.
  main(nil, "stop")
  S.drive(co, 1)
  eq(coroutine.status(co), "dead")
  eq(#S.litIndices("UsbDeviceMA3 2"), 0)
  noViolations(S)
end)

test("LEDs are refreshed while they hold a value", function()
  local S, main = load()
  fullSize(S)
  S.setMaster(1, "30", nil) -- 2 s per beat, 1 s on
  S.assign(291, 1)
  local co = startWith(S, main, {}, 3)
  local gaps, last = 0, nil
  for _, c in ipairs(S.ledCalls) do
    if last then gaps = math.max(gaps, c.t - last) end
    last = c.t
  end
  truthy(gaps <= 0.25 + 1e-9, "longest gap between SetLED calls " .. gaps)
  main(nil, "stop")
  S.drive(co, 1)
end)

test("the BPM follows the master and 0 BPM hands the LEDs back", function()
  local S, main = load()
  fullSize(S)
  S.setMaster(1, "120", nil)
  S.assign(291, 1)
  local co = startWith(S, main, {}, 1)
  S.setMaster(1, "60", nil)
  S.drive(co, 4)
  eq(countFlashes(S, "UsbDeviceMA3 2", 135, 101.5, 104.99), 4)
  S.setMaster(1, "0", 0)
  S.drive(co, 1)
  eq(#S.litIndices("UsbDeviceMA3 2"), 0)
  main(nil, "stop")
  S.drive(co, 1)
  noViolations(S)
end)

test("auto follows page changes", function()
  local S, main = load()
  fullSize(S)
  S.setMaster(1, "120", nil)
  S.assign(291, 1)
  local co = startWith(S, main, {}, 1.5)
  truthy(#S.litIndices("UsbDeviceMA3 2") > 0)
  S.assign(291, nil) -- new page: the master isn't on it
  S.drive(co, 1.5)
  eq(#S.litIndices("UsbDeviceMA3 2"), 0)
  S.assign(195, 1) -- X13 on the next page
  S.drive(co, 1.5)
  listEq(S.litIndices("UsbDeviceMA3 2"), { 78 })
  main(nil, "stop")
  S.drive(co, 1)
  noViolations(S)
end)

test("one fader module: executor numbers map onto it", function()
  local S, main = load()
  S.host = { "Console", "Light" }
  S.addModule("UsbDeviceMA3 2", "MM")
  S.addModule("UsbDeviceMA3 3", "MFX")
  S.setMaster(1, "120", nil)
  S.assign(401, 1)
  S.assign(201, 1)
  local co = startWith(S, main, {}, 1)
  noViolations(S)
  -- MFX 401: key 131, knob 134/139/152. MFX 201: key 35, fader 168/169/170.
  listEq(S.litIndices("UsbDeviceMA3 3"), { 35, 131, 134, 139, 152, 168, 169, 170 })
  main(nil, "stop")
  S.drive(co, 1)
end)

test("two fader modules: asks for Learn keys, MFE:401 works", function()
  local S, main = load()
  fullSize(S)
  S.setMaster(1, "120", nil)
  S.assign(401, 1)
  local msg
  S.boxes = { mock.form({}, 1), function(spec) msg = spec.message return { result = 1 } end }
  local co = S.start(main, nil, "")
  S.drive(co, 1)
  eq(coroutine.status(co), "dead")
  truthy(msg and msg:find("Learn keys"), msg)
  eq(#S.ledCalls, 0)

  co = startWith(S, main, { Executors = "MFE:401" }, 1)
  listEq(S.litIndices("UsbDeviceMA3 3"), { 114, 117, 122, 135 })
  eq(#S.litIndices("UsbDeviceMA3 4"), 0)
  main(nil, "stop")
  S.drive(co, 1)
  noViolations(S)
end)

test("guessed modules: X-keys work, high LEDs are left alone", function()
  local S, main = load()
  fullSize(S, "none")
  S.setMaster(1, "120", nil)
  local co = startWith(S, main, { Executors = "291, MFE:201" }, 1)
  noViolations(S)
  listEq(S.litIndices("UsbDeviceMA3 2"), { 108, 113, 125, 135 })
  listEq(S.litIndices("UsbDeviceMA3 3"), { 25 }) -- 201's key; its fader LEDs (161-163) are skipped
  local all = table.concat(S.errors, "\n")
  truthy(all:find("only guessed"), all)
  main(nil, "stop")
  S.drive(co, 1)
end)

test("a wrong guess can't hit a missing LED", function()
  -- Module names as in the 2.1 manual: the guesses are all wrong.
  local S, main = load()
  S.addModule("UsbDeviceMA3 2", "MFX", "none")
  S.addModule("UsbDeviceMA3 3", "MFE", "none")
  S.addModule("UsbDeviceMA3 4", "MM", "none")
  S.setMaster(1, "120", nil)
  local co = startWith(S, main, {
    Executors = "191-198, 291-298, MFE:101-115, MFE:201-215, MFE:301-315, MFE:401-415, "
      .. "MFX:101-115, MFX:201-215, MFX:301-315, MFX:401-415",
    ["Also flash the 5 screen encoders"] = true,
  }, 1.5)
  truthy(#S.ledCalls > 0)
  noViolations(S)
  main(nil, "stop")
  S.drive(co, 1)
  noViolations(S)
end)

test("options: keys only, colour, dim, screen encoders", function()
  local S, main = load()
  fullSize(S)
  S.setMaster(1, "120", nil)
  local co = startWith(S, main, {
    Executors = "291, 191", ["Flash the encoder / fader LEDs"] = false,
    ["Also flash the 5 screen encoders"] = true, ["Encoder colour"] = "Red",
    ["Brightness between flashes %"] = 20,
  }, 2)
  noViolations(S)
  local lit = S.litIndices("UsbDeviceMA3 2")
  local set = {}
  for _, i in ipairs(lit) do set[i] = true end
  truthy(set[135] and set[139], "both keys")
  truthy(not set[108], "knob left alone")
  for _, rgb in ipairs({ { 7, 10, 22 }, { 32, 19, 31 } }) do
    truthy(set[rgb[1]] and set[rgb[2]] and set[rgb[3]], "screen encoder")
  end
  -- Red at full, 20 % between flashes; green and blue stay dark.
  eq(S.ledAt("UsbDeviceMA3 2", 7, 101.1), 255)
  eq(S.ledAt("UsbDeviceMA3 2", 10, 101.1), 0)
  eq(S.ledAt("UsbDeviceMA3 2", 7, 101.3), 51)
  eq(S.ledAt("UsbDeviceMA3 2", 135, 101.3), 51)
  main(nil, "stop")
  S.drive(co, 1)
end)

test("tapping a flashing key starts the beat", function()
  local S, main = load()
  fullSize(S)
  S.setMaster(1, "60", nil) -- 1 s per beat, on for 0.5 s
  S.assign(291, 1)
  local co = startWith(S, main, {}, 1.2)
  -- 101.2: the beat that started at 101.0 is off. Tap X1 (button 238).
  S.press("UsbDeviceMA3 2", 238)
  S.drive(co, 0.1)
  S.press("UsbDeviceMA3 2", 238, false)
  local tapT = 101.2
  eq(S.ledAt("UsbDeviceMA3 2", 135, tapT + 0.05), 255)
  S.drive(co, 1.5)
  eq(S.ledAt("UsbDeviceMA3 2", 135, tapT + 0.6), 0)
  eq(S.ledAt("UsbDeviceMA3 2", 135, tapT + 1.05), 255)
  main(nil, "stop")
  S.drive(co, 1)
end)

test("learn keys: tap to add, tap again to remove, touch a fader", function()
  local S, main = load()
  fullSize(S)
  S.setMaster(1, "120", nil)
  local learnedForm
  S.boxes = {
    mock.form({}, 2), -- Learn keys
    function(spec) learnedForm = spec return { result = 0 } end,
  }
  local co = S.start(main, nil, "")
  local script = {
    { 0.5, "UsbDeviceMA3 2", 238 }, -- X1 -> 291
    { 1.0, "UsbDeviceMA3 2", 239 }, -- X2 -> 292
    { 1.5, "UsbDeviceMA3 3", 203 }, -- MFE 401 key
    { 2.0, "UsbDeviceMA3 2", 239 }, -- X2 again: removed
    { 2.5, "UsbDeviceMA3 4", 249 }, -- touch MFX fader 201
  }
  local t0 = S.now
  S.drive(co, 15, function(now)
    local down = {}
    for _, s in ipairs(script) do
      local key = s[2] .. "|" .. s[3]
      down[key] = down[key] or (now - t0 >= s[1] and now - t0 < s[1] + 0.1)
    end
    for _, s in ipairs(script) do S.press(s[2], s[3], down[s[2] .. "|" .. s[3]]) end
  end)
  eq(coroutine.status(co), "dead")
  noViolations(S)
  local execs
  for _, i in ipairs(learnedForm.inputs) do if i.name:find("Executors") then execs = i.value end end
  eq(execs, "291, MFE:401, MFX:201")
  -- Feedback while learning: X1 lit, and everything handed back at the end.
  truthy(S.ledAt("UsbDeviceMA3 2", 135, t0 + 0.8) == 255)
  eq(#S.litIndices("UsbDeviceMA3 2"), 0)
  eq(#S.litIndices("UsbDeviceMA3 3"), 0)
end)

test("toggle and the running menu", function()
  local S, main = load()
  fullSize(S)
  S.setMaster(1, "120", nil)
  S.assign(291, 1)
  -- No saved settings yet: toggle starts with the defaults.
  local co = S.start(main, nil, "toggle")
  S.drive(co, 1)
  truthy(coroutine.status(co) ~= "dead")
  -- Running: plain run shows the menu.
  local title
  S.popups = { function(spec) title = spec.title return mock.pick("Stop flashing")(spec) end }
  main(nil, "")
  truthy(title:find("120.0 BPM"), title)
  S.drive(co, 1)
  eq(coroutine.status(co), "dead")
  -- Toggle again starts again.
  co = S.start(main, nil, "toggle")
  S.drive(co, 1)
  truthy(coroutine.status(co) ~= "dead")
  main(nil, "toggle")
  S.drive(co, 1)
  eq(coroutine.status(co), "dead")
  -- The command-line stop works too.
  co = S.start(main, nil, "start")
  S.drive(co, 1)
  truthy(coroutine.status(co) ~= "dead")
  SpeedMasterLEDs_Stop()
  S.drive(co, 1)
  eq(coroutine.status(co), "dead")
  eq(#S.litIndices("UsbDeviceMA3 2"), 0)
  noViolations(S)
end)

test("settings are remembered", function()
  local S, main = load()
  fullSize(S)
  S.setMaster(2, "120", nil)
  local co = startWith(S, main, { ["Speed master"] = 2, Executors = "293", ["Encoder colour"] = "Blue" }, 1)
  main(nil, "stop")
  S.drive(co, 1)
  eq(S.vars.SML_master, "2")
  eq(S.vars.SML_execs, "293")
  co = S.start(main, nil, "start")
  S.drive(co, 1)
  listEq(S.litIndices("UsbDeviceMA3 2"), { 104, 115, 127, 137 })
  eq(S.ledAt("UsbDeviceMA3 2", 127, S.now - 0.9), 255) -- blue
  eq(S.ledAt("UsbDeviceMA3 2", 104, S.now - 0.9), 0)
  main(nil, "stop")
  S.drive(co, 1)
end)

test("unsupported hardware and missing master stop with a message", function()
  local S, main = load()
  S.host = { "onPC", "onPC" }
  S.setMaster(1, "120", nil)
  S.assign(291, 1)
  local msg
  S.boxes = { mock.form({}, 1), function(spec) msg = spec.message return { result = 1 } end }
  local co = S.start(main, nil, "")
  S.drive(co, 1)
  eq(coroutine.status(co), "dead")
  truthy(msg:find("No grandMA3 surface modules"), msg)

  S, main = load()
  S.host = { "Console", "Compact" }
  S.addModule("UsbDeviceMA3 2", "Compact")
  S.setMaster(1, "120", nil)
  S.boxes = { mock.form({ Executors = "291" }, 1), function(spec) msg = spec.message return { result = 1 } end }
  co = S.start(main, nil, "")
  S.drive(co, 1)
  truthy(msg:find("can't tell which hardware modules"), msg)
  eq(#S.ledCalls, 0)

  S, main = load()
  fullSize(S)
  S.boxes = { mock.form({}, 1), function(spec) msg = spec.message return { result = 1 } end }
  co = S.start(main, nil, "")
  S.drive(co, 1)
  truthy(msg:find("Speed Master 1 doesn't exist"), msg)
end)

test("check lists the BPM, modules and executors", function()
  local S, main = load()
  fullSize(S)
  S.setMaster(1, "128", nil)
  S.assign(291, 1)
  local msg
  S.boxes = { function(spec) msg = spec.message return { result = 1 } end }
  local co = S.start(main, nil, "check")
  S.drive(co, 1)
  truthy(msg:find('shows "128"'), msg)
  truthy(msg:find("UsbDeviceMA3 2: Master Module %(MM%)"), msg)
  truthy(msg:find("UsbDeviceMA3 1: not used"), msg)
  truthy(msg:find("speed master is on: 291"), msg)
  truthy(msg:find("Would flash: 291"), msg)
end)

print(string.format("\n%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
