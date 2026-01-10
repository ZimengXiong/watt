# Watt

A lightweight macOS menu bar app that displays real-time power consumption in watts. Monitor your MacBook's power draw, battery health, and energy costs at a glance.

## Features

- **Real-time Power Monitoring**: Displays current system power draw in the menu bar
- **Battery Information**: View battery health, cycle count, temperature, and charge status
- **Power Flow Visualization**: See how power flows between wall, battery, and system
- **Charger Detection**: Identifies charger type, wattage, and Apple adapter status
- **Energy Tracking**: Track daily and lifetime energy consumption
- **Cost Estimation**: Calculate electricity costs based on your local rates
- **ZIP Code Rate Lookup**: Automatically fetch electricity rates by US ZIP code

## Requirements

- macOS 13.0 (Ventura) or later
- Apple Silicon or Intel Mac with battery

## Installation

### Building from Source

1. Clone the repository:
   ```bash
   git clone https://github.com/zimengxiong/watt.git
   cd watt
   ```

2. Open the project in Xcode:
   ```bash
   open Watt.xcodeproj
   ```

3. Build and run (⌘R)

### Pre-built Binary

Download the latest release from the [Releases](https://github.com/zimengxiong/watt/releases) page.

## How It Works

Watt reads power data from multiple macOS system sources:

- **SMC (System Management Controller)**: Real-time power readings via SMC keys (`PSTR`, `PDTR`, `SBAP`)
- **IOKit**: Battery properties from `AppleSmartBattery` including voltage, amperage, capacity, and health
- **IOPowerSources**: Charger details and power adapter information

The app runs as a menu bar utility with minimal resource usage, updating power readings every 500ms.

## Architecture

```
Watt/
├── Sources/
│   ├── App/
│   │   └── WattApp.swift          # App entry point and menu bar setup
│   ├── Models/
│   │   ├── BatteryInfo.swift      # Battery data model
│   │   ├── ChargerInfo.swift      # Charger data model
│   │   ├── PortInfo.swift         # USB-C port data model
│   │   └── PowerTelemetry.swift   # Power telemetry data model
│   ├── Services/
│   │   └── PowerMonitorService.swift  # Core power monitoring logic
│   └── Views/
│       ├── ContentView.swift      # Main popover UI
│       └── VisualEffectView.swift # Native blur effect
└── Resources/
    ├── Info.plist
    └── Watt.entitlements
```

## Privacy

Watt runs entirely on-device and does not collect or transmit any personal data. The only network request made is an optional IP geolocation lookup for electricity rate estimation, which can be disabled in settings.

## License

MIT License. See [LICENSE](LICENSE) for details.

## Contributing

Contributions are welcome! Please feel free to submit issues and pull requests.

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## Acknowledgments

- Uses IOKit for hardware access
- SMC reading inspired by various open-source macOS utilities
