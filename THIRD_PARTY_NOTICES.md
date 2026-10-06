# Third-party software and voices

The iPhone build includes VOICEVOX CORE 0.17.0, VOICEVOX ONNX Runtime 1.23.2, the Open JTalk dictionary, and the official VVM 0.16.0 voice model. Their license files, third-party notices, and model conditions are preserved in the generated app under `voice/licenses`, `voice/NOTICE.txt`, and the embedded frameworks. The settings screen opens these notices and the selected voice credits. Do not remove them from a redistributed build.

Voice credits: VOICEVOX:四国めたん / VOICEVOX:ずんだもん / VOICEVOX:春日部つむぎ / VOICEVOX:雨晴はう.

Software licensing and voice-use terms apply separately. App integration of the VVM does not grant unrestricted use of character images, names, trademarks, or generated speech. The commercial review and remaining voice-rights questions are recorded in [commercial-preparation.md](docs/commercial-preparation.md). No character illustration is included in the app icon.

Official sources:

- https://github.com/VOICEVOX/voicevox_core/releases/tag/0.17.0
- https://github.com/VOICEVOX/onnxruntime-builder/releases/tag/voicevox_onnxruntime-1.23.2
- https://github.com/VOICEVOX/voicevox_vvm/blob/0.16.0/README.md
- https://zunko.jp/con_ongen_kiyaku.html
- https://tsumugi-official.studio.site/rule
- https://amehau.com/rules/amehare-hau-rule

jsdom and Playwright are development-only test dependencies. Their package license notices remain with the development packages; these Node packages are not embedded in the iPhone IPA.
