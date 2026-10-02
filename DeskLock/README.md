# DeskLock for grandMA3

A grandMA3 Lua plugin that locks the desk behind a full-screen picture on **every** screen: main screens, the command screen, letterbox screens and onPC windows. Each screen shows its own appearance, and you unlock with a PIN on an on-screen keypad or the keyboard. Everything is set up in one settings window.

| Feature | |
|---|---|
| **Own picture per screen** | Every display gets its own appearance from the Appearances pool |
| **Pixel-perfect sizes** | Reads the real size of every display, shows it, and exports an SVG template per screen at exactly that size, with the PIN pad area marked |
| **Full lock (hard lock)** | Also logs in as a no-rights user `DeskLock`, so keys, executors, faders and encoders do nothing. Unlocking logs you back in |
| **Survives reboot** | A desk that was locked stays locked after a reboot, power cut or show reload |
| **Auto-lock on show load** | Optional |
| **Failed attempt counter** | Shown on the lock screen, reported after unlocking, kept in an unlock history |
| **Cooldown** | After N wrong PINs the keypad locks for a while. The wait doubles every round, up to 15 min |
| **Master PIN** | Optional second PIN, for example for the system tech |
| **Watchdog** | If a screen is uncovered (Esc, a view change, a new display connected) it is covered again within a second. If someone logs in as another user while locked, the plugin logs back in as the lock user |
| **Info line** | Optional message text and clock per screen |
| **Test lock / preview** | Test lock unlocks itself after 30 s. Preview shows one screen for 10 s |
| **One-press lock** | `Plugin "DeskLock" "lock"` in a macro or on an executor |
| **Showcase mode** | No PIN: a tap anywhere unlocks. For a picture on the desk, not for security |
| **Settings window** | Tabs for Lock, Screens, Security, Templates and Help. Changes save as you make them |
| **Quick unlock** | Type the PIN on the keypad or the keyboard. It unlocks as soon as the last digit is in, no OK needed |

## Install

