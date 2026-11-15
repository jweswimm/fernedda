# fernedda

Ground control for a sailboat: a live dashboard of boat data from a
[Signal K](https://signalk.org) server, plus folders of documents for each part of the boat.
Native Qt 6 / QML, made for a laptop now and a Raspberry Pi screen later.

- **Dashboard**: wind, navigation, depth, house bank, engine, tanks, weather, heel and position.
  Click any card to zoom into its history (5 min to 6 h).
- **Data**: every Signal K path the boat reports, live, with sparklines. Use it to check what a new sensor is sending.
- **Notes**: in the boat folder itself, a slowly turning 3D model of the S2 35C. Go into a part of the boat, or
  choose a view, for its drawing (outside profile, deck, below decks). Every part of the boat is a folder
  (`boat/below/engine/`), shown on the drawing as a small graph of the folders and files inside it.
  Tap a part (or press Enter on it) and Neovim comes up in a card over the drawing, with oil in that folder;
  the drawing moves aside to stay clear of it.
  From the card you can **rename** the part (it's the folder's name) or **redraw its border**.
  *Insert readings* stamps engine hours, battery and position into the file you're editing.
- **Night / red night-vision / day** themes (top-right button): gruvbox dark and light, plus red. F11 toggles full screen.

With no server it runs a built-in **simulated boat**. Switch to a real server in Settings.

## Neovim in the app

The Notes page has Neovim in a card floating over the boat: a real `nvim --embed` on the boat folder,
with your config and plugins, drawn by the app itself, so it needs no terminal or window manager.
It comes up when you tap a part of the boat (or press Enter on one) and goes away with Esc (once you're back
out at the whole view), its ×, a tap on empty water, or `Ctrl+T` (which also brings it back, from anywhere). It's linked both ways:

- move the cursor in oil and the app shows that part of the boat;
- tap a part of the boat and oil opens its folder; move around the boat or pick a view (Outside, Deck, Below)
  and oil follows (only while oil is showing; a file you're editing is left alone);
- rename a part's folder in oil and the part takes the new name (oil and the app always show the same name).

`Alt+Tab` or `Ctrl+;` moves the keyboard between the card and the app. Drag the card's left edge to resize it.
Neovim closes with the app: if files are unsaved it asks first, in the card, and Cancel keeps everything open.
(Closing the window again while it's asking stops Neovim; recover from its swap files.)

**Touch mode** (on by default, `t` toggles) is for a touch screen: oil's files and folders become buttons you
tap to open, the status line at the bottom goes up a folder (or back to the folder from a file), and the text
is bigger with taller rows. The vim keys work as ever.

**Changing parts of the boat**: the card's title bar has **Rename**, which renames the part's folder (oil
follows), and **Redraw border**: tap the corners of the new outline on the drawing, then tap the first corner
or *Done*. While drawing, scroll or pinch to zoom, drag to pan, *Fit* to go back; *Reset* restores the
original outline. Borders and renamed folders are kept in `boat/.zones.json`; the drawing in
`qml/BoatS235C.js` stays the original.

**Layers**: more sets of parts over the same drawing of a view, e.g. an *electrical* layer over Below. The bar at
the bottom of the drawing switches between **Main** (the drawing's own parts) and your layers; **+ Layer** adds
one, and in a layer **+ Area** (`n`) or **+ Line** (`N`) draws a new part, which then gets a folder and asks for
its name. An area is a closed outline; a line is an open run of segments (a wire, a hose), tapped anywhere along it.
A layer is a folder in the view's folder and its parts are folders in that (`boat/below/electrical/panel/`);
renaming either in oil is followed. Layers live in `boat/.zones.json` too.

The link is `nvim/lua/fernedda.lua`, loaded only into that nvim; your config is untouched.

The boat folder is `boat/` in this repo; set `FERNEDDA_BOAT_DIR` to use another.

## Keyboard

Vim-style normal mode everywhere; typing in a text field is insert mode (Esc leaves it).

- `f` — hints: every clickable thing (and every part of the boat) gets a label; type it to click
- `?` — all keys · `H` / `L` — previous / next page (views on Notes) · `Alt+Tab` or `Ctrl+;` — switch between Neovim and the app · `Ctrl+T` — show / hide Neovim
- Notes: `h` `j` `k` `l` move to the part of the boat left / below / above / right ·
  `Enter` open its folder in Neovim · `Esc` back out to the whole view, then put Neovim away ·
  `Space` `h` or `-` back / up a folder, out to the whole boat · `0` the 3D model · `1` `2` `3`, `H` `L` or `gT` `gt` views · `z` zoom on / off ·
  `t` touch mode on / off · `r` rename the part · `b` redraw its border · `n` / `N` new area / line (in a layer) · `i` insert readings
- Drawing a border: tap corners · `u` undo · `+` / `-` zoom, `0` fit · `Enter` done · `Esc` cancel

## Build

```sh
sudo dnf install qt6-qtbase-devel qt6-qtdeclarative-devel qt6-qtwebsockets-devel qt6-qtquick3d
cmake -S . -B build
cmake --build build      # also installs to ~/.local (FERNEDDA_AUTO_INSTALL)
./build/fernedda
```

## Getting data aboard

1. Run `signalk-server` on a Pi (or locally: `npx signalk-server --sample-nmea0183-data`).
2. Connect instruments: NMEA 2000 (CAN HAT / USB gateway) or NMEA 0183 (serial/USB).
3. For DIY Wi-Fi sensors, flash an ESP32 with [SensESP](https://github.com/SignalK/SensESP).
4. In Settings, choose *Signal K server* and enter `host:3000`.

## Layout

| | |
|---|---|
| `src/SignalKStore`  | Path → latest value and ~6 h of history (the `Boat` QML singleton) |
| `src/SignalKClient` | Simulator or WebSocket stream, reconnects with backoff (the `Connection` singleton) |
| `src/Simulator`     | Plausible sailboat that publishes standard Signal K paths |
| `src/SignalKValue`  | QML handle on one path: `SignalKValue { path: "navigation.speedOverGround" }` |
| `src/HistoryPlot`   | Time-series chart / sparkline |
| `src/BoatFolder`    | The boat folder: makes, lists and renames folders, watches for changes (the `BoatFolder` singleton) |
| `src/NvimLink`      | Runs the embedded Neovim and speaks RPC with it (the `Nvim` singleton) |
| `src/NvimView`      | Draws Neovim's screen (bigger rows in touch mode), sends it keys and mouse input |
| `src/Msgpack`       | The MessagePack encoding that RPC uses |
| `src/KeyRouter`     | Normal / insert mode keyboard (the `Keyboard` singleton) |
| `nvim/lua/fernedda.lua` | The Neovim side of the link (oil cursor, entries on screen, folder renames → app; reveal / open_folder / tap / insert) |
| `qml/BoatS235C.js`  | The boat drawing and its tappable zones, as data in metres; edit to match your boat |
| `qml/BoatView.qml`  | Renders one view of the boat with each zone's folder graph, hit-tests zones, draws new borders |
| `qml/NotesPage.qml` | The Notes page: the drawing, the Neovim card, touch buttons, renaming, layers |
| `qml/BoatMesh.js`   | Lofts the 3D model from the lines in `BoatS235C.js` |
| `qml/Boat3D.qml`    | Renders and turns the 3D model (Qt Quick 3D) |
| `qml/`              | UI: `Theme`, `Units` (SI → knots/°C/…), cards, gauges, pages |

To check a layout without a display:
`QT_QPA_PLATFORM=offscreen FERNEDDA_SCREENSHOT=shot.png ./build/fernedda`
(add `FERNEDDA_KEYS="f s f"` to type keys first). The offscreen platform uses software rendering: it can't draw
the 3D model and can hide GPU-only problems. For a true picture, run on a headless compositor instead, e.g.
`WLR_BACKENDS=headless sway` and then `QT_QPA_PLATFORM=wayland` with the same variables.
