# fernedda

Ground control for a sailboat: a live dashboard of boat data from a
[Signal K](https://signalk.org) server, plus notes organised by boat system.
Native Qt 6 / QML, made for a laptop now and a Raspberry Pi screen later.

- **Dashboard**: wind, navigation, depth, house bank, engine, tanks, weather, heel and position.
  Click any card to zoom into its history (5 min to 6 h).
- **Data**: every Signal K path the boat reports, live, with sparklines. Use it to check what a new sensor is sending.
- **Notes**: Markdown notes filed on a drawing of the boat (an S2 35C: outside profile, deck, and below
  decks) or by system (Engine, Rigging…), with tags, pins and search. Tap a part of the boat to see
  and file notes there; double-tap or long-press to drop a named *spot* (your own folder, e.g.
  "raw water strainer") and drag it to move it.
  *Insert readings* stamps engine hours, battery and position into a note.
  Stored as plain `.md` files in `~/.local/share/fernedda/notes/`.
- **Night / red night-vision / day** themes (top-right button). F11 toggles full screen.

With no server it runs a built-in **simulated boat**. Switch to a real server in Settings.

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
| `src/NotesModel`    | Markdown-file notes and boat spots (the `Notes` singleton) |
| `qml/BoatS235C.js`  | The boat drawing and its tappable zones, as data in metres; edit to match your boat |
| `qml/BoatView.qml`  | Renders one view of the boat, hit-tests zones, places and drags spots |
| `qml/`              | UI: `Theme`, `Units` (SI → knots/°C/…), cards, gauges, pages |

To check a layout without a display:
`QT_QPA_PLATFORM=offscreen FERNEDDA_SCREENSHOT=shot.png ./build/fernedda`
