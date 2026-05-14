import SwiftUI
import AppKit

extension Notification.Name {
    static let openSettings = Notification.Name("openSettings")
    static let openUptimeHistory = Notification.Name("openUptimeHistory")
    static let uptimeDataUpdated = Notification.Name("uptimeDataUpdated")
    static let panelDidClose = Notification.Name("panelDidClose")
}

enum ServiceHealth: String, Codable, Sendable, CaseIterable {
    case operational
    case degradedPerformance
    case partialOutage
    case majorOutage
    case unknown

    var displayName: String {
        switch self {
        case .operational: "Operational"
        case .degradedPerformance: "Degraded"
        case .partialOutage: "Partial Outage"
        case .majorOutage: "Major Outage"
        case .unknown: "Unknown"
        }
    }

    var iconName: String {
        switch self {
        case .operational: "checkmark.circle.fill"
        case .degradedPerformance: "minus.circle.fill"
        case .partialOutage: "exclamationmark.circle.fill"
        case .majorOutage: "xmark.circle.fill"
        case .unknown: "questionmark.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .operational: .green
        case .degradedPerformance: .yellow
        case .partialOutage: .orange
        case .majorOutage: .red
        case .unknown: .secondary
        }
    }

    var nsColor: NSColor {
        switch self {
        case .operational: .systemGreen
        case .degradedPerformance: .systemYellow
        case .partialOutage: .systemOrange
        case .majorOutage: .systemRed
        case .unknown: .secondaryLabelColor
        }
    }

    var severity: Int {
        switch self {
        case .unknown: -1
        case .operational: 0
        case .degradedPerformance: 1
        case .partialOutage: 2
        case .majorOutage: 3
        }
    }
}

struct ServiceInfo: Identifiable, Sendable {
    let id: String
    let name: String
    let health: ServiceHealth
    let components: [ServiceComponent]
    let incidents: [ServiceIncident]
    let lastUpdated: Date
    let statusPageURL: String
    let sortOrder: Int
    let responseTimeMs: Double?
}

struct ServiceComponent: Identifiable, Sendable {
    let id: String
    let name: String
    let status: ServiceHealth
    let description: String?
}

struct ServiceIncident: Identifiable, Sendable {
    let id: String
    let title: String
    let status: String
    let impact: ServiceHealth
    let createdAt: Date
    let updatedAt: Date?
    let updates: [IncidentUpdate]
    let isActive: Bool
}

struct IncidentUpdate: Identifiable, Sendable {
    let id: String
    let body: String
    let status: String
    let createdAt: Date
}

// MARK: - Date Parsing

func parseISO8601Date(_ string: String?) -> Date {
    guard let string, !string.isEmpty else { return Date() }
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let date = formatter.date(from: string) { return date }
    formatter.formatOptions = [.withInternetDateTime]
    if let date = formatter.date(from: string) { return date }
    // Try with timezone offset format (e.g., -07:00)
    formatter.formatOptions = [.withInternetDateTime, .withColonSeparatorInTimeZone]
    if let date = formatter.date(from: string) { return date }
    return Date()
}

// MARK: - String Helpers

extension String {
    var strippingHTML: String {
        replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}

// MARK: - Uptime Log Entry

struct StatusLogEntry: Identifiable {
    let id: Int64
    let timestamp: Date
    let serviceId: String
    let serviceName: String
    let health: Int  // ServiceHealth.severity value
    let responseTimeMs: Double?
    
    var serviceHealth: ServiceHealth {
        switch health {
        case 0: return .operational
        case 1: return .degradedPerformance
        case 2: return .partialOutage
        case 3: return .majorOutage
        default: return .unknown
        }
    }
}
