# Speed Master LEDs for grandMA3

A grandMA3 Lua plugin that flashes your executors' **key LEDs** and **encoder LEDs** in time with a speed master's BPM. The encoder LED is the knob LED, or the fader LED on 2xx executors.

Put Speed Master 1 on an executor (for example the X-keys and knobs, 291-298), run the plugin and press **Start**. The key and the knob above it flash on every beat. Change the tempo by tapping or by moving the master, and the flashing follows.

## Install

1. Copy `SpeedMasterLEDs/SpeedMasterLEDs.xml` and `SpeedMasterLEDs/SpeedMasterLEDs.lua` into
   `grandMA3/gma3_library/datapools/plugins/` on a USB stick.
2. On the console, edit an empty slot in the **Plugins** pool → **Import** → choose *Speed Master LEDs*.
3. Tap the plugin to run it.

It needs real console hardware (see [Supported hardware](#supported-hardware)). **Try it before a show**: start it, check that the right LEDs flash, then stop it.

## Quick start

1. Assign Speed Master 1 to the executors whose LEDs should flash.
2. Run the plugin. The setup dialog opens:

   | Field | Meaning |
   |---|---|
   | Speed master | Which speed master sets the tempo (1-16) |
   | Executors | `auto`, executor numbers, or use **Learn keys** (see below) |
   | Flashes per beat | `1` = every beat, `2` = twice per beat, `1/2` = every other beat |
   | On time % | How much of each beat the LEDs stay on |
   | Encoder colour | `White`, `Red`, `Orange`, `Amber`, `Yellow`, `Green`, `Cyan`, `Blue`, `Purple`, `Magenta`, `Pink`, or `255,0,0` / `#FF0000` |
   | Brightness between flashes % | `0` = dark between flashes. Raise it to keep the executors visible |
   | Flash the keys | Key LEDs |
   | Flash the encoder / fader LEDs | Knob LEDs (191-298, 3xx, 4xx) and fader LEDs (2xx) |
   | Also flash the 5 screen encoders | The dual encoders under the screen |
   | Pulse (fade out) instead of blink | Each flash fades out over the on time instead of switching off |
   | Line up with taps | Start a flash when you tap a flashing key, or when the BPM jumps after a tap tempo |

3. Press **Start**. The plugin keeps running in the background.
4. To stop, run the plugin again and choose **Stop flashing**. **Change settings** and **Check BPM and hardware** are in the same menu.

The dialog remembers your values (user variables `SML_*`).

## Executors

| You type | What flashes |
|---|---|
| `auto` | The executors on the current page that hold the speed master. When you change page, the flashing moves with the master, and stops while the master isn't on the page |
| `291, 293-295` | The X-key executors 191-198 and 291-298, with the knobs above X1-X8 (291-298) |
| `201`, `401-405` | Executors on the fader module, when the console has only one |
| `MFE:401`, `MFX:201-205` | Executors on a given fader module: `MFE` = the module with encoders, `MFX` = the module with the crossfader |

**Learn keys** in the setup dialog: tap each key you want to flash, and tap it again to remove it. Touching a fader picks its 2xx executor. The keys light up as you pick them. The plugin stops listening 5 seconds after the last tap and fills in the Executors field. Each tap also does what the key normally does, so tap the speed master's own keys.

On a console with two fader modules (the full-size), use Learn keys or `MFE:` / `MFX:` for executors 101-415. There `auto` and plain numbers can't tell which module shows them.

## Start and stop from a macro or key

The text after the plugin name is passed to the plugin:

```
Plugin "Speed Master LEDs" "toggle"     start with the saved settings, or stop
Plugin "Speed Master LEDs" "start"
Plugin "Speed Master LEDs" "stop"
Plugin "Speed Master LEDs" "check"      show the BPM and hardware it sees
```

If running the plugin again doesn't reach the running copy, stop it from the command line:

```
Lua "SpeedMasterLEDs_Stop()"
```

## Timing

- **BPM**: the plugin reads the value shown on the speed master (BPM, Hz or seconds) every frame. It also reads the fader position, which gives the same value with more decimals, and uses that when the two agree. Use **Check BPM and hardware** to see both.
- **Beat position**: Lua can read the speed master's BPM, but not where its beat is. The flashing starts when the plugin starts. With **Line up with taps** on, a flash also starts when you tap a flashing key, or when the BPM jumps after a quiet spell, which is how tap tempo changes it. Riding the fader changes the speed smoothly without restarting the beat.
- **Speed master at 0**: when the master stops, the LEDs go back to the console until it runs again.

## Supported hardware

The plugin sets LEDs with the console's `SetLED()` Lua function. MA documents which LED is which only for three modules: the **Master Module (MM)**, the **Fader Module Encoder (MFE)** and the **Fader Module Crossfader (MFX)**. These are the modules of the full-size, and the light should report the same types. The plugin checks which modules the console has when it starts, and says so if it finds none it knows.

**onPC, compact, compact XT and wings are not supported**: MA doesn't publish their LED layout.

Safety:

- The manual warns that setting an index with no LED behind it can crash and reboot the module. The plugin only writes the LEDs in its built-in map, which comes from the manual's tables. The offline tests check the map against those tables.
- It identifies each module by its product type. If a full-size module doesn't report its type, the plugin falls back to the module names in the manual. It then writes only LEDs 1-140. Those are ordinary LEDs on all three modules, so a wrong guess can light the wrong LED but can't hit a missing one. In that case the fader LEDs of 2xx and some 3xx keys are skipped.
- Modules it can't identify are never written to.
- LEDs it doesn't drive are left to the console (`-1` in the SetLED table). When the plugin stops, it hands its LEDs back. The console also takes LEDs back about 2 seconds after the last update.

## Settings

At the top of `SpeedMasterLEDs.lua`:

| Setting | Default | |
|---|---|---|
| `frameTime` | `0.02` | How often the loop wakes up, in seconds |
| `refreshTime` | `0.2` | Resend the LEDs at least this often |
| `keyBrightness` | `100` | Key LED brightness at the peak of a flash |
| `tapGap` | `0.35` | A BPM change after this many quiet seconds counts as a tap |
| `rescanTime` | `1.0` | How often `auto` looks for the speed master on the page |
| `learnIdle` / `learnMaxWait` | `5` / `20` | When Learn keys stops listening |
| `moduleTypes` | `{}` | Set module types by name if they can't be detected, e.g. `{ ["UsbDeviceMA3 2"] = "MM" }` |
| `rememberValues` | `true` | Remember the dialog values |

## Troubleshooting

Run **Check BPM and hardware**. It prints to the System Monitor and shows:

- the console type,
- what the speed master shows and the BPM the plugin uses,
- each hardware module and how its type was found,
- the executors on this page that hold the speed master,
- what would flash, and any problems.

For a module it can't identify, it also prints all of the module's properties. Set that module in `moduleTypes` and import the plugin again.

## Offline tests

```
lua tests/run_speed_master_leds_tests.lua      # Lua 5.3 or 5.4
```

The tests run the plugin against a small grandMA3 mock with a simulated clock. They check:

- the LED and key map against the manual's tables (`tests/fixtures/`),
- that every SetLED call stays on LEDs that exist on that module,
- the flash timing, taps, page changes, Learn keys and the menus.

They can't prove how a real console reacts, so do a test run on the console.
