# Contributing

Thanks for your interest in contributing to open-wispr.

## Getting started

1. Fork and clone the repository.
2. Run the local development script:

   ```bash
   bash scripts/dev.sh
   ```

The script configures the Parakeet language, punctuation mode, recording history, toggle mode, and hotkey. It then builds, bundles, and launches the menu bar app.

## Project structure

```text
Sources/OpenWisprLib/
├── AppDelegate.swift         # App lifecycle and transcription workflow
├── AudioRecorder.swift       # Microphone/system-audio capture and mixing
├── Config.swift              # Config loading and migration
├── ParakeetTranscriber.swift # Native FluidAudio/Parakeet transcription
├── StatusBarController.swift # Menu bar UI
├── RecordingStore.swift      # Recording history and pruning
└── ...
Sources/OpenWispr/
└── main.swift                # CLI entry point
```

## Tests

Run the unit and install smoke tests:

```bash
swift test --disable-sandbox
bash scripts/test-install.sh
```

The unit suite covers configuration, hotkeys, recording lifecycle and storage, text insertion, and punctuation processing. The install smoke test builds the binary, exercises the supported CLI commands, bundles the app, and validates its metadata.

When adding logic, prefer focused unit tests for pure transformations and state changes. Hardware-dependent microphone, system-audio, display, and accessibility behavior should also be tested manually on Apple Silicon.

## Pull requests

1. Create a branch from `main`.
2. Make the change and add applicable tests.
3. Run the test commands above.
4. Test the bundled app locally.
5. Open a pull request.

Keep changes local-first, minimal, and fully on-device.

## License

Contributions are licensed under the MIT License.
