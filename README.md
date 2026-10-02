# grandMA3 plugins

| Plugin | |
|---|---|
| [Pixel Grid Builder](#pixel-grid-builder-for-grandma3) | Selection grids and layouts for pixel fixtures |
| [DeskLock](DeskLock/README.md) | Locks the desk behind its own picture on every screen, with PIN unlock, hard lock and pixel-exact templates per screen |

Tests: `lua tests/run_tests.lua` and `lua tests/run_desklock_tests.lua`.

# Pixel Grid Builder for grandMA3

A grandMA3 Lua plugin that builds **selection grids** (stored as groups) and **layout views** for multi-instance pixel fixtures. It handles pixel washes, pixel lines and bars, matrices, multi-row strobe bars like the Chauvet Color STRIKE M, and any other pixel arrangement you can type.

You pick a shape, list your fixtures and press Build. For every fixture the plugin places each pixel (subfixture) in the selection grid with the `Grid x/y` keyword. It then stores:

| Output | What you get |
|---|---|
| **Grid group** | One group with every pixel of every fixture at its real position: `StrikeM Grid` |
| **Part groups** | One group per part of the fixture: `StrikeM Tubes`, `StrikeM Face` or `Hex19 Center`, `Hex19 Ring 1`, ... |
| **Layout view** | A layout with one element per pixel at its physical position (real hex and ring geometry) |
| **GridStore** *(optional)* | Stores the pixel shape on the fixture type, so selecting a fixture and pressing **Down** brings back the shape |

## Install

1. Copy `PixelGridBuilder/PixelGridBuilder.xml` and `PixelGridBuilder/PixelGridBuilder.lua` into
   `grandMA3/gma3_library/datapools/plugins/` on a USB stick, or into the same folder of your onPC install.
2. On the console, edit an empty slot in the **Plugins** pool → **Import** → choose *Pixel Grid Builder*.
3. Tap the plugin to run it.

Written for the grandMA3 2.x command syntax. It needs the `Grid` keyword, and `GridStore` for the optional fixture-type step. **Try it in onPC with your show file before using it on a live show.**

## Quick start

1. Patch the fixtures in a pixel mode. All the fixtures in one build should be the same type and mode.
2. Run the plugin and choose a shape, or one of the **Quick** presets.
3. **Shape dialog**: set the pixel count, rows, rings or map.
4. **Rig & output dialog**:

   | Field | Meaning |
   |---|---|
   | Fixtures | `101 Thru 116`, `101-108 + 201-208`, `Group 5`, or `sel` (current selection) |
   | Pixel sub-IDs | `auto` = the fixture's subfixtures in patch order. Or type them in pixel order: `1 Thru 42`, `2-43`, `15-28, 1-14, 29-42`, `1.1-1.14` |
   | Fixtures per row | `0` = one row. With `Group N` or `sel`, `0` keeps the grid arrangement of the main fixtures, so you can lay out the main fixtures first (or use MA's 3D → selection grid tool) and the plugin expands each one into its pixels |
   | Gap between fixtures | Empty cells between fixtures. Use 0 for continuous lines |
   | Rotate / Flip | Orientation of every fixture: rotate 0/90/180/270, flip left-right, flip up-down |
   | Turn every 2nd fixture 180 | For bars hung alternating directions |
   | Name | Base name for the groups and layout |
   | Group no. / Layout no. | Where to store. `0` = don't store. The next free slots are suggested |
   | Layout cell size | Layout units per pixel |

5. Check the summary (cell count, grid size, what gets created, anything that will be overwritten, and a text preview of the first fixture's pixels), then press **Build**.

The finished grid stays selected, so you can start programming straight away.

## Shapes

| Shape | Use it for | Options |
|---|---|---|
| **Pixel line / bar** | Pixel bars, battens, tubes | pixels, vertical, pixel 1 at the end |
| **Matrix / panel** | Panels, matrix blinders | columns, rows, column order, snake, start corner |
| **Multi-row bar** | Strobe bars with tube + RGB rows | pixels per row (`14,14,14`), row names. Rows with the same name share a part group |
| **Hex pixel wash** | Hex LED faces (7 / 19 / 37 / 61 pixels) | rings, start angle, direction, outer ring first |
| **Ring pixel wash** | Ring layouts (`1,8,16`, `12,24`, ...) | pixels per ring, start angle, direction, outer ring first, grid scale |
| **Custom pixel map** | Anything else | type the map, see below |

Quick presets (all editable before building):

- **Color STRIKE M style**: 3 rows × 14 (tube / RGB face / tube), parts `Tubes` and `Face`
- **Hex 19**: Robe Spiider / B-EYE K10 style
- **Hex 37**: B-EYE K20 style
- **Matrix 5×5 / 6×6**: MagicPanel FX / 602 style
- **Pixel bar 20**: impression X4 Bar 20 style

> The presets describe the *shape* only. Subfixture numbering depends on the fixture profile and mode, so check it once with **Inspect fixture** (below).

### Custom pixel map syntax

```
/          new row
.          empty cell (also - or _)
4-9        a run of cells, sub-IDs 4 to 9 (also 4 Thru 9, or 9-4 to run backwards)
2.3        nested sub-ID (Fixture 101.2.3)
Name:      at the start of a row starts a new part (one group per part)
```

Examples:

```
Tubes: 1-14 / Face: 15-28 / Tubes: 29-42          Color STRIKE M style, 3 rows
Ring: . 1 2 . / 8 . . 3 / 7 . . 4 / . 6 5 . // Center: 9
1.1-1.12 / 2.1-2.12                               two nested branches, 2 rows
```

In a custom map the numbers *are* the sub-IDs, so the Pixel sub-IDs field is not used.

## Getting the pixel order right

Choose **Inspect fixture** in the plugin menu and enter a fixture ID. The plugin prints the subfixture tree to the System Monitor and shows a summary:

```
Fixture 101 "STRIKE 1": 45 subfixtures, 42 pixels (subfixtures without children)
.1  Tube A  (14 inside)
    .1.1  Cell 1
    ...
```

- `auto` uses every pixel (subfixture with no children of its own) in patch order.
- If the fixture has more pixels than the shape (for example a master subfixture), the plugin asks whether to use the first or the last N.
- If the profile numbers the parts in a different order from the shape, type the sub-IDs in shape order. For a profile that numbers face 1-14, tube A 15-28 and tube B 29-42, while the shape goes top tube / face / bottom tube, enter `15-28, 1-14, 29-42`.
- Pixels running the wrong way round? Change the start angle, the direction, snake, or the start corner, or rotate/flip the fixture.

## How it works

For each grid the plugin runs:

```
ClearSelection
Grid 0/0
Fixture 101.1
Grid 1/0
Fixture 101.2
...
Store Group 50 /Overwrite
Label Group 50 "StrikeM Grid"
```

For layouts it runs `Store Layout N` and `Assign Fixture 101.1 At Layout N`, then sets each element's `PosX`, `PosY`, `PositionW` and `PositionH` from Lua. An existing layout is deleted and rebuilt, and an existing group is overwritten. The summary lists both before you confirm.

Where your version supports `CreateUndo`, the build is grouped into one undo step.

## Settings

At the top of `PixelGridBuilder.lua`:

| Setting | Default | |
|---|---|---|
| `layoutYUp` | `true` | Set to `false` if layouts come out upside down |
| `layoutFill` | `0.9` | How much of each layout cell an element fills |
| `rememberValues` | `true` | Remember the last values (stored as user variables `PGB_*`) |
| `echoCommands` | `false` | Print every command to the System Monitor |
| `yieldEvery` | `100` | Let the console redraw the progress bar every N commands |

Add your own fixtures to `USER_PRESETS` and they appear at the top of the shape list:

```lua
local USER_PRESETS = {
  { label = "My JDC1s: tube + plates, 2 x 12", kind = "rows",
    values = { counts = "12,12", names = "Tube,Plates" }, name = "JDC1", gap = 1 },
}
```

## Offline tests

The geometry and the full dialog → command flow run against a small grandMA3 mock:

```
lua tests/run_tests.lua      # Lua 5.3 or 5.4
```

The mock checks that every pixel lands in its own grid cell and that only known commands are sent. It can't prove how a real console reacts, so do a test run in onPC.
