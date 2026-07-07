# watt

Monitor power consumption, cost, and core usage.

<img width="1038" height="730" alt="image" src="https://github.com/user-attachments/assets/5081bda4-9e27-4224-aaeb-5c9df7660391" />



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
