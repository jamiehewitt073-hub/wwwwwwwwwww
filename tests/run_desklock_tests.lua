-- Offline tests for DeskLock.  Run from the repo root:
--   lua tests/run_desklock_tests.lua

package.path = "./tests/?.lua;" .. package.path
local mock = require("desklock_mock")

local PLUGIN = "DeskLock/DeskLock.lua"

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
local function contains(s, part, msg)
  if not tostring(s):find(part, 1, true) then error((msg or "text") .. " has no '" .. part .. "':\n" .. tostring(s), 2) end
end

-- A full-size style desk: two main screens, a command screen, a letterbox.
local function load(opts)
  opts = opts or {}
  local S = mock.new()
  if not opts.noDisplays then
    S.addDisplay(1, "Display 1", 1920, 1080)
    S.addDisplay(2, "Display 2", 1920, 1080)
    S.addDisplay(3, "Command", 1280, 800)
    S.addDisplay(4, "Letterbox", 1920, 240)
  end
  S.install()
  DESKLOCK_TEST_HOOK = {}
  local signalTable = {}
  local chunk = assert(loadfile(PLUGIN))
  local main = chunk("DeskLock", "DeskLock", signalTable, S.component)
  local H = DESKLOCK_TEST_HOOK
  DESKLOCK_TEST_HOOK = nil
  S.signalTable = signalTable
  H.MA.clock = function() return S.t end
  return S, main, H
end

-- Runs Main in a coroutine like the console does. Returns a stepper that
-- moves the clock and resumes until Main yields again or ends.
local function run(main, S, arg)
  local co = coroutine.create(function() return main(nil, arg) end)
  local function step(seconds)
    S.t = S.t + (seconds or 0)
    if coroutine.status(co) == "dead" then return false end
    local ok, err = coroutine.resume(co)
    if not ok then error(err, 0) end
    return coroutine.status(co) ~= "dead"
  end
  step(0)
  return step, co
end

local function setPin(H, pin) H.Config.setPin(pin) end

local function visible(S, d)
  local pad = S.find(S.lockBase(d), "DLPad_" .. d)
  return pad and pad._props.Visible == "Yes"
end

