import SwiftUI
import FerretCore

struct SettingsView: View {
    @Bindable var store: SettingsStore
    var about: AboutSnapshot
    var onAddExcluded: () -> Void
    var onReindex: () -> Void
    var onOpenLogs: () -> Void
    var onOpenLicenses: () -> Void
    var onLaunchAtLogin: (Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Settings")
                .font(.title3.weight(.semibold))

            labeled("Search hotkey") {
                Text("⌥Space")
                    .font(.body.monospaced())
            }

            labeled("Result limit") {
                Stepper(value: $store.resultLimit, in: 10...500) {
                    Text("\(store.resultLimit)")
                        .monospacedDigit()
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Excluded paths")
                    .font(.headline)
                Text(SettingsStore.exclusionCopy)
                    .font(.caption)
                    .foregroundStyle(Color.white.opacity(0.75))
                if store.excludedPaths.isEmpty {
                    Text("None")
                        .font(.caption)
                        .foregroundStyle(Color.white.opacity(0.55))
                } else {
                    ForEach(Array(store.excludedPaths.enumerated()), id: \.offset) { _, path in
                        Text(path)
                            .font(.caption.monospaced())
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                HStack {
                    Button("+", action: onAddExcluded)
                    Button("−") {
                        store.removeExcluded(at: store.excludedPaths.count - 1)
                    }
                    .disabled(store.excludedPaths.isEmpty)
                }
                .controlSize(.small)
            }

            Toggle("Show hidden files", isOn: $store.showHiddenFiles)
                .toggleStyle(.switch)

            Toggle("Launch at login", isOn: Binding(
                get: { store.launchAtLogin },
                set: { newValue in
                    store.launchAtLogin = newValue
                    onLaunchAtLogin(newValue)
                }
            ))
            .toggleStyle(.switch)

            Button("Reindex…", action: onReindex)

            VStack(alignment: .leading, spacing: 3) {
                Text("About")
                    .font(.headline)
                Text("Ferret \(about.marketingVersion)")
                Text("Git \(about.gitSHA)")
                    .font(.caption.monospaced())
                Text("fsearch \(about.fsearchPin)")
                    .font(.caption.monospaced())
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text("Daemon: \(about.daemonSummary)")
                Text(about.fullDiskAccess ? "Full Disk Access: ✓" : "Full Disk Access: ✗")
                HStack {
                    Button("Open Logs Folder", action: onOpenLogs)
                    Button("Third-Party Licenses", action: onOpenLicenses)
                }
                .controlSize(.small)
            }
            .font(.caption)
        }
        .padding(16)
        .frame(width: 560, height: 640, alignment: .topLeading)
        .background(Color(red: 0.12, green: 0.12, blue: 0.13))
        .foregroundStyle(Color.white)
        .preferredColorScheme(.dark)
    }

    private func labeled<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        HStack {
            Text(title)
                .font(.headline)
            Spacer()
            content()
        }
    }
}
