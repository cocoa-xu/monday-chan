# Monday-chan

A small macOS desktop performance: Kanade peeks up from the bottom of your screen, jumps around with a Monday placard, and runs away.

- Native Metal rendering, synchronized expressions, and transparent mouse passthrough.
- Preview on demand or schedule one Sunday-night surprise on your selected monitors.
- English and Japanese, using [FlowingDayUI](https://github.com/cocoa-xu/flowing-day-ui).

Requires macOS 14 or later on Apple silicon. No game assets or performance audio are included.

## Set up

1. Choose your locally exported game files or game directory in the first-run window.
2. Save the video from [YouTube Japan’s original post](https://x.com/YouTubeJapan/status/2091495920311414921), then drop the downloaded MP4/MOV into the window or choose it from disk. The clip is approximately 11 seconds long.
3. Preview the audio and import. Choose your monitors in Preferences, then press Play.

Only the required character resources are imported. Audio is extracted locally into lossless ALAC. Your source files remain unchanged; nothing is uploaded. Right-click Kanade to dismiss her.

## Build

With Xcode 26 or later, its Metal Toolchain component, and Swift 6.1 or later:

```sh
scripts/build.sh
open dist/MondayChan.app
```

Asset import is implemented in Swift, with system Metal texture decoding and AVFoundation audio extraction. Run `swift test -c release` for tests. For local development, exclude `/data/` in `.git/info/exclude` and use `scripts/run.sh` with your imported data.

## Resource ownership and responsibility

Kanade and the original character models, textures, animations, and associated game resources belong to COVER Corporation (Japan), not this project. All rights remain with their respective owners. This is an unofficial project and grants no permission to use or redistribute those materials. Consult the applicable terms and [COVER’s guidelines](https://hololivepro.com/en/terms/).

Use only resources you are entitled to use. You are responsible for your use and any redistribution of COVER’s data, including resulting claims or legal disputes. To the extent permitted by applicable law, the maintainers accept no liability for those activities. Consider your responsibilities carefully before use.
