# watt

Monitor power consumption, cost, and core usage.

<img width="731" height="731" alt="image" src="https://github.com/user-attachments/assets/5fac708f-2a22-4aad-a0ce-e3e183017b52" />

## Installation

### Homebrew

```bash
brew install --cask zimengxiong/watt/watt
xattr -cr /Applications/Watt.app
```

> **Note:** The app isn't notarized with Apple, so macOS Gatekeeper will block it on first launch. Homebrew no longer allows the `--no-quarantine` flag, so run `xattr -cr /Applications/Watt.app` after installing to clear the quarantine attribute.

### Build from Source

Requires macOS 13 or later, [XcodeGen](https://github.com/yonaskolb/XcodeGen) and the Xcode Command Line Tools. CPU/GPU/ANE metrics require Apple Silicon.

```bash
git clone https://github.com/zimengxiong/watt.git
cd watt
make install
xattr -cr /Applications/Watt.app
```

`make install` generates the Xcode project with XcodeGen, builds the Release configuration and copies `Watt.app` to `/Applications`. It publishes nothing. Run `make help` for all available targets.

#### Signing

The `Makefile` defaults to the maintainer's Apple Development certificate, which exists in exactly one keychain. To build somewhere else, override it — no editing of the Makefile, and no Apple account required:

```bash
make build SIGN_IDENTITY=          # ad-hoc signing (this is what CI runs)
make build SIGN_IDENTITY="Apple Development: you@example.com (TEAMID)" TEAM_ID=TEAMID
```

#### Releasing

`make release` is the publishing pipeline: it pushes a branch, tags it, creates a GitHub release and updates the Homebrew tap. It names its target explicitly, prints what it will do, waits for a typed confirmation, and refuses a version that is already tagged:

```bash
make release REMOTE=origin
```

Building a release binary without publishing anything is `make build-release`.

### CPU/GPU/ANE Metrics

On first launch, Watt prompts to install a system service that runs Apple's `powermetrics` tool. This provides accurate hardware metrics that aren't available through standard APIs. The service:

- Runs as a LaunchDaemon with root privileges
- Prompts for an administrator password on install and on uninstall, because it writes a plist into `/Library/LaunchDaemons`
- Reads CPU, GPU, and ANE idle ratios and energy consumption
- Updates every second
- Can be uninstalled from Settings

## Settings

<img width="710" height="457" alt="image" src="https://github.com/user-attachments/assets/cb4c9e86-1d7a-4689-81f1-5d9f8b2c35ee" />


## Privacy

Watt:

- Stores settings and statistics locally in UserDefaults
- Does not collect or transmit any personal data
- IP-based location lookup (optional) uses ipapi.co for electricity rate detection only

## Acknowledgments

CPU, GPU, and ANE monitoring is based on [asitop](https://github.com/tlkh/asitop) by Timothy Liu.

## License

MIT License
