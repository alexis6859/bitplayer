# BitPlayer

BitPlayer is a retro-inspired local music player and entertainment hub built with Flutter. Featuring a nostalgic CRT screen aesthetic, customizable color themes, and built-in classic mini-games, this app brings back the vintage portable console experience to modern smartphones.

This application was developed by **Alexandre Silva** as a personal project over the summer holidays to explore Flutter, audio processing, and game logic.

## Features

* **Retro Audio Player:** Plays local audio files with custom queue management and playback controls.
* **Classic Mini-Games:** Play Snake, Tetris, 2048, Racing, Flappy Bird, and Frogger(Crossy Roads) right from the main menu.
* **Custom Themes:** Multiple retro color palettes (Classic Teal, Gameboy, Arcade Red, Cyberpunk).
* **Focus Mode:** A built-in timer to block out distractions while listening to music.
* **Interactive D-Pad:** Fully functional digital directional pad for navigating menus and playing games.

## Known Bugs

As this was a summer learning project, there are a few rough edges. The currently known issues are:

* In the mini-games, the playable screen area should ideally start slightly higher up on the display.

Fixed:

* ~~Clicking the "Mix" (shuffle) button causes the currently playing track to restart.~~ The queue is now reordered in place, so playback continues.
* ~~In Tetris, the game fails to clear the board correctly if more than two full lines are completed at the exact same time.~~
* ~~The DSP Equalizer is experimental.~~ Presets are now applied as real audio filters (mpv `af`), with an adjustable strength (0–200%).
* ~~The audio visualizer is not accurate.~~ It now follows the real audio: mpv measures 12 frequency bands (40 Hz–16 kHz), one per spectrum bar; the wave follows loudness and timbre. Measuring only runs while the player screen is visible.

## Keyboard shortcuts (desktop)

| Key | Action |
| --- | --- |
| Arrow keys | D-Pad (on the Equalizer screen, ◀ ▶ change the effect strength) |
| Enter | OK |
| Space | PLAY (start / pause games) |
| Esc / Backspace | BACK |
| M | MENU |
| S | MIX (shuffle) |

## Running on Linux

```bash
sudo apt install libgtk-3-dev libmpv-dev
flutter run -d linux
```

## Tests

```bash
flutter test                               # unit tests (game logic, playlist, equalizer)
flutter test integration_test -d linux     # end-to-end test driving the real app
```

## Feedback & Improvements

I am completely open to constructive criticism, feedback, and improvements. If you spot a way to fix the known bugs, optimize the code, or have a genuinely good idea for a new feature, feel free to open an issue or submit a pull request!

Feel free to also add your own theme onto `/lib/models/retro_themes.dart`, just like this:
```
const RetroTheme(
    name: 'YOUR_THEME',
    deviceColor: Color(0xHEXCODE),
    screenColor: Color(0xHEXCODE),
    dpadColor: Color(0xHEXCODE),
    okColor: Color(0xHEXCODE),
    menuColor: Color(0xHEXCODE),
    playColor: Color(0xHEXCODE),
    mixColor: Color(0xHEXCODE),
    backColor: Color(0xHEXCODE),
    ledColor: Color(0xHEXCODE),
),
```

## Links & Resources

**Developer Links:**
* [LinkedIn](https://www.linkedin.com/in/alexandresilva4400) - Let's connect!
* [Buy Me a Coffee](https://www.buymeacoffee.com/alexis6859) - If you enjoy the app and want to support my work.

**Built With:**
* [Flutter](https://flutter.dev/) - The UI toolkit used to build the app.
* [Dart](https://dart.dev/) - The programming language behind Flutter.
* [media_kit](https://github.com/media-kit/media-kit) - The robust audio/video library powering the music playback.