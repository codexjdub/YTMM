# YouTubeMusicMenu

A small macOS menu bar app for YouTube Music. Hover the icon to open music.youtube.com in a panel; move the mouse away and it hides while the music keeps playing.

## Features

- **Hover to open:** the panel drops down under the icon. It's resizable and remembers its size.
- **Click to play/pause** once a song is loaded.
- **Now playing in the menu bar:** the song title sits next to the icon, which switches between play and pause.
- **Separate login:** the app keeps its own Google sign-in, apart from Safari and other apps. Right-click → Sign Out clears it.
- **Light:** about 12 MB until the panel is first opened. The page loads only then.

Right-click the icon for Reload, Sign Out and Quit.

## Build

Requires macOS 14 or later and Swift 6 or later (Xcode's Command Line Tools 16 or later are enough).

```sh
./build.sh
open YouTubeMusicMenu.app
```

`build.sh` quits a running copy first, so `open` starts the new build.

To start it at login, add `YouTubeMusicMenu.app` in System Settings → General → Login Items.

## Notes

- The song title and play/pause come from the YouTube Music page itself, so a redesign of that page may break them until the script in `main.swift` is updated.
- On a free account, ads show their own titles in the menu bar while they play.
- Not affiliated with YouTube or Google.
