# YTMM: YouTube Music Menu

YouTube Music in your Mac's menu bar. Hover the icon to open music.youtube.com in a panel; move the mouse away and it hides while the music keeps playing.

## Features

- **Hover to open:** the panel drops down under the icon. It's resizable and remembers its size.
- **Click to play/pause** once a song is loaded.
- **Now playing in the menu bar:** the song title sits next to the icon, which switches between play and pause.
- **Separate login:** the app keeps its own Google sign-in, apart from Safari and other apps. Right-click → Sign Out clears it.
- **Light:** about 12 MB until the panel is first opened. The page loads only then.

Right-click the icon for Reload, Sign Out and Quit.

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

- The song title and play/pause come from the YouTube Music page itself, so a redesign of that page may break them until the script in `main.swift` is updated.
- On a free account, ads show their own titles in the menu bar while they play.
- Not affiliated with YouTube or Google.

## License

MIT
