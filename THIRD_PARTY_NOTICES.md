# Third-party software and voices

The iPhone build includes VOICEVOX CORE 0.17.0, VOICEVOX ONNX Runtime 1.23.2, the Open JTalk dictionary, and the official VVM 0.16.4 Nemo n0.vvm voice model. Their license files, third-party notices, and model conditions are preserved in the generated app under `voice/licenses`, `voice/NOTICE.txt`, and the embedded frameworks. The settings screen opens these notices and the selected voice credits. Do not remove them from a redistributed build.

Voice credit: **VOICEVOX Nemo**. All nine neutral voices use this common credit. Character models used in 2.7 and earlier are not embedded in 2.8.

Software licensing and voice-use terms apply separately. App integration of the VVM does not grant unrestricted use of character images, names, trademarks, or generated speech. The commercial review and remaining voice-rights questions are recorded in [commercial-preparation.md](docs/commercial-preparation.md). No character illustration is included in the app icon.

Official sources:

- https://github.com/VOICEVOX/voicevox_core/releases/tag/0.17.0
- https://github.com/VOICEVOX/onnxruntime-builder/releases/tag/voicevox_onnxruntime-1.23.2
- https://github.com/VOICEVOX/voicevox_vvm/blob/0.16.4/README.md
- https://voicevox.hiroshiba.jp/nemo/term/
- Offline Nemo conditions: [VOICEVOX_Nemo_TERMS.txt](licenses/VOICEVOX_Nemo_TERMS.txt)

jsdom and Playwright are development-only test dependencies. Their package license notices remain with the development packages; these Node packages are not embedded in the iPhone IPA.
