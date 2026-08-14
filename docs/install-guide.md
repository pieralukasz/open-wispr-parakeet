# Installation Guide

## Quick install

```bash
curl -fsSL https://raw.githubusercontent.com/human37/open-wispr/main/scripts/install.sh | bash
```

The installer sets up the Homebrew formula, copies the app bundle to `~/Applications/OpenWispr.app`, requests permissions, loads Parakeet v3, and starts the background service.

## Permissions

OpenWispr needs these macOS permissions:

- **Microphone** for microphone and combined capture modes.
- **Accessibility** to detect the global hotkey and paste text.
- **Screen & System Audio Recording** when `System Audio` or `Microphone + System Audio` is selected.

You can manage them under **System Settings → Privacy & Security**. If OpenWispr is missing from a list, add `~/Applications/OpenWispr.app` with the **+** button. Restart the app after changing Screen & System Audio Recording access if macOS requests it.

## Troubleshooting

### Accessibility setup timed out

Open **System Settings → Privacy & Security → Accessibility**, enable OpenWispr, then restart:

```bash
brew services restart open-wispr
```

### Microphone denied

Enable OpenWispr under **System Settings → Privacy & Security → Microphone**, then restart the service.

### Globe key opens the emoji picker

Set **System Settings → Keyboard → Press 🌐 key to → Do Nothing**, or choose another hotkey.

### Configuration is invalid

OpenWispr reports invalid JSON and uses defaults for that launch. Fix `~/.config/open-wispr/config.json`, then restart the service.

## Language support

Parakeet defaults to English. Choose a language from the menu bar or set it directly:

```bash
open-wispr set-language pl
```

Use `auto` for automatic detection. Run `open-wispr --help` or open the Language menu for the supported language list.

## Build from source

```bash
git clone https://github.com/human37/open-wispr.git
cd open-wispr
swift build --disable-sandbox -c release
scripts/bundle-app.sh .build/release/open-wispr .build/OpenWispr.app dev
open .build/OpenWispr.app
```

## Uninstall

```bash
curl -fsSL https://raw.githubusercontent.com/human37/open-wispr/main/scripts/uninstall.sh | bash
```
