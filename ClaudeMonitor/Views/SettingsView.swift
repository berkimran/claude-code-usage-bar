import SwiftUI
import ServiceManagement

struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @AppStorage("showCostInMenuBar") private var showCost = true
    @AppStorage("refreshInterval") private var refreshInterval = 60.0
    @AppStorage("launchAtLogin") private var launchAtLogin = false
    @AppStorage("greenMax") private var greenMax = 60.0
    @AppStorage("yellowMax") private var yellowMax = 80.0
    @AppStorage("orangeMax") private var orangeMax = 90.0

    var body: some View {
        Form {
            Section("Display") {
                Toggle("Show cost in menu bar", isOn: $showCost)

                HStack {
                    Text("Refresh interval:")
                    Picker("", selection: $refreshInterval) {
                        Text("30s").tag(30.0)
                        Text("1m").tag(60.0)
                        Text("2m").tag(120.0)
                        Text("5m").tag(300.0)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 220)
                }
            }

            Section("Color Thresholds") {
                ThresholdRow(label: "Green -> Yellow", value: $greenMax, range: 30...90)
                ThresholdRow(label: "Yellow -> Orange", value: $yellowMax, range: 50...95)
                ThresholdRow(label: "Orange -> Red", value: $orangeMax, range: 60...99)
            }

            Section("System") {
                Toggle("Launch at login", isOn: $launchAtLogin)
            }

            Section {
                HStack {
                    Spacer()
                    Text("ClaudeMonitor v1.0")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 400, height: 320)
        .onChange(of: showCost) { _ in
            appState.showCostInMenuBar = showCost
        }
        .onChange(of: refreshInterval) { _ in
            appState.refreshInterval = refreshInterval
        }
        .onChange(of: launchAtLogin) { _ in
            setLaunchAtLogin(launchAtLogin)
        }
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            // May fail without proper entitlements
        }
    }
}

struct ThresholdRow: View {
    let label: String
    @Binding var value: Double
    let range: ClosedRange<Double>

    var body: some View {
        HStack {
            Text(label)
                .frame(width: 140, alignment: .leading)
            Slider(value: $value, in: range, step: 5)
            Text("\(Int(value))%")
                .frame(width: 40, alignment: .trailing)
                .monospacedDigit()
        }
    }
}
