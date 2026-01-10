# watt

Monitor power consumption, cost, and core usage.

<p align="left">
  <img src="Screenshots/main.png" alt="Watt" height="700">
</p>

## Installation

### Homebrew

```bash
brew install --cask --no-quarantine zimengxiong/watt/watt
```

> **Note:** The `--no-quarantine` flag is required because the app is not notarized with Apple. Without this flag, macOS Gatekeeper will block the app from running.

### Build from Source

Requires [XcodeGen](https://github.com/yonaskolb/XcodeGen) and Xcode Command Line Tools.

```bash
git clone https://github.com/zimengxiong/watt.git
cd watt
make install
```

Run `make help` for all available targets.

### CPU/GPU/ANE Metrics

On first launch, Watt prompts to install a system service that runs Apple's `powermetrics` tool. This provides accurate hardware metrics that aren't available through standard APIs. The service:

- Runs as a LaunchDaemon with root privileges
- Reads CPU, GPU, and ANE idle ratios and energy consumption
- Updates every 500ms
- Can be uninstalled from Settings

## Settings

<p align="center">
  <img src="Screenshots/extra.png" alt="Settings" height="600">
</p>

## Privacy

Watt:

- Stores settings and statistics locally in UserDefaults
- Does not collect or transmit any personal data
- IP-based location lookup (optional) uses ipapi.co for electricity rate detection only

## Acknowledgments

CPU, GPU, and ANE monitoring is based on [asitop](https://github.com/tlkh/asitop) by Timothy Liu.

## License

MIT License
