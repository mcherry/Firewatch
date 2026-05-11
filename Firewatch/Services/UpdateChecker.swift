import AppKit
import Combine

@MainActor
final class UpdateChecker: ObservableObject {
    @Published var latestVersion: String?
    @Published var updateAvailable = false
    @Published var isChecking = false
    @Published var lastCheckDate: Date?
    @Published var checkError: String?

    private static let versionURL = URL(string: "https://raw.githubusercontent.com/mcherry/Firewatch/main/VERSION")!
    private static let repoURL = URL(string: "https://github.com/mcherry/Firewatch")!
    private static let checkIntervalKey = "lastUpdateCheckDate"
    private static let checkInterval: TimeInterval = 86400 // 24 hours

    var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }

    init() {
        lastCheckDate = UserDefaults.standard.object(forKey: Self.checkIntervalKey) as? Date
        latestVersion = UserDefaults.standard.string(forKey: "latestKnownVersion")
        if let latestVersion {
            updateAvailable = Self.isNewer(remote: latestVersion, local: currentVersion)
        }
    }

    /// Check if enough time has passed since the last automatic check.
    func checkIfNeeded() {
        guard UserDefaults.standard.bool(forKey: "autoCheckForUpdates") else { return }
        if let last = lastCheckDate, Date().timeIntervalSince(last) < Self.checkInterval {
            return
        }
        Task { await checkForUpdates() }
    }

    func checkForUpdates() async {
        isChecking = true
        checkError = nil

        defer { isChecking = false }

        do {
            let (data, response) = try await URLSession.shared.data(from: Self.versionURL)

            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                checkError = "Server returned an error"
                return
            }

            guard let remoteVersion = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
                  !remoteVersion.isEmpty else {
                checkError = "Invalid version data"
                return
            }

            latestVersion = remoteVersion
            updateAvailable = Self.isNewer(remote: remoteVersion, local: currentVersion)
            lastCheckDate = Date()

            UserDefaults.standard.set(lastCheckDate, forKey: Self.checkIntervalKey)
            UserDefaults.standard.set(remoteVersion, forKey: "latestKnownVersion")
        } catch {
            checkError = error.localizedDescription
        }
    }

    func openReleasePage() {
        NSWorkspace.shared.open(Self.repoURL)
    }

    /// Returns true if `remote` is a newer semver than `local`.
    static func isNewer(remote: String, local: String) -> Bool {
        let remoteParts = remote.split(separator: ".").compactMap { Int($0) }
        let localParts = local.split(separator: ".").compactMap { Int($0) }

        for i in 0..<max(remoteParts.count, localParts.count) {
            let r = i < remoteParts.count ? remoteParts[i] : 0
            let l = i < localParts.count ? localParts[i] : 0
            if r > l { return true }
            if r < l { return false }
        }
        return false
    }
}
