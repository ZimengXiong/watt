# Watt

A lightweight macOS menu bar app for real-time power monitoring on Apple Silicon Macs.

<p align="center">
  <img src="Screenshots/main.png" alt="Watt" height="700">
</p>

## Features

- **Real-time Power Display**: Shows current system power consumption in the menu bar
- **CPU/GPU/ANE Metrics**: E-CPU, P-CPU, GPU, and Neural Engine usage with htop-style bar graphs
- **Battery Information**: Cycle count, temperature, health, voltage, and capacity
- **Power Flow Visualization**: See power flowing from wall/battery to system
- **Energy Tracking**: Today's and lifetime energy consumption with cost estimates
- **Electricity Cost**: Auto-detect rates by location or set manually by ZIP code
- **Launch at Login**: Optional automatic startup

## Requirements

- macOS 13.0 (Ventura) or later
- Apple Silicon Mac (M1/M2/M3/M4)

## Installation

### Homebrew

```bash
brew install --cask --no-quarantine zimengxiong/watt/watt
```

### Download

Download the latest release from [GitHub Releases](https://github.com/zimengxiong/watt/releases).

### Build from Source

Requires [XcodeGen](https://github.com/yonaskolb/XcodeGen) and Xcode Command Line Tools.

```bash
git clone https://github.com/zimengxiong/watt.git
cd watt
make build    # Build debug version
make open     # Build and open the app
make install  # Build release and install to /Applications
```

Run `make help` for all available targets.

## How It Works

Watt reads power data from multiple macOS system sources:

| Source | Data |
|--------|------|
| **SMC** | Real-time power readings via SMC keys (`PSTR`, `PDTR`, `SBAP`) |
| **IOKit** | Battery properties from `AppleSmartBattery` (voltage, amperage, capacity, health) |
| **IOPowerSources** | Charger details and power adapter information |
| **powermetrics** | CPU/GPU/ANE usage and power via LaunchDaemon (requires one-time admin setup) |

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

- **Electricity Cost**: Set your $/kWh rate manually or auto-detect by ZIP code
- **Launch at Login**: Start Watt automatically when you log in
- **Reset Statistics**: Clear energy tracking data
- **Uninstall Service**: Remove the powermetrics daemon

## Privacy

Watt:
- Stores settings and statistics locally in UserDefaults
- Does not collect or transmit any personal data
- IP-based location lookup (optional) uses ipapi.co for electricity rate detection only

## Acknowledgments

CPU, GPU, and ANE monitoring is based on [asitop](https://github.com/tlkh/asitop) by Timothy Liu.

## License

MIT License - see [LICENSE](LICENSE) for details.
