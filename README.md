# fernedda

Ground control for a sailboat: a live dashboard of boat data from a
[Signal K](https://signalk.org) server, plus notes organised by boat system.
Native Qt 6 / QML, made for a laptop now and a Raspberry Pi screen later.

- **Dashboard**: wind, navigation, depth, house bank, engine, tanks, weather, heel and position.
  Click any card to zoom into its history (5 min to 6 h).
- **Data**: every Signal K path the boat reports, live, with sparklines. Use it to check what a new sensor is sending.
- **Notes**: Markdown files in a folder per part of the boat (`boat/below/engine/…`), shown on a
  drawing of the S2 35C (outside profile, deck, below decks) or by system. Spots are sub-folders
  (`boat/below/engine/raw-water-strainer/`), drawn as pins you can drag. Notes are edited in Neovim.
  *Insert readings* stamps engine hours, battery and position into the note you're editing.
- **Night / red night-vision / day** themes (top-right button). F11 toggles full screen.

With no server it runs a built-in **simulated boat**. Switch to a real server in Settings.

## Neovim alongside

Opening Notes starts a terminal beside the app (`alacritty`, or set `FERNEDDA_TERMINAL`, e.g.
`foot -a fernedda-nvim -e`) running `nvim` on the boat folder, linked both ways:

- move the cursor in oil and the app shows that part of the boat (or previews the note);
- pick a part of the boat or a note in the app and oil's cursor moves to it (only while oil is
  showing; a note you're editing is left alone); `e` / Enter opens the note in nvim.

The link is `nvim/lua/fernedda.lua` (loaded only into that nvim; your config is untouched) and a
socket at `$XDG_RUNTIME_DIR/fernedda.sock`. Sway tiles the terminal next to the app; to size it,
add e.g. `for_window [app_id="fernedda-nvim"] resize set width 40 ppt` to your sway config.

The boat folder is `boat/` in this repo (git-ignored); set `FERNEDDA_BOAT_DIR` to use another.

## Keyboard

Vim-style normal mode everywhere; typing in a text field is insert mode (Esc leaves it).

- `f` — hints: every clickable thing (and every part of the boat) gets a label; type it to click
- `?` — all keys · `H` / `L` — previous / next page
- Notes: `j` `k` `gg` `G` move · `Enter`/`e` edit in nvim · `o` new note · `-` up a folder ·
  `J` `K` next / previous part of the boat · `1` `2` `3` or `gt` `gT` views · `/` search ·
  `p` pin · `dd` delete · `a` add spot · `i` insert readings · `s` boat / systems · `t` nvim

## Build

```sh
sudo dnf install qt6-qtbase-devel qt6-qtdeclarative-devel qt6-qtwebsockets-devel
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
| `src/NotesModel`    | The boat folder: notes, spots, live file watching (the `Notes` singleton) |
| `src/NvimLink`      | The two-way link with Neovim, launching its terminal (the `Nvim` singleton) |
| `src/KeyRouter`     | Normal / insert mode keyboard (the `Keyboard` singleton) |
| `nvim/lua/fernedda.lua` | The Neovim side of the link (oil cursor → app; reveal / edit / insert) |
| `qml/BoatS235C.js`  | The boat drawing and its tappable zones, as data in metres; edit to match your boat |
| `qml/BoatView.qml`  | Renders one view of the boat, hit-tests zones, places and drags spots |
| `qml/`              | UI: `Theme`, `Units` (SI → knots/°C/…), cards, gauges, pages |

To check a layout without a display:
`QT_QPA_PLATFORM=offscreen FERNEDDA_SCREENSHOT=shot.png ./build/fernedda`
(add `FERNEDDA_KEYS="f s f"` to type keys first).
