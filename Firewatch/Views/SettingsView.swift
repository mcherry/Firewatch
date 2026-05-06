import SwiftUI
import KeyboardShortcuts
import UserNotifications

struct SettingsView: View {
    @EnvironmentObject var statusManager: StatusManager

    var body: some View {
        TabView {
            GeneralSettingsView(statusManager: statusManager)
                .tabItem {
                    Label("General", systemImage: "gear")
                }
            ScriptsSettingsView(statusManager: statusManager)
                .tabItem {
                    Label("Scripts", systemImage: "scroll")
                }
        }
        .frame(width: 420, height: 340)
    }
}

// MARK: - Scripts Tab

struct ScriptsSettingsView: View {
    @ObservedObject var statusManager: StatusManager
    @State private var scripts: [(name: String, filename: String)] = []

    var body: some View {
        Form {
            Section {
                if scripts.isEmpty {
                    Text("No scripts loaded")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 8)
                } else {
                    ForEach(scripts, id: \.filename) { script in
                        HStack {
                            Text(script.name)
                            Spacer()
                            Text(script.filename)
                                .foregroundStyle(.secondary)
                                .font(.caption)
                        }
                    }
                }
            }

            Section {
                HStack {
                    Button("Open Scripts Folder") {
                        NSWorkspace.shared.open(CheckScriptManager.checksDirectory)
                    }
                    Spacer()
                    Button("Reload Scripts") {
                        statusManager.loadProviders()
                        loadScripts()
                        statusManager.manualRefresh()
                    }
                }
            }

            Section {
                Text("Add .js files to the scripts folder to create custom status checks. See TEMPLATE.js.example for reference.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
        .onAppear { loadScripts() }
    }

    private func loadScripts() {
        scripts = statusManager.loadedScripts
    }
}

struct GeneralSettingsView: View {
    @ObservedObject var statusManager: StatusManager
    @AppStorage("refreshInterval") private var refreshInterval: Double = 120
    @State private var notificationsEnabled = UserDefaults.standard.bool(forKey: "notificationsEnabled")
    @State private var notificationAuthStatus: UNAuthorizationStatus = .notDetermined

    var body: some View {
        Form {
            Section {
                Picker("Refresh Interval", selection: $refreshInterval) {
                    Text("30 seconds").tag(30.0)
                    Text("1 minute").tag(60.0)
                    Text("2 minutes").tag(120.0)
                    Text("5 minutes").tag(300.0)
                    Text("10 minutes").tag(600.0)
                }
                .onChange(of: refreshInterval) {
                    statusManager.startTimer()
                }
            }

            Section {
                KeyboardShortcuts.Recorder("Toggle Status Panel:", name: .toggleStatusPanel)
            }

            Section {
                Toggle("Enable Notifications", isOn: $notificationsEnabled)
                    .toggleStyle(.checkbox)
                    .onChange(of: notificationsEnabled) {
                        UserDefaults.standard.set(notificationsEnabled, forKey: "notificationsEnabled")
                        if notificationsEnabled {
                            Task {
                                await requestNotificationPermission()
                            }
                        }
                    }

                if notificationsEnabled && notificationAuthStatus == .denied {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.yellow)
                            .font(.caption)
                        Text("Notifications are blocked in System Settings.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Button("Open Settings") {
                            NSWorkspace.shared.open(
                                URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings")!
                            )
                        }
                        .font(.caption)
                    }
                } else {
                    Text("Get notified when a service status changes, including recovery to operational.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
        .task {
            await refreshAuthStatus()
        }
    }

    private func requestNotificationPermission() async {
        let granted = await statusManager.notificationManager.requestPermission()
        if !granted {
            await refreshAuthStatus()
        } else {
            notificationAuthStatus = .authorized
        }
    }

    private func refreshAuthStatus() async {
        notificationAuthStatus = await statusManager.notificationManager.checkAuthorizationStatus()
        // If the OS denied permission, reflect that in the toggle
        if notificationAuthStatus == .denied && notificationsEnabled {
            // Keep toggle on but show the warning
        }
    }
}
