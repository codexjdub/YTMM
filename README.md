# YTMM: YouTube Music Menu

YouTube Music in your Mac's menu bar. Hover the icon to open music.youtube.com in a panel; move the mouse away and it hides while the music keeps playing.

## Features

- **Hover to open:** the panel drops down under the icon. It's resizable and remembers its size.
- **Click to play/pause** once a song is loaded.
- **Scroll to skip:** scroll down on the icon for the next song, up for the previous one.
- **Pin:** the pin in the panel's top corner keeps it open while you browse or type.
- **Compact player:** the button next to the pin narrows the panel to YouTube Music's own now-playing view, with its Up next list. Press it again to go back.
- **Lyrics:** the Lyrics button in the panel's top corner opens YouTube Music's own lyrics for the current song. While they show, it reads Up next and takes you back.
- **Now playing in the menu bar:** the song title and artist sit next to the icon, which switches between play and pause. Right-click → Show Artist turns the artist off.
- **Separate login:** the app keeps its own Google sign-in, apart from Safari and other apps. Right-click → Sign Out clears it.
- **Light:** about 12 MB until the panel is first opened. The page loads only then.

Right-click the icon for Show Artist, Reload, Sign Out and Quit.

## Install

Runs on macOS 14 or later, on Apple silicon and Intel Macs.

1. Download `YTMM-<version>.zip` from [Releases](https://github.com/codexjdub/YTMM/releases) and unzip it.
2. Move `YTMM.app` to Applications and open it.
3. macOS blocks it the first time, because the app isn't notarized by Apple. Open System Settings → Privacy & Security, scroll down, and click **Open Anyway** next to YTMM. You only need to do this once.

To start it at login, add `YTMM.app` in System Settings → General → Login Items.

## Build

Requires Swift 6 or later (Xcode's Command Line Tools 16 or later are enough).

```sh
./build.sh
open YTMM.app
```

`build.sh` quits a running copy first, so `open` starts the new build. Set `SIGN_IDENTITY` to sign with a certificate from your keychain; otherwise the app is signed ad hoc.

To publish a release, bump `version` in `build.sh`, commit and push, then run `./release.sh`.

## Notes

- The song title, artist and play/pause come from the YouTube Music page itself, so a redesign of that page may break them until the script in `main.swift` is updated.
- On a free account, ads show their own titles in the menu bar while they play.
- Not affiliated with YouTube or Google.

## License

MIT
