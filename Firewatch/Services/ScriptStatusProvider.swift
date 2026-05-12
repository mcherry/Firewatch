import Foundation

struct ScriptStatusProvider: StatusProvider {
    let scriptPath: URL
    let serviceName: String
    let sortOrder: Int

    private let scriptContent: String
    private let pageURL: String

    init(scriptPath: URL, sortOrder: Int) {
        self.scriptPath = scriptPath
        self.sortOrder = sortOrder
        self.scriptContent = (try? String(contentsOf: scriptPath, encoding: .utf8)) ?? ""
        self.serviceName = Self.parseMetadata("FIREWATCH_NAME", from: scriptContent)
            ?? scriptPath.deletingPathExtension().lastPathComponent
        self.pageURL = Self.parseMetadata("FIREWATCH_URL", from: scriptContent) ?? ""
    }

    func fetchStatus() async throws -> ServiceInfo {
        // Re-read script on each execution to pick up live edits
        let content = (try? String(contentsOf: scriptPath, encoding: .utf8)) ?? scriptContent

        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                let result = ScriptRunner.run(script: content)
                continuation.resume(returning: self.mapResult(result))
            }
        }
    }

    // MARK: - Metadata Parsing

    static func parseMetadata(_ key: String, from text: String) -> String? {
        let escaped = NSRegularExpression.escapedPattern(for: key)
        let pattern = "//\\s*\(escaped)\\s*=\\s*\"([^\"]+)\""
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[range])
    }

    // MARK: - Result Mapping

    private func mapResult(_ result: [String: Any]?) -> ServiceInfo {
        guard let result else { return makeUnknownInfo() }

        let health = mapStatus(result["status"] as? String)

        let components: [ServiceComponent] = (result["components"] as? [[String: Any]] ?? []).map { comp in
            ServiceComponent(
                id: comp["name"] as? String ?? UUID().uuidString,
                name: comp["name"] as? String ?? "Unknown",
                status: mapStatus(comp["status"] as? String),
                description: comp["description"] as? String
            )
        }

        let incidents: [ServiceIncident] = (result["incidents"] as? [[String: Any]] ?? []).map { inc in
            let updates: [IncidentUpdate] = (inc["updates"] as? [[String: Any]] ?? []).map { u in
                IncidentUpdate(
                    id: UUID().uuidString,
                    body: u["body"] as? String ?? "",
                    status: u["status"] as? String ?? "",
                    createdAt: parseISO8601Date(u["created_at"] as? String)
                )
            }

            return ServiceIncident(
                id: inc["title"] as? String ?? UUID().uuidString,
                title: inc["title"] as? String ?? "Unknown",
                status: inc["status"] as? String ?? "Unknown",
                impact: mapStatus(inc["impact"] as? String),
                createdAt: parseISO8601Date(inc["created_at"] as? String),
                updatedAt: parseISO8601Date(inc["updated_at"] as? String),
                updates: updates,
                isActive: inc["is_active"] as? Bool ?? false
            )
        }

        // If the overall status is operational but there are active incidents,
        // elevate to at least degraded (use the worst incident impact if higher)
        var effectiveHealth = health
        let activeIncidents = incidents.filter { $0.isActive }
        if effectiveHealth == .operational && !activeIncidents.isEmpty {
            let worstIncidentSeverity = activeIncidents
                .map { $0.impact.severity }
                .max() ?? 0
            let minimumSeverity = max(worstIncidentSeverity, ServiceHealth.degradedPerformance.severity)
            effectiveHealth = ServiceHealth.allCases.first { $0.severity == minimumSeverity } ?? .degradedPerformance
        }

        return ServiceInfo(
            id: serviceName.lowercased().replacingOccurrences(of: " ", with: "-"),
            name: serviceName,
            health: effectiveHealth,
            components: components,
            incidents: incidents,
            lastUpdated: Date(),
            statusPageURL: pageURL,
            sortOrder: sortOrder
        )
    }

    private func mapStatus(_ status: String?) -> ServiceHealth {
        switch status {
        case "operational": .operational
        case "degraded": .degradedPerformance
        case "partial_outage": .partialOutage
        case "major_outage": .majorOutage
        default: .unknown
        }
    }

    private func makeUnknownInfo() -> ServiceInfo {
        ServiceInfo(
            id: serviceName.lowercased().replacingOccurrences(of: " ", with: "-"),
            name: serviceName,
            health: .unknown,
            components: [],
            incidents: [],
            lastUpdated: Date(),
            statusPageURL: pageURL,
            sortOrder: sortOrder
        )
    }
}
