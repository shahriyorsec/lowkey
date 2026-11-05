# Lowkey

A small macOS overlay that shows synced Spotify lyrics on every desktop, with Apple Music-style animation.

- Lyrics come from [LRCLIB](https://lrclib.net). It times whole lines, so word timing is estimated.
- Requires macOS 15 or later and the Spotify desktop app.

## Build and run

```bash
scripts/build.sh --run
```

macOS asks for permission to control Spotify on first launch. Lowkey lives in the menu bar and has no Dock icon.

Hold Option and drag the card to move it. Everything else is in the menu bar under Settings.
