# fernedda

Ground control for a sailboat: a live dashboard of boat data from a
[Signal K](https://signalk.org) server, plus folders of documents for each part of the boat.
Native Qt 6 / QML, made for a laptop now and a Raspberry Pi screen later.

- **Dashboard**: wind, navigation, depth, house bank, engine, tanks, weather, heel and position.
  Click any card to zoom into its history (5 min to 6 h).
- **Data**: every Signal K path the boat reports, live, with sparklines. Use it to check what a new sensor is sending.
- **Notes**: a drawing of the S2 35C (outside profile, deck, below decks) that fills the page. Click a part
  of the boat for its **Documentation**, **Plans** and **Research** folders (`boat/below/engine/Plans/`);
  picking one, and creating it if it's missing, opens it in Neovim beside the drawing.
  *Insert readings* stamps engine hours, battery and position into the file you're editing.
- **Night / red night-vision / day** themes (top-right button). F11 toggles full screen.

With no server it runs a built-in **simulated boat**. Switch to a real server in Settings.

## Neovim in the app

The Notes page has a Neovim pane: a real `nvim --embed` on the boat folder, with your config and
plugins, drawn by the app itself, so it needs no terminal or window manager. It's linked both ways:

- move the cursor in oil and the app shows that part of the boat;
- pick a part of the boat in the app and oil moves to it (only while oil is showing; a file you're
  editing is left alone). Picking a category always opens its folder; the file you were editing stays open.

`Ctrl+;` moves the keyboard between the pane and the app. Drag the gap beside the pane to resize it;
`Ctrl+T` shows or hides it, from anywhere. Neovim closes with the app: if files are unsaved it asks first, in the pane, and Cancel
keeps everything open. (Closing the window again while it's asking stops Neovim; recover from its swap files.)

The link is `nvim/lua/fernedda.lua`, loaded only into that nvim; your config is untouched.

The boat folder is `boat/` in this repo; set `FERNEDDA_BOAT_DIR` to use another.

## Keyboard

Vim-style normal mode everywhere; typing in a text field is insert mode (Esc leaves it).

- `f` — hints: every clickable thing (and every part of the boat) gets a label; type it to click
- `?` — all keys · `H` / `L` — previous / next page (views on Notes) · `Ctrl+;` — switch between Neovim and the app · `Ctrl+T` — show / hide Neovim
- Notes: `h` `j` `k` `l` move to the part of the boat left / below / above / right ·
  `Enter` show / hide its folders, then `d` `p` `r` open Documentation / Plans / Research ·
  `Space` `h` or `-` back / up a folder, out to the whole boat · `1` `2` `3`, `H` `L` or `gT` `gt` views · `z` zoom on / off ·
  `i` insert readings

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
| `src/BoatFolder`    | The boat folder: makes and counts folders, watches for changes (the `BoatFolder` singleton) |
| `src/NvimLink`      | Runs the embedded Neovim and speaks RPC with it (the `Nvim` singleton) |
| `src/NvimView`      | The Neovim pane: draws its screen, sends it keys and mouse input |
| `src/Msgpack`       | The MessagePack encoding that RPC uses |
| `src/KeyRouter`     | Normal / insert mode keyboard (the `Keyboard` singleton) |
| `nvim/lua/fernedda.lua` | The Neovim side of the link (oil cursor → app; reveal / open_folder / insert) |
| `qml/BoatS235C.js`  | The boat drawing and its tappable zones, as data in metres; edit to match your boat |
| `qml/BoatView.qml`  | Renders one view of the boat, hit-tests zones, shows the category menu |
| `qml/`              | UI: `Theme`, `Units` (SI → knots/°C/…), cards, gauges, pages |

To check a layout without a display:
`QT_QPA_PLATFORM=offscreen FERNEDDA_SCREENSHOT=shot.png ./build/fernedda`
(add `FERNEDDA_KEYS="f s f"` to type keys first).
