import SwiftUI

struct AboutView: View {
    var body: some View {
        ZStack {
            VisualEffectView(material: .popover, blendingMode: .behindWindow)

            VStack(spacing: 16) {
                VStack(spacing: 6) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [Color.black, Color.black.opacity(0.85)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 52, height: 52)

                        Image(systemName: "bolt.fill")
                            .font(.system(size: 26, weight: .semibold))
                            .foregroundStyle(.yellow.gradient)
                    }

                    Text("Watt")
                        .font(.system(size: 16, weight: .semibold))

                    Text("Real-time power monitoring for macOS")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }

                VStack(spacing: 2) {
                    HStack(spacing: 4) {
                        Text("Version \(getAppVersion())")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.secondary)
                        Text(getGitHash().uppercased())
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundStyle(.tertiary)
                    }

                    Text("© 2026 Zimeng Xiong")
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                }

                Link(destination: URL(string: "https://github.com/zimengxiong/watt")!) {
                    HStack(spacing: 5) {
                        GitHubIcon()
                            .frame(width: 12, height: 12)
                        Text("View on GitHub")
                            .font(.system(size: 10, weight: .medium))
                    }
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.primary.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                }
                .buttonStyle(.plain)
            }
            .padding(.vertical, 20)
            .padding(.horizontal, 24)
        }
        .frame(width: 240)
    }

    private func getAppVersion() -> String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }

    private func getGitHash() -> String {
        guard let url = Bundle.main.url(forResource: "GitHash", withExtension: "txt"),
              let hash = try? String(contentsOf: url, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines) else {
            return "dev"
        }
        return hash
    }
}

struct GitHubIcon: View {
    var body: some View {
        Image("GitHubIcon")
            .resizable()
            .aspectRatio(contentMode: .fit)
    }
}

#Preview {
    AboutView()
}
