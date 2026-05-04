import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var settings: AppSettings
    var showsHeader = true

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if showsHeader {
                SectionHeader(title: "Settings", systemImage: "slider.horizontal.3")
            }

            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Hide completed above")
                        Spacer()
                        Text("\(Int(settings.hideCompletedThreshold * 100))%")
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: $settings.hideCompletedThreshold, in: 0.5...1.0, step: 0.01)
                }

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Save interval")
                        Spacer()
                        Text("\(Int(settings.saveInterval))s")
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: $settings.saveInterval, in: 5...60, step: 1)
                }

                Toggle(isOn: Binding(
                    get: { settings.launchAtLogin },
                    set: { settings.setLaunchAtLogin($0) }
                )) {
                    Text("Launch at login")
                }

                if let settingsMessage = settings.settingsMessage {
                    Text(settingsMessage)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .font(.system(size: 12))
            .padding(12)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.primary.opacity(0.06), lineWidth: 1)
            }
        }
        .onAppear {
            settings.refreshLaunchAtLoginStatus()
        }
    }
}
