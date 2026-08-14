<p align="center">
  <img src="logo.svg" width="80" alt="open-wispr logo">
</p>

<h1 align="center">open-wispr-parakeet</h1>

<p align="center">
  <strong><a href="https://open-wispr.com">open-wispr.com</a></strong><br>
  Local, private voice dictation for macOS. Hold a key, speak, release — your words appear at the cursor.<br>
  Everything runs on-device. No audio or text ever leaves your machine.
</p>

<p align="center">Powered exclusively by Parakeet TDT v3 through <a href="https://github.com/FluidInference/FluidAudio">FluidAudio</a>.</p>

## Install

This repository is a Parakeet-enabled fork of OpenWispr. Build and install it locally:

```bash
git clone https://github.com/pieralukasz/open-wispr-parakeet.git
cd open-wispr-parakeet

swift build --disable-sandbox -c release
scripts/bundle-app.sh .build/release/open-wispr .build/OpenWispr.app 0.43.0-parakeet

mkdir -p ~/Applications ~/.local/bin
ditto .build/OpenWispr.app ~/Applications/OpenWispr.app
ln -sfn ~/Applications/OpenWispr.app/Contents/MacOS/open-wispr ~/.local/bin/open-wispr

~/.local/bin/open-wispr set-language pl
open ~/Applications/OpenWispr.app
```

Parakeet v3 downloads on first launch and then stays loaded in the menu bar app. Grant Microphone and Accessibility permissions when macOS asks. System-audio capture additionally requires **Screen & System Audio Recording** permission. To launch it automatically, add `~/Applications/OpenWispr.app` in **System Settings → General → Login Items**.

If the upstream Homebrew edition is already running, stop it first with `brew services stop open-wispr` to avoid two copies using the same hotkey.

A waveform icon appears in your menu bar when it's running.

The default hotkey is the **Globe key** (🌐, bottom-left). Hold it, speak, release.

The upstream project remains available at [human37/open-wispr](https://github.com/human37/open-wispr).

## Uninstall

```bash
osascript -e 'tell application "OpenWispr" to quit'
rm -rf ~/Applications/OpenWispr.app
rm -f ~/.local/bin/open-wispr
```

Configuration and downloaded models remain in `~/.config/open-wispr` and `~/Library/Application Support/FluidAudio` so they can be reused.

## Configuration

Edit `~/.config/open-wispr/config.json`:

```json
{
  "hotkey": { "keyCode": 63, "modifiers": [] },
  "language": "en",
  "spokenPunctuation": false,
  "maxRecordings": 0,
  "toggleMode": false,
  "audioCaptureSource": "microphone"
}
```

Then choose **Reload Configuration** from the menu, or restart the app.

To bind multiple hotkeys, use the `hotkeys` array instead:

```json
{
  "hotkeys": [
    { "keyCode": 63, "modifiers": [] },
    { "keyCode": 96, "modifiers": [] }
  ]
}
```

Both `hotkey` (single) and `hotkeys` (array) are supported. If both are present, `hotkeys` takes precedence.

| Option | Default | Values |
|---|---|---|
| **hotkey** | `63` | Globe (`63`), Right Option (`61`), F5 (`96`), or any key code |
| **hotkeys** | — | Array of hotkey objects — bind multiple keys to trigger dictation |
| **modifiers** | `[]` | `"cmd"`, `"ctrl"`, `"shift"`, `"opt"` — combine for chords |
| **language** | `"en"` | `"auto"` for auto-detect, or a language offered by the menu — e.g. `pl`, `en`, `fr`, `de`, `es` |
| **spokenPunctuation** | `false` | Say "comma", "period", etc. to insert punctuation instead of auto-punctuation |
| **maxRecordings** | `0` | Optionally store past recordings locally as `.wav` files for re-transcribing from the tray menu. `0` = nothing stored (default). Set 1-100 to keep that many recent recordings. |
| **toggleMode** | `false` | Press hotkey once to start recording, press again to stop. Default is hold-to-talk. |
| **audioCaptureSource** | `"microphone"` | `"microphone"`, `"systemAudio"`, or `"microphoneAndSystemAudio"`. You can also change this from **Audio Input** in the menu bar. |

### Parakeet v3

Parakeet TDT v3 is the only transcription engine. FluidAudio downloads it on first launch and keeps it loaded while the menu bar app runs. Choose a supported language from the menu or use `auto` for automatic language detection.

If the Globe key opens the emoji picker: **System Settings → Keyboard → "Press 🌐 key to" → "Do Nothing"**

### System audio permission

Switching **Audio Input** to *System Audio* or *Microphone + System Audio* needs **Screen & System Audio Recording** permission, because macOS routes system audio through ScreenCaptureKit. OpenWispr asks for it the moment you pick one of those sources, and the menu bar shows **Grant Screen Recording Permission...** while it is missing.

macOS only shows that prompt once per app. If you declined it, grant it manually in **System Settings → Privacy & Security → Screen & System Audio Recording** and restart OpenWispr.

Locally built bundles are ad-hoc signed, so their signature changes on every rebuild and macOS treats the new build as a different app. After rebuilding, remove the old OpenWispr entry in that settings pane and grant it again.

## Menu bar

Click the waveform icon for status and options. **Recent Recordings** lists your last recordings; click one to re-transcribe and copy the result to the clipboard.

| State | Icon |
|---|---|
| Idle | Waveform outline |
| Recording | Bouncing waveform |
| Transcribing | Wave dots |
| Downloading model | Progress ring |
| Waiting for permission | Lock |

Click the menu bar icon to access **Copy Last Dictation** — recovers your most recent transcription if you dictated without a text field focused.

## Compare

| | open-wispr | VoiceInk | Wispr Flow | Superwhisper | Apple Dictation |
|---|---|---|---|---|---|
| **Price** | **Free** | $39.99 | $15/mo | $8.49/mo | Free |
| **Open source** | MIT | GPLv3 | No | No | No |
| **100% on-device** | Yes | Yes | No | Yes | Partial |
| **Push-to-talk** | Yes | Yes | Yes | Yes | No |
| **AI features** | No | AI assistant | AI rewriting | AI formatting | No |
| **Account required** | No | No | Yes | Yes | Apple ID |

## Privacy

open-wispr is completely local. Audio is recorded to a temp file, transcribed by Parakeet through FluidAudio, and the temp file is deleted. No network requests are made except to download Parakeet on first run. Optionally, you can configure open-wispr to store a number of past recordings locally via the `maxRecordings` setting. Those recordings stay private and on your machine, and we default to not storing anything.

## Roadmap

This fork tracks OpenWispr 0.43.0 and uses a native FluidAudio/Parakeet v3 transcription pipeline with Polish-first setup instructions. Upstream development lives at [human37/open-wispr](https://github.com/human37/open-wispr).

## Build from source

```bash
swift test --disable-sandbox
swift build --disable-sandbox -c release
scripts/bundle-app.sh .build/release/open-wispr .build/OpenWispr.app dev
open .build/OpenWispr.app
```

## Support

open-wispr is free and always will be. If you find it useful, you can [leave a tip](https://buy.stripe.com/4gM5kC2AU0Ssd4l6Hqd7q00).

## License

MIT
