# DeskLock for grandMA3

A grandMA3 Lua plugin that locks the desk behind a full-screen picture on **every** screen: main screens, the command screen, letterbox screens and onPC windows. Each screen shows its own appearance, and you unlock with a PIN on an on-screen keypad.

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

## Install

1. Copy `DeskLock.xml` and `DeskLock.lua` into the plugins folder:
   - **onPC on Windows:** `C:\ProgramData\MALightingTechnology\gma3_library\datapools\plugins\` (`ProgramData` is hidden: paste the path into the Explorer address bar)
   - **onPC on macOS:** `~/MALightingTechnology/gma3_library/datapools/plugins/`
   - **Console:** `grandMA3/gma3_library/datapools/plugins/` on a USB stick
2. On the desk, edit an empty slot in the **Plugins** pool → **Import** → *DeskLock*.
3. Tap the plugin to open its menu.

**Run the Test lock in onPC with your show before using it on a real desk.** See *What to check on onPC* below.

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
- The same table is in the plugin: **Screen sizes** and **Export templates** let you pick *grandMA3 full-size / light / compact XT* as well as *this desk*. That's useful in onPC, where the measured sizes are those of your onPC windows.
- Run **Screen sizes → This desk** once on the real console to confirm the display numbers match.

## Making the pictures (pixel-perfect)

1. Run the plugin → **Screen sizes**. You get the exact pixel size of every display on *this* desk:

   ```
   Display 1  Display 1       1920 x 1080   (16:9)  + PIN pad
   Display 3  Command         1280 x 800    (8:5)   + PIN pad
   Display 4  Letterbox       1920 x 240    (8:1)
   ```

   (Example output. Run it on the desk or onPC you will lock, because sizes depend on the hardware and the onPC window.)
2. Press **Export templates** and choose the internal drive or a USB stick. In `desklock_templates/` you get:
   - `DisplayN_<name>_<W>x<H>.svg`: one per screen, exactly the screen size. The `guides` layer shows the edge, a 5 % safe area, the centre lines, the **PIN pad area** (keep important artwork out of it) and the info line if you use one
   - `screens.csv` / `screens.txt`: every size, plus the PIN pad position (`pad_x, pad_y, pad_w, pad_h`)
3. Open an SVG in Photoshop, Illustrator, Affinity or Figma, design on the `artwork` layer, hide `guides`, and export a PNG at 100 %.
4. Import the PNGs into the **Images** pool and put each one in an **appearance**.
5. Plugin → **Pictures per screen**: pick a display and enter its appearance (number or name). **Save + preview** shows it for 10 s. Shortcuts: *Same appearance on every screen*, and *Consecutive appearances* (e.g. 31 → display 1, 32 → display 2, ...).

The size list also checks your pictures. It flags `image is 1920x1200` when an appearance's image doesn't match its screen, and `appearance not found`.

## PIN & security

Plugin → **PIN & security**. Once a PIN is set, it asks for the current PIN before you can change anything.

| Field | |
|---|---|
| New PIN / Repeat | 4–8 digits. Leave empty to keep the current PIN |
| Master PIN | Optional second PIN. `0` removes it |
| Wrong PINs before cooldown | Default 5 |
| Cooldown seconds | Default 30, doubles every round (max 900) |
| PIN pad hides after | Seconds without a touch before the pad hides and clears the entry |
| PIN pad screen | `0` = the pad comes up on the screen you tap (screens too small for it, such as a letterbox, use the first big screen). A number = always that display |
| Hard lock | Log in as the no-rights user while locked (default on) |
| Auto-lock when the show loads | |
| Show failed attempts | Counter on the lock screen |
| Tap screen to show PIN pad | Off = the pad is always visible |
| No PIN – tap unlocks | Showcase mode |

The PIN is stored only as a salted hash, in global variables (`PDL_*`) that are saved with the show. A 4–8 digit PIN is not a strong password. The hash keeps the PIN out of plain sight, and the cooldown slows down guessing.

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

This plugin was written and tested against an offline mock of the console (`lua tests/run_desklock_tests.lua`), not on a real desk. The mock covers the lock logic, PIN handling, cooldown, hard lock login and logout, the watchdog, auto-lock and the templates. A few console details differ between grandMA3 versions, and the plugin tries known alternatives for each one:

- **Picture on the lock screen.** The plugin sets the appearance on the full-screen button. If your version doesn't take it, it tries the appearance's image as a texture or icon, and then the appearance colour. Turn on `debug` to see which one was used. **Save + preview** checks this in 10 s.
- **Hard lock.** Check that the `DeskLock` user appears in the Users list with rights *None*, and that unlocking logs you back in.
- **Auto-lock.** Turn it on, save the show, load it again.

Use **Test lock** for all of this: it unlocks itself after 30 s.
