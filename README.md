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

## Using it

Run the plugin and a window opens:

```
 [ Line ][ Matrix ][ Multi-row ][ Hex ][ Rings ][ Custom ][ Presets... ]
   Pixels per row  [14,14,14                                   ]
 ┌──────────────────── live preview of one fixture ───────────────────┐
 │   1  2  3  4  5  6  7  8  9 10 11 12 13 14                          │
 │  15 16 17 18 19 20 21 22 23 24 25 26 27 28                          │
 │  29 30 31 32 33 34 35 36 37 38 39 40 41 42                          │
 └─────────────────────────────────────────────────────────────────────┘
   Fixtures  [101 Thru 104                        ] [ Use selection ]
 [x] Group [-][50][+]   [x] Layout [-][7][+]       Name [StrikeM     ]
 4 fixtures x 42 px = 168 pixels  |  grid 59 x 3  |  parts: Tubes, Face
 Fixture 101: 42 pixels, matches.
 [ Advanced... ] [ Help ]                          [  Build  ] [ Close ]
```

1. Tap the shape of your fixture, or pick one from **Presets**.
2. Set the pixel count. The preview shows pixel 1, 2, 3 ... of one fixture, coloured by part.
3. Type the fixtures (`101 Thru 116`, `101-108 + 201-208`, `Group 5`) or tap **Use selection**.
4. Tick **Group** and/or **Layout**, check the numbers (the next free slots are suggested) and tap **Build**.

The info line updates as you type: fixture count, grid size, parts, and whether the fixture's subfixtures match the shape. Problems show in red and grey out Build, and anything that would be overwritten is listed. The window stays open after a build, so you can change something and tap Build again to replace what it just made.

### Advanced...

| Row | What it does |
|---|---|
| Rotate / Flip / Turn every 2nd | How the fixtures hang |
| Per row / Gap / Cell size | Fixtures per row (`0` = one row; with `Group N` or a selection, `0` keeps their own grid arrangement), empty cells between fixtures, layout units per pixel |
| Pixel order | Start corner, direction, snake, start angle, outer ring first, row names ... (depends on the shape) |
| Pixel sub-IDs + Inspect | `auto` = the fixture's subfixtures in patch order, or type them in pixel order (`15-28, 1-14, 29-42`). **Inspect** shows how the first fixture is numbered |
| Part groups / GridStore / Keep selected | One extra group per part, store the shape on the fixture type, leave the grid selected |
| Save preset... | Saves the current shape and options under a name. It then appears in **Presets** (saved presets can be deleted from there too) |

Everything you type is remembered for next time.

### Classic dialogs

If the window can't open on your software version, the plugin falls back to the old step-by-step dialogs on its own. You can also ask for them on purpose: `Plugin "Pixel Grid Builder" "classic"`.

## Shapes

| Shape | Use it for | Options |
|---|---|---|
| **Pixel line / bar** | Pixel bars, battens, tubes | pixels, vertical, pixel 1 at the end |
| **Matrix / panel** | Panels, matrix blinders | columns, rows, column order, snake, start corner |
| **Multi-row bar** | Strobe bars with tube + RGB rows | pixels per row (`14,14,14`), row names. Rows with the same name share a part group |
| **Hex pixel wash** | Hex LED faces (7 / 19 / 37 / 61 pixels) | rings, start angle, direction, outer ring first |
| **Ring pixel wash** | Ring layouts (`1,8,16`, `12,24`, ...) | pixels per ring, start angle, direction, outer ring first, grid scale |
| **Custom pixel map** | Anything else | type the map, see below |

Presets (all editable before building):

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

Open **Advanced...** and tap **Inspect** (it inspects the first fixture in your list). The plugin prints the subfixture tree to the System Monitor and shows a summary:

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

You can also add fixtures to `USER_PRESETS` in the file, and they appear at the top of **Presets**:

```lua
local USER_PRESETS = {
  { label = "My JDC1s: tube + plates, 2 x 12", kind = "rows",
    values = { counts = "12,12", names = "Tube,Plates" }, name = "JDC1", gap = 1 },
}
```

## Offline tests

The geometry, the window (clicking buttons, typing, building) and the classic dialogs run against a small grandMA3 mock:

```
lua tests/run_tests.lua      # Lua 5.3 or 5.4
```

The mock checks that every pixel lands in its own grid cell, that only known commands are sent, and that the window's buttons and fields do what they should. It can't prove how a real console draws the window or reacts, so do a test run in onPC.
