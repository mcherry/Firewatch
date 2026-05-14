import SwiftUI

struct ServiceRowView: View {
    let service: ServiceInfo

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 12) {
            // Service icon
            serviceIcon

            // Service info
            VStack(alignment: .leading, spacing: 2) {
                Text(service.name)
                    .font(.system(.body, weight: .medium))

                if service.health != .operational {
                    let activeCount = service.incidents.filter { $0.isActive }.count
                    if activeCount > 0 {
                        Text("\(activeCount) active incident\(activeCount == 1 ? "" : "s")")
                            .font(.caption)
                            .foregroundStyle(service.health.color)
                    } else {
                        Text(service.health.displayName)
                            .font(.caption)
                            .foregroundStyle(service.health.color)
                    }
                } else {
                    componentSummary
                }
            }

            Spacer()

            // Response time
            if let ms = service.responseTimeMs {
                Text(formatResponseTime(ms))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            // Status indicator
            Image(systemName: service.health.iconName)
                .foregroundStyle(service.health.color)
                .font(.title3)

            Image(systemName: "chevron.right")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isHovered ? Color.primary.opacity(0.06) : Color.clear)
        )
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovered = hovering
        }
    }

    private var serviceIcon: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(iconColor.opacity(0.15))
                .frame(width: 32, height: 32)

            if service.id == "github" {
                Image("GitHubMark")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 16, height: 16)
                    .foregroundStyle(iconColor)
            } else {
                Image(systemName: iconSymbol)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(iconColor)
            }
        }
    }

    private var iconSymbol: String {
        switch service.id {
        case "azure": "cloud.fill"
        case "aws": "server.rack"
        case "pagerduty": "bell.badge.fill"
        case "slack": "number"
        case "zendesk": "headphones"
        case "openai": "brain.head.profile"
        case "claude": "bubble.left.and.text.bubble.right.fill"
        default: "server.rack"
        }
    }

    private var iconColor: Color {
        switch service.id {
        case "github": .purple
        case "azure": .blue
        case "aws": .orange
        case "pagerduty": .green
        case "slack": .pink
        case "zendesk": .teal
        case "openai": .mint
        case "claude": .indigo
        default: .gray
        }
    }

    private var componentSummary: some View {
        let total = service.components.count
        let healthy = service.components.filter { $0.status == .operational }.count
        return Group {
            if total > 0 {
                Text("\(healthy)/\(total) components healthy")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("All systems operational")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func formatResponseTime(_ ms: Double) -> String {
        if ms < 1000 {
            return "\(Int(ms)) ms"
        } else {
            return String(format: "%.1fs", ms / 1000)
        }
    }
}
