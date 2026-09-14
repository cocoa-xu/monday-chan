# Monday-chan

A small macOS desktop performance: Kanade peeks up from the bottom of your screen, jumps around with a Monday placard, and runs away.

[Watch the Demo](assets/demo.mp4)

*This demo video is silent; audio has been removed.*

- Native Metal rendering, synchronized expressions, and transparent mouse passthrough.
- Preview on demand or schedule one Sunday-night surprise on your selected monitors.
- English and Japanese, using [FlowingDayUI](https://github.com/cocoa-xu/flowing-day-ui).

Requires macOS 14 or later on an Apple Silicon or Intel Mac with Metal 3. No game assets or performance audio are included.

## Set up

1. Install and open [hololive Dreams](https://hololive.hololivepro.com/en/news/20260723-01-401/), sign in, and let the game finish downloading its resource data. Export the downloaded resource directory from your phone using a method you choose, then select that folder in Monday-chan’s first-run window.
2. Save the video from [YouTube Japan’s original post](https://x.com/YouTubeJapan/status/2091495920311414921), then drop the downloaded MP4/MOV into the window or choose it from disk.
3. Preview the audio and import. Choose your monitors in Preferences, then press Play.

Only the required character resources are imported. Audio is extracted locally into lossless ALAC. Your source files remain unchanged; nothing is uploaded. Right-click Kanade to dismiss her.

## Build

With Xcode 26 or later, its Metal Toolchain component, and Swift 6.1 or later:

```sh
scripts/build.sh
open dist/MondayChan.app
```

Asset import is implemented in Swift, with system Metal texture decoding and AVFoundation audio extraction. Run `swift test -c release` for tests. For local development, exclude `/data/` in `.git/info/exclude` and use `scripts/run.sh` with your imported data.

## Disclaimer

This repository does not include Kanade’s model, textures, animations, voice, or any other game, video, or audio resources, and it never will. Users must import the required files themselves from copies they are authorized to access.

Otonose Kanade and the original character models, textures, animations, and associated resources belong to COVER Corporation. This is an unofficial project and grants no permission to use or redistribute those materials. Use them only in accordance with the applicable terms and [COVER’s guidelines](https://hololivepro.com/en/terms/). Users are solely responsible for their use and any redistribution of COVER’s data, including resulting claims or legal disputes. To the extent permitted by applicable law, the maintainers accept no liability for those activities.

このリポジトリには、音乃瀬奏のモデル、テクスチャ、アニメーション、音声、その他のゲーム・映像・音声素材は含まれておらず、今後も配布しません。必要なファイルは、利用者自身が正当にアクセスできるコピーからインポートしてください。

音乃瀬奏および元のキャラクターモデル、テクスチャ、アニメーション、関連素材の権利は、カバー株式会社に帰属します。本プロジェクトは非公式であり、これらの素材の利用または再配布を許諾するものではありません。適用される規約および[カバー株式会社の二次創作ガイドライン](https://hololivepro.com/terms/)に従って利用してください。カバー株式会社のデータの利用および再配布、それによって生じる請求や法的紛争については、利用者自身が責任を負うものとします。適用法令で認められる範囲において、メンテナーはこれらに関する責任を負いません。