1. Copy `DeskLock.xml` and `DeskLock.lua` into the plugins folder:
   - **onPC on Windows:** `C:\ProgramData\MALightingTechnology\gma3_library\datapools\plugins\` (`ProgramData` is hidden: paste the path into the Explorer address bar)
   - **onPC on macOS:** `~/MALightingTechnology/gma3_library/datapools/plugins/`
   - **Console:** `grandMA3/gma3_library/datapools/plugins/` on a USB stick
2. On the desk, edit an empty slot in the **Plugins** pool → **Import** → *DeskLock*.
3. Tap the plugin to open its settings window.

**Run the Test lock in onPC with your show before using it on a real desk.** See *What to check on onPC* below.

## The settings window

Tap the plugin and the window opens on the screen you tapped it from. Every change is saved the moment you make it, and the line at the bottom confirms what happened. Close the window with **X** or Esc.

| Tab | |
|---|---|
| **Lock** | **LOCK DESK**, **Test lock** (unlocks itself after 30 s), what's set up (PIN, hard lock, auto-lock), each screen with its picture (`NOT FOUND` if the appearance doesn't exist), and the count of wrong PINs with a **Reset** button |
| **Screens** | One row per display: size, appearance (number or name), message text, clock / text / PIN pad switches, and **Preview**. Below the rows: type an appearance, then **Same on all screens** or **Consecutive from it** (e.g. 31 → display 1, 32 → display 2 ...). More than 7 displays: `<` `>` page through |
| **Security** | PIN, master PIN, cooldown, PIN pad, hard lock, auto-lock, showcase mode. Once a PIN is set, this tab asks for it first |
| **Templates** | Exact pixel size of every screen for **This desk**, **full-size**, **light** or **compact XT**, and **Export SVG templates + size list** |
| **Help** | Short how-to |

Other ways to run it:

| Command | |
|---|---|
| `Plugin "DeskLock" "lock"` | Locks straight away (for a macro or an executor) |
| `Plugin "DeskLock" "test"` | Test lock |
| `Plugin "DeskLock" "screens"` (or `security`, `templates`, `help`) | Opens the window on that tab |
| `Plugin "DeskLock" "menu"` | The old popup menu, if the window doesn't work on your version |

If the window can't be built, the plugin falls back to the popup menu by itself.

## Screen resolutions

These are the native sizes of each console's internal screens, from MA Lighting's grandMA3 technical data. Make every picture **exactly** this size. Ready-made templates for each console are in [`templates/`](templates/).

| Display | full-size | light | compact XT |
|---|---|---|---|
| 1 – Main | 1920 × 1080 | 1920 × 1080 | 1920 × 1080 |
| 2 – Main | 1920 × 1080 | 1920 × 1080 | 1920 × 1080 |
| 3 – Main | 1920 × 1080 | – | – |
| 6 – Command (right) | 800 × 480 | 800 × 480 | – |
| 7 – Command (left) | 800 × 480 | 800 × 480 | – |
| 8 – Letterbox (encoders) | 1280 × 242 | 1280 × 242 | – |
| 9 – Letterbox (executors) | 1280 × 242 | 1280 × 242 | – |
| 10 – Letterbox (executors) | 1280 × 242 | – | – |
| External monitors | 1920 × 1080 | 1920 × 1080 | 1920 × 1080 |

- The PIN pad (360 × 520) only fits on the 1920 × 1080 screens. The command and letterbox screens show only their picture, and tapping one brings the pad up on a main screen.
- The letterbox height is **242**, not 240.
- The same table is in the plugin on the **Templates** tab: pick *full-size*, *light* or *compact XT* as well as *This desk*. That's useful in onPC, where the measured sizes are those of your onPC windows.
- Pick **This desk** once on the real console to confirm the display numbers match.

## Making the pictures (pixel-perfect)

1. Open the **Templates** tab. With **This desk** you get the exact pixel size of every display on the desk you are at:

   ```
   Display 1  Display 1       1920 x 1080   (16:9)  + PIN pad
   Display 3  Command         1280 x 800    (8:5)   + PIN pad
   Display 4  Letterbox       1920 x 240    (8:1)
   ```

   (Example output. Run it on the desk or onPC you will lock, because sizes depend on the hardware and the onPC window.)
2. Press **Export SVG templates + size list** and choose the internal drive or a USB stick. In `desklock_templates/` you get:
   - `DisplayN_<name>_<W>x<H>.svg`: one per screen, exactly the screen size. The `guides` layer shows the edge, a 5 % safe area, the centre lines, the **PIN pad area** (keep important artwork out of it) and the info line if you use one
   - `screens.csv` / `screens.txt`: every size, plus the PIN pad position (`pad_x, pad_y, pad_w, pad_h`)
3. Open an SVG in Photoshop, Illustrator, Affinity or Figma, design on the `artwork` layer, hide `guides`, and export a PNG at 100 %.
4. Import the PNGs into the **Images** pool and put each one in an **appearance**.
5. **Screens** tab: type each display's appearance (number or name). **Preview** shows it for 10 s.

The Lock tab shows which pictures can't be found. The exported size list (`screens.txt`) also checks your pictures. It flags `image is 1920x1200` when an appearance's image doesn't match its screen, and `appearance not found`.

## Unlocking

Tap any screen and the PIN pad comes up. Type the PIN on the pad, or on the keyboard (onPC). It unlocks as soon as the last digit is in, so there's no need to press OK. What you type shows as `****`. A wrong PIN of full length counts as one wrong attempt and clears the field. **C** clears, **OK** checks what you've typed so far.

The plugin knows how long your PIN is, so it can unlock on the last digit. If you set the PIN with version 1.0, set it again once so this works. Until then, press **OK**.

## PIN & security

**Security** tab. Once a PIN is set, the tab asks for the current PIN before you can change anything.

| Field | |
|---|---|
| PIN: New / Repeat → **Save PIN** | 4–8 digits |
| Master PIN → **Save master PIN** / **Remove master PIN** | Optional second PIN |
| Wrong PINs before cooldown | Default 5 |
| Cooldown seconds | Default 30, doubles every round (max 900) |
| PIN pad hides after | Seconds without a touch before the pad hides and clears the entry |
| PIN pad screen | `0` = the pad comes up on the screen you tap (screens too small for it, such as a letterbox, use the first big screen). A number = always that display |
| Hard lock | Log in as the no-rights user while locked (default on) |
| Auto-lock when the show loads | |
| Show failed attempts | Counter on the lock screen |
| Tap screen to show PIN pad | Off = the pad is always visible |
| Showcase mode | No PIN: a tap unlocks |

The PIN is stored only as a salted hash (plus its length, for the quick unlock), in global variables (`PDL_*`) that are saved with the show. A 4–8 digit PIN is not a strong password. The hash keeps the PIN out of plain sight, and the cooldown slows down guessing.

### How the hard lock works

On lock, the plugin creates (once) a user `DeskLock` with rights **None** and the same user profile as you, so your screens look the same. It then logs in as that user and remembers who you were. On unlock it logs you back in. If your user has a password, the desk asks for it. With hard lock off, only the touch screens are covered, and the hardware keys, executors and encoders still work.

### Forgot the PIN?

Use the master PIN if you set one. Without one, there is no backdoor in the plugin. Delete the global variable `PDL_PinHash` (in the Variables window, or with `DelGlobalVariable "PDL_PinHash"`) from a session that is logged in with rights, then set a new PIN. If you are stuck as user `DeskLock`, type `Login "YourUser"` on the command line.

## Auto-lock and reboot

grandMA3 runs the plugin's code when the show loads. If auto-lock is on, or the desk was locked when it went down, the plugin starts itself 3 seconds later and locks. If the desk comes back logged in as `DeskLock`, it locks as well, so you can unlock with the PIN and go back to your own user.

## Settings in the file

At the top of `DeskLock.lua`:

| Setting | Default | |
|---|---|---|
| `padWidth` / `padHeight` | 360 / 520 | PIN pad size in px (the templates follow this) |
| `infoHeight` | 56 | Info line height |
| `lockUserName` | `DeskLock` | The no-rights user |
| `testSeconds` / `previewSeconds` | 30 / 10 | |
| `autoLockDelay` | 3 | Seconds after show load |
| `maxCooldown` | 900 | |
| `debug` | false | Log to the System Monitor |

## What to check on onPC

This plugin was written and tested against an offline mock of the console (`lua tests/run_desklock_tests.lua`), not on a real desk. The mock covers the lock logic, PIN handling (keypad and keyboard), cooldown, hard lock login and logout, the watchdog, auto-lock, the templates and every tab of the settings window. A few console details differ between grandMA3 versions, and the plugin tries known alternatives for each one:

- **Picture on the lock screen.** The plugin sets the appearance on the full-screen button. If your version doesn't take it, it tries the appearance's image as a texture or icon, and then the appearance colour. Turn on `debug` to see which one was used. **Save + preview** checks this in 10 s.
- **Hard lock.** Check that the `DeskLock` user appears in the Users list with rights *None*, and that unlocking logs you back in.
- **Auto-lock.** Turn it on, save the show, load it again.
- **Settings window.** Check that the switches tick and untick, and that typing in the fields saves (the bottom line confirms each change). If the window doesn't open or looks wrong, `Plugin "DeskLock" "menu"` gives you the popup menu.
- **Typing the PIN.** On onPC, tap a screen, then type the PIN on the keyboard. On the console, check whether the desk's number keys type into the PIN field. If they don't, use the on-screen pad.

Use **Test lock** for all of this: it unlocks itself after 30 s.
