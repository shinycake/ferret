import SwiftUI
import FerretCore

struct OnboardingView: View {
    var model: OnboardingModel
    var onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Setup")
                .font(.title3.weight(.semibold))

            step(
                badge: model.fullDiskBadge,
                title: "Full Disk Access",
                detail: model.fullDiskDetailLine,
                warning: model.externalDaemonWarning
            ) {
                Button("Open Privacy Settings", action: model.openPrivacySettings)
                Button("Skip") { model.skip(.fullDiskAccess) }
            }

            step(badge: model.indexingBadge, title: "Indexing", detail: model.indexingDetail) {
                if case .scanning = model.phase {
                    ProgressView()
                        .controlSize(.small)
                }
                Button("Skip") { model.skip(.indexing) }
            }

            step(badge: model.extensionBadge, title: "Finder extension", detail: model.extensionDetailLine) {
                toolbarPicture
                Button("Enable…", action: model.openExtensionManagement)
                Button("Skip") { model.skip(.finderExtension) }
            }

            step(badge: model.loginBadge, title: "Launch at login", detail: model.loginDetail) {
                Toggle("Launch at login", isOn: Binding(
                    get: { model.login == .on || model.login == .requiresApproval },
                    set: { model.setLaunchAtLogin($0) }
                ))
                .toggleStyle(.switch)
                if model.login == .requiresApproval {
                    Button("Open Login Items Settings", action: model.openLoginItemsSettings)
                }
                Button("Skip") { model.skip(.launchAtLogin) }
            }

            Text(OnboardingModel.hotkeyFooter)
                .font(.callout.weight(.medium))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 4)

            HStack {
                Spacer()
                Button("Done", action: onClose)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .frame(width: 560, height: 460, alignment: .topLeading)
        .background(Color(red: 0.12, green: 0.12, blue: 0.13))
        .foregroundStyle(Color.white)
        .preferredColorScheme(.dark)
    }

    private var toolbarPicture: some View {
        HStack(spacing: 8) {
            Image(systemName: "macwindow")
            Image(systemName: "magnifyingglass")
            Text("Finder toolbar")
                .font(.caption)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.white.opacity(0.35), lineWidth: 1)
        )
    }

    private func step<Actions: View>(
        badge: OnboardingModel.Badge,
        title: String,
        detail: String,
        warning: String? = nil,
        @ViewBuilder actions: () -> Actions
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(badge == .ok ? "✓" : "⚠︎")
                    .font(.headline)
                Text(title)
                    .font(.headline)
            }
            Text(detail)
                .font(.caption)
                .foregroundStyle(Color.white.opacity(0.78))
                .fixedSize(horizontal: false, vertical: true)
            if let warning {
                Text(warning)
                    .font(.caption)
                    .foregroundStyle(Color.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 8) {
                actions()
            }
            .controlSize(.small)
        }
    }
}

private extension OnboardingModel {
    var fullDiskDetailLine: String {
        skipped.contains(.fullDiskAccess) ? "Skipped. \(Self.fullDiskDetail)" : Self.fullDiskDetail
    }

    var extensionDetailLine: String {
        skipped.contains(.finderExtension) ? "Skipped. \(Self.extensionDetail)" : Self.extensionDetail
    }

    var loginDetail: String {
        if skipped.contains(.launchAtLogin) { return "Skipped." }
        switch login {
        case .off:
            return "Off. Ferret can still be opened from Finder."
        case .on:
            return "On. Ferret opens when you log in."
        case .requiresApproval:
            return "macOS needs approval in Login Items."
        }
    }
}