--------------------------------------------------------------------------------
-- Basics
--------------------------------------------------------------------------------
test("PIN hash: same input same hash, salt matters, PIN not stored", function()
  local S, _, H = load()
  eq(H.Hash.pin("1234", "aa"), H.Hash.pin("1234", "aa"))
  truthy(H.Hash.pin("1234", "aa") ~= H.Hash.pin("1234", "bb"))
  truthy(H.Hash.pin("1234", "aa") ~= H.Hash.pin("1235", "aa"))
  eq(#H.Hash.pin("1234", "aa"), 16)
  setPin(H, "4711")
  for k, v in pairs(S.vars) do truthy(not tostring(v):find("4711"), "PIN in plain text in " .. k) end
  local cfg = H.Config.load()
  eq(H.Config.checkPin(cfg, "4711"), "user")
  eq(H.Config.checkPin(cfg, "4712"), nil)
  eq(H.Config.checkPin(cfg, ""), nil)
end)

test("PIN rules: 4 to 8 digits", function()
  local _, _, H = load()
  truthy(H.Config.validPin("1234")); truthy(H.Config.validPin("12345678"))
  truthy(not H.Config.validPin("123")); truthy(not H.Config.validPin("123456789"))
  truthy(not H.Config.validPin("12a4"))
end)

test("aspect ratios", function()
  local _, _, H = load()
  eq(H.U.aspect(1920, 1080), "16:9"); eq(H.U.aspect(1280, 800), "8:5")
  eq(H.U.aspect(1920, 240), "8:1"); eq(H.U.aspect(1024, 768), "4:3")
end)

test("settings round trip through global variables", function()
  local _, _, H = load()
  local c = H.Config.load()
  eq(c.maxTries, 5); eq(c.hardLock, true); eq(c.autoLock, false)
  c.maxTries, c.autoLock, c.padScreen = 3, true, 2
  H.Config.save(c)
  local d = H.Config.load()
  eq(d.maxTries, 3); eq(d.autoLock, true); eq(d.padScreen, 2)
  H.Config.saveScreen(3, { app = "12", msg = "Hi", clock = true, showMsg = true, pad = false })
  local s = H.Config.screen(3)
  eq(s.app, "12"); eq(s.msg, "Hi"); eq(s.clock, true); eq(s.pad, false)
end)

--------------------------------------------------------------------------------
-- Screen sizes and templates
--------------------------------------------------------------------------------
test("screen sizes: every display with its exact size", function()
  local S, _, H = load()
  S.addAppearance(11, "Main L", 1920, 1080)
  S.addAppearance(14, "Letter", 1920, 200)
  H.Config.saveScreen(1, { app = "11" })
  H.Config.saveScreen(4, { app = "14" })
  H.Config.saveScreen(2, { app = "99" })
  local rows = H.Templates.rows()
  eq(#rows, 4)
  eq(rows[1].w, 1920); eq(rows[1].h, 1080); eq(rows[3].w, 1280); eq(rows[3].h, 800)
  eq(rows[1].pad, true); eq(rows[4].pad, false, "letterbox too small for the pad")
  local text = H.Templates.report(rows)
  contains(text, "1920 x 1080"); contains(text, "1280 x 800"); contains(text, "1920 x 240")
  contains(text, "image size OK")
  contains(text, "image is 1920x200")
  contains(text, "appearance not found")
end)

test("SVG template is exactly the screen size with the PIN pad marked", function()
  local _, _, H = load()
  local rows = H.Templates.rows()
  local svg = H.Templates.svg(rows[1])
  contains(svg, 'width="1920" height="1080" viewBox="0 0 1920 1080"')
  contains(svg, '<rect x="780" y="280" width="360" height="520"', "pad centred")
  contains(svg, 'id="guides"')
  local small = H.Templates.svg(rows[4])
  contains(small, 'width="1920" height="240"')
  truthy(not small:find("PIN pad", 1, true), "no pad on letterbox")
  eq(H.Templates.fileName(rows[3]), "Display3_Command_1280x800.svg")
  local csv = H.Templates.csv(rows)
  contains(csv, '1,"Display 1",1920,1080,16:9,yes,780,280,360,520')
  contains(csv, '4,"Letterbox",1920,240,8:1,no')
end)

test("export writes SVGs and size lists", function()
  local S, _, H = load()
  local dir = os.tmpname(); os.remove(dir)
  os.execute('mkdir -p "' .. dir .. '"')
  local folder, written = H.Templates.export(dir)
  truthy(folder, tostring(written))
  eq(#written, 6)
  local f = assert(io.open(folder .. "/Display1_Display_1_1920x1080.svg"))
  contains(f:read("a"), 'width="1920"'); f:close()
  f = assert(io.open(folder .. "/screens.csv")); contains(f:read("a"), "width_px"); f:close()
  os.execute('rm -rf "' .. dir .. '"')
end)

--------------------------------------------------------------------------------
-- Locking
--------------------------------------------------------------------------------
test("lock covers every screen with its own picture, PIN unlocks", function()
  local S, main, H = load()
  setPin(H, "2468")
  local apps = {}
  for i = 1, 4 do
    apps[i] = S.addAppearance(20 + i, "Pic " .. i)
    H.Config.saveScreen(i, { app = tostring(20 + i) })
  end
  local step = run(main, S, "lock")
  truthy(H.state(), "locked")
  eq(S.vars.PDL_Locked, "1")
  for i = 1, 4 do
    local base = S.lockBase(i)
    truthy(base, "display " .. i .. " covered")
    eq(base._props.W, S.displays[i]._props.W, "width " .. i)
    eq(base._props.H, S.displays[i]._props.H, "height " .. i)
    eq(base._props.CloseOnEscape, "No")
    eq(S.find(base, "DLBg_" .. i)._props.Appearance, apps[i], "own picture on display " .. i)
  end
  truthy(not S.find(S.lockBase(4), "DLPad_4"), "no pad on the letterbox")
  truthy(not visible(S, 1), "pad hidden until tapped")

  -- Tapping the letterbox brings the pad up on the first big screen.
  S.click(4, "DLBg_4"); step(0.2)
  truthy(visible(S, 1), "pad on display 1"); truthy(not visible(S, 2))
  -- Tapping display 2 moves it there.
  S.click(2, "DLBg_2"); step(0.2)
  truthy(visible(S, 2)); truthy(not visible(S, 1))

  S.typePin(2, "1111"); step(0.2)
  eq(S.find(S.lockBase(2), "DLStatus_2")._props.Text, "Wrong PIN")
  contains(S.find(S.lockBase(1), "DLInfo_1")._props.Text, "1 failed unlock attempt")
  truthy(H.state(), "still locked")

  S.click(2, "DLKey_2_2"); S.click(2, "DLKey_4_2"); step(0.2)
  eq(S.find(S.lockBase(2), "DLEntry_2")._props.Text, "* *")
  S.click(2, "DLKey_C_2"); step(0.2)
  eq(S.find(S.lockBase(2), "DLEntry_2")._props.Text, "Enter PIN")

  S.typePin(2, "2468")
  local alive = step(0.2)
  truthy(not alive, "Main returned")
  eq(H.state(), nil)
  for i = 1, 4 do eq(S.lockBase(i), nil, "display " .. i .. " uncovered") end
  eq(S.vars.PDL_Locked, "0")
  eq(S.vars.PDL_FailCount, "1")
  contains(S.boxSpecs[#S.boxSpecs].message, "1 wrong PIN was entered")
end)

test("pad hides again after the timeout and forgets the entry", function()
  local S, main, H = load()
  setPin(H, "2468")
  local step = run(main, S, "lock")
  S.click(1, "DLBg_1"); S.click(1, "DLKey_2_1"); step(0.2)
  truthy(visible(S, 1))
  step(25)
  truthy(not visible(S, 1))
  eq(H.state().entry, "")
end)

test("cooldown after too many wrong PINs, doubling", function()
  local S, main, H = load()
  setPin(H, "2468")
  local step = run(main, S, "lock")
  S.click(1, "DLBg_1")
  for _ = 1, 5 do S.typePin(1, "0000") end
  step(0.2)
  local L = H.state()
  eq(L.fails, 5)
  truthy(math.abs(L.cooldownUntil - S.t - 29.8) < 1e-6, "30 s cooldown")
  contains(S.find(S.lockBase(1), "DLStatus_1")._props.Text, "try again in")
  S.typePin(1, "2468"); step(0.2)
  truthy(H.state(), "right PIN ignored during cooldown")
  step(31)
  S.click(1, "DLBg_1")
  for _ = 1, 5 do S.typePin(1, "0000") end
  truthy(math.abs(H.state().cooldownUntil - S.t - 60) < 1e-6, "second round doubles")
  step(61)
  S.click(1, "DLBg_1"); S.typePin(1, "2468")
  truthy(not step(0.2), "unlocked after the cooldown")
end)

test("master PIN unlocks", function()
  local S, main, H = load()
  setPin(H, "2468"); H.Config.setAdminPin("99887766")
  local step = run(main, S, "lock")
  S.click(1, "DLBg_1"); S.typePin(1, "99887766")
  truthy(not step(0.2))
  eq(H.state(), nil)
end)

test("hard lock: no-rights user while locked, back to your user after", function()
  local S, main, H = load()
  setPin(H, "2468")
  local step = run(main, S, "lock")
  eq(S.current._props.Name, "DeskLock")
  eq(S.current._props.Rights, "None")
  eq(S.current._props.Profile, "Default", "same profile, same screens")
  -- Someone logs in elsewhere: the watchdog takes the desk back.
  S.current = S.usersPool._children[1]
  step(1.2)
  eq(S.current._props.Name, "DeskLock")
  S.click(1, "DLBg_1"); S.typePin(1, "2468")
  truthy(not step(0.2))
  eq(S.current._props.Name, "Admin")
end)

test("hard lock asks for your password when your user has one", function()
  local S, main, H = load()
  S.current._props.Password = "secret"
  setPin(H, "2468")
  local step = run(main, S, "lock")
  eq(S.current._props.Name, "DeskLock")
  S.texts = { "wrong", "secret" }
  S.click(1, "DLBg_1"); S.typePin(1, "2468")
  truthy(not step(0.2))
  eq(S.current._props.Name, "Admin")
  eq(#S.textTitles, 2)
end)

test("hard lock off: user stays the same", function()
  local S, main, H = load()
  setPin(H, "2468")
  local c = H.Config.load(); c.hardLock = false; H.Config.save(c)
  local step = run(main, S, "lock")
  eq(S.current._props.Name, "Admin")
  S.click(1, "DLBg_1"); S.typePin(1, "2468")
  truthy(not step(0.2))
end)

test("watchdog covers a screen again when its overlay is removed", function()
  local S, main, H = load()
  setPin(H, "2468")
  local step = run(main, S, "lock")
  S.overlay(3):ClearUIChildren()
  eq(S.lockBase(3), nil)
  step(1.2)
  truthy(S.lockBase(3), "covered again")
  -- A display that turns up while locked gets covered too.
  S.addDisplay(5, "Display 5", 1024, 768)
  step(1.2)
  truthy(S.lockBase(5), "new display covered")
end)

test("no flashing: a locked screen is not rebuilt while it is still up", function()
  local S, main, H = load()
  setPin(H, "2468")
  local step = run(main, S, "lock")
  local before = {}
  for i = 1, 4 do before[i] = S.lockBase(i) end
  for _ = 1, 20 do step(0.6) end
  for i = 1, 4 do eq(S.lockBase(i), before[i], "display " .. i .. " rebuilt (flash)") end
  for _, line in ipairs(S.log) do truthy(not line:find("uncovered"), "watchdog fired: " .. line) end
  S.click(1, "DLBg_1"); S.typePin(1, "2468")
  truthy(not step(0.2))
end)

test("test lock unlocks itself and leaves no locked flag", function()
  local S, main, H = load()
  setPin(H, "2468")
  local step = run(main, S, "test")
  truthy(H.state())
  contains(S.find(S.lockBase(1), "DLInfo_1")._props.Text, "TEST")
  truthy(step(10))
  truthy(not step(25))
  eq(H.state(), nil)
  truthy(S.vars.PDL_Locked ~= "1")
  eq(S.current._props.Name, "Admin")
end)

test("showcase mode: a tap unlocks", function()
  local S, main, H = load()
  local c = H.Config.load(); c.mode = "tap"; c.hardLock = false; H.Config.save(c)
  local step = run(main, S, "lock")
  truthy(H.state())
  truthy(not S.find(S.lockBase(1), "DLPad_1"), "no pad")
  S.click(3, "DLBg_3")
  truthy(not step(0.2))
end)

test("pad always visible when tap-to-show is off, on the chosen screen", function()
  local S, main, H = load()
  setPin(H, "2468")
  local c = H.Config.load(); c.tapToShow = false; c.padScreen = 3; H.Config.save(c)
  local step = run(main, S, "lock")
  step(0.2)
  truthy(visible(S, 3)); truthy(not S.find(S.lockBase(1), "DLPad_1"))
  S.typePin(3, "2468")
  truthy(not step(0.2))
end)

test("screen info line: message, clock", function()
  local S, main, H = load()
  setPin(H, "2468")
  H.Config.saveScreen(1, { msg = "Hands off - FOH", showMsg = true, clock = true })
  local step = run(main, S, "lock")
  local text = S.find(S.lockBase(1), "DLInfo_1")._props.Text
  contains(text, "Hands off - FOH")
  truthy(text:find("%d%d:%d%d"), "clock")
  eq(S.find(S.lockBase(2), "DLInfo_2")._props.Text, "")
  S.click(1, "DLBg_1"); S.typePin(1, "2468"); step(0.2)
end)

--------------------------------------------------------------------------------
-- Auto-lock and reboot
--------------------------------------------------------------------------------
test("auto-lock arms on show load and the next run locks", function()
  local S, main, H = load()
  setPin(H, "2468")
  local c = H.Config.load(); c.autoLock = true; H.Config.save(c)
  H.armAutoLock()
  eq(S.commands[#S.commands], "Plugin 7")
  local step = run(main, S, nil)
  truthy(H.state(), "locked by the pending auto-lock")
  S.click(1, "DLBg_1"); S.typePin(1, "2468")
  truthy(not step(0.2))
end)

test("a desk locked before a reboot locks again on load", function()
  local S, main, H = load()
  setPin(H, "2468")
  local step = run(main, S, "lock")
  truthy(H.state())
  -- Power cut: the show comes back with the lock flag and the lock user.
  local S2, main2, H2 = load()
  S2.vars = S.vars
  S2.current = S2.addUser("DeskLock", "", "None")
  H2.armAutoLock()
  eq(S2.commands[#S2.commands], "Plugin 7")
  local step2 = run(main2, S2, nil)
  truthy(H2.state())
  S2.click(1, "DLBg_1"); S2.typePin(1, "2468")
  truthy(not step2(0.2))
  eq(S2.current._props.Name, "Admin", "back to the user from before the reboot")
end)

test("no auto-lock when it is off and the desk was not locked", function()
  local S, _, H = load()
  setPin(H, "2468")
  local n = #S.commands
  H.armAutoLock()
  eq(#S.commands, n)
end)

test("stale auto-lock flag is ignored", function()
  local S, main, H = load()
  setPin(H, "2468")
  S.vars.PDL_AutoPending = tostring(S.t - 3600)
  S.popups = { function() return nil end }
  run(main, S, nil)
  eq(H.state(), nil)
end)

--------------------------------------------------------------------------------
-- Menus
--------------------------------------------------------------------------------
test("locking without a PIN asks for one first", function()
  local S, main, H = load()
  S.boxes = {
    mock.button(1), -- "Set a PIN first."
    mock.form({ ["New PIN"] = "1357", ["Repeat new PIN"] = "1357" }),
    mock.button(1), -- "Saved."
  }
  local step = run(main, S, "lock")
  truthy(H.state(), "locked after setting the PIN")
  S.click(1, "DLBg_1"); S.typePin(1, "1357")
  truthy(not step(0.2))
end)

test("security: PINs must match, and the current PIN is asked", function()
  local S, main, H = load()
  setPin(H, "2468")
  S.popups = { mock.pick("PIN & security"), function() return nil end }
  S.texts = { "2468" }
  S.boxes = {
    mock.form({ ["New PIN"] = "1111", ["Repeat new PIN"] = "2222" }),
    mock.button(1), -- not the same
    mock.form({ ["New PIN"] = "1111", ["Repeat new PIN"] = "1111", ["Hard lock (block keys + faders)"] = false }),
    mock.button(1), -- saved
  }
  run(main, S, nil)
  contains(S.boxSpecs[2].message, "not the same")
  local cfg = H.Config.load()
  eq(H.Config.checkPin(cfg, "1111"), "user")
  eq(cfg.hardLock, false)
end)

test("security: wrong current PIN keeps everything", function()
  local S, main, H = load()
  setPin(H, "2468")
  S.popups = { mock.pick("PIN & security"), function() return nil end }
  S.texts = { "0000" }
  run(main, S, nil)
  eq(H.Config.checkPin(H.Config.load(), "2468"), "user")
end)

test("pictures per screen: consecutive appearances", function()
  local S, main, H = load()
  S.popups = { mock.pick("Pictures per screen"), mock.pick("Consecutive"), function() return nil end, function() return nil end }
  S.boxes = { mock.form({ ["First appearance no."] = 31 }) }
  run(main, S, nil)
  for i = 1, 4 do eq(H.Config.screen(i).app, tostring(30 + i)) end
end)

test("screen preview shows one screen and closes itself", function()
  local S, main, H = load()
  S.addAppearance(5, "Logo")
  S.popups = { mock.pick("Pictures per screen"), mock.pick("Display 2"), function() return nil end, function() return nil end }
  S.boxes = { mock.form({ ["Appearance (no. or name)"] = "Logo" }, 2) }
  local step = run(main, S, nil)
  truthy(H.state(), "previewing")
  truthy(S.lockBase(2)); eq(S.lockBase(1), nil, "only display 2")
  eq(S.current._props.Name, "Admin", "no hard lock in preview")
  truthy(not step(11))
  eq(S.lockBase(2), nil)
  eq(H.Config.screen(2).app, "Logo")
end)

test("console models: full-size, light, compact XT sizes", function()
  local _, _, H = load()
  local fs = H.Templates.rows(H.Templates.console("full-size"))
  eq(#fs, 8)
  local byIndex = {}
  for _, r in ipairs(fs) do byIndex[r.index] = r end
  eq(byIndex[3].w, 1920); eq(byIndex[3].h, 1080); eq(byIndex[3].pad, true)
  eq(byIndex[6].w, 800); eq(byIndex[6].h, 480); eq(byIndex[6].pad, false, "pad does not fit 800x480")
  eq(byIndex[10].w, 1280); eq(byIndex[10].h, 242)
  eq(#H.Templates.rows(H.Templates.console("light")), 6)
  eq(#H.Templates.rows(H.Templates.console("compact-xt")), 2)
  contains(H.Templates.report(fs, H.Templates.console("full-size")), "grandMA3 full-size")
end)

test("export for a console model goes to its own folder", function()
  local S, main = load()
  local dir = os.tmpname(); os.remove(dir)
  os.execute('mkdir -p "' .. dir .. '"')
  S.library = dir
  S.popups = { mock.pick("Export content templates"), mock.pick("grandMA3 light"), function() return nil end }
  run(main, S, nil)
  local f = assert(io.open(dir .. "/desklock_templates/light/Display8_Letterbox_encoder_1280x242.svg"))
  contains(f:read("a"), 'width="1280" height="242"'); f:close()
  os.execute('rm -rf "' .. dir .. '"')
end)

print(string.format("\n%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
