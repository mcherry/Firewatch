import AppKit
import Combine

@MainActor
final class StatusManager: ObservableObject {
    @Published var services: [ServiceInfo] = []
    @Published var isRefreshing = false
    @Published var lastRefreshDate: Date?

    private var timer: Timer?
    private var providers: [ScriptStatusProvider] = []
    let notificationManager = NotificationManager()
    let uptimeStore = UptimeStore()
    private var previousHealthStates: [String: ServiceHealth] = [:]
    private var lastFetchTime: Date = .distantPast
    private var lastPollTimes: [String: Date] = [:]
    private var isSleeping = false
    private var sleepObserver: NSObjectProtocol?
    private var wakeObserver: NSObjectProtocol?

    var overallHealth: ServiceHealth {
        guard !services.isEmpty else { return .unknown }
        return services
            .map { $0.health }
            .max(by: { $0.severity < $1.severity }) ?? .unknown
    }

    private var refreshInterval: TimeInterval {
        max(UserDefaults.standard.double(forKey: "refreshInterval"), 30)
    }

    /// Returns the currently loaded scripts for display in Settings.
    var loadedScripts: [(name: String, filename: String, interval: TimeInterval?)] {
        providers.map { ($0.serviceName, $0.scriptPath.lastPathComponent, $0.customInterval) }
    }

    init() {
        CheckScriptManager.ensureDefaultScripts()
        loadProviders()
        startTimer()
        observeSleepWake()
    }

    deinit {
        if let sleepObserver { NSWorkspace.shared.notificationCenter.removeObserver(sleepObserver) }
        if let wakeObserver { NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver) }
    }

    private func observeSleepWake() {
        let center = NSWorkspace.shared.notificationCenter

        sleepObserver = center.addObserver(
            forName: NSWorkspace.willSleepNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.isSleeping = true
                self.timer?.invalidate()
                self.timer = nil
            }
        }

        wakeObserver = center.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.isSleeping = false
                self.startTimer()
                await self.refreshAll(force: true)
            }
        }
    }

    /// Scans the checks directory and loads all .js scripts as providers.
    func loadProviders() {
        let dir = CheckScriptManager.checksDirectory
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: nil
        ) else {
            providers = []
            return
        }

        providers = files
            .filter { $0.pathExtension == "js" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .enumerated()
            .map { ScriptStatusProvider(scriptPath: $1, sortOrder: $0) }
    }

    /// Fetches status from all providers (or only due providers on timer ticks).
    func refreshAll(force: Bool = false) async {
        guard !isSleeping else { return }

        let now = Date()
        let elapsed = now.timeIntervalSince(lastFetchTime)

        // Never fetch more often than every 30 seconds unless forced
        if !force && elapsed < 30 && !services.isEmpty {
            return
        }

        isRefreshing = true
        lastFetchTime = now

        // Determine which providers to run
        let dueProviders: [ScriptStatusProvider]
        if force {
            dueProviders = providers
        } else {
            dueProviders = providers.filter { provider in
                let interval = provider.customInterval ?? refreshInterval
                let lastPoll = lastPollTimes[provider.serviceName] ?? .distantPast
                return now.timeIntervalSince(lastPoll) >= interval
            }
        }

        // Keep existing results for providers we're not refreshing
        var resultsByID: [String: ServiceInfo] = [:]
        for s in services { resultsByID[s.id] = s }

        var freshResults: [ServiceInfo] = []

        await withTaskGroup(of: ServiceInfo?.self) { group in
            for provider in dueProviders {
                group.addTask {
                    do {
                        return try await provider.fetchStatus()
                    } catch {
                        print("[\(provider.serviceName)] Error: \(error.localizedDescription)")
                        return ServiceInfo(
                            id: provider.serviceName.lowercased().replacingOccurrences(of: " ", with: "-"),
                            name: provider.serviceName,
                            health: .unknown,
                            components: [],
                            incidents: [],
                            lastUpdated: Date(),
                            statusPageURL: "",
                            sortOrder: provider.sortOrder,
                            responseTimeMs: nil
                        )
                    }
                }
            }

            for await result in group {
                if let info = result {
                    freshResults.append(info)
                }
            }
        }

        // Update poll times for providers that ran
        for provider in dueProviders {
            lastPollTimes[provider.serviceName] = now
        }

        // Merge fresh results into existing
        for result in freshResults {
            resultsByID[result.id] = result
        }

        // Build sorted results from all known providers
        var results: [ServiceInfo] = []
        for provider in providers {
            let id = provider.serviceName.lowercased().replacingOccurrences(of: " ", with: "-")
            if let info = resultsByID[id] {
                results.append(info)
            }
        }
        results.sort { $0.sortOrder < $1.sortOrder }

        let notificationsEnabled = UserDefaults.standard.bool(forKey: "notificationsEnabled")
        if notificationsEnabled {
            for service in freshResults {
                if let previous = previousHealthStates[service.id] {
                    if previous != service.health {
                        NSLog("[Firewatch] Status change detected: \(service.name) \(previous.displayName) → \(service.health.displayName)")
                        await notificationManager.sendStatusChangeNotification(
                            service: service,
                            previousHealth: previous
                        )
                    }
                } else {
                    NSLog("[Firewatch] First seen: \(service.name) = \(service.health.displayName) (no previous state, skipping notification)")
                }
            }
        } else {
            NSLog("[Firewatch] Notifications disabled, skipping change detection")
        }

        for service in freshResults {
            previousHealthStates[service.id] = service.health
        }

        // Log status for uptime history
        if UserDefaults.standard.bool(forKey: "uptimeLoggingEnabled") {
            uptimeStore.logStatus(services: results)
            NotificationCenter.default.post(name: .uptimeDataUpdated, object: nil)
        }

        services = results
        lastRefreshDate = Date()
        isRefreshing = false
    }

    func startTimer() {
        timer?.invalidate()
        // Use the shortest interval across all providers (or global if none custom)
        let minInterval = providers.compactMap { $0.customInterval }.min() ?? refreshInterval
        let effectiveInterval = min(minInterval, refreshInterval)
        let interval = effectiveInterval + Double.random(in: 0...30)
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.refreshAll()
                self?.startTimer()
            }
        }
    }

    /// Manual refresh from the UI — respects the 30-second minimum
    func manualRefresh() {
        Task {
            await refreshAll(force: true)
        }
        startTimer()
    }
}
