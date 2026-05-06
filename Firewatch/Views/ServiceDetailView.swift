import SwiftUI

struct ServiceDetailView: View {
    let service: ServiceInfo
    let onBack: () -> Void

    @State private var expandedIncidentID: String?

    var body: some View {
        VStack(spacing: 0) {
            detailHeader
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if !service.components.isEmpty {
                        componentsSection
                    }
                    if !service.incidents.isEmpty {
                        incidentsSection
                    }
                    if service.components.isEmpty && service.incidents.isEmpty {
                        emptyDetailView
                    }
                }
                .padding(16)
            }
            .frame(maxHeight: 500)
        }
    }

    // MARK: - Header

    private var detailHeader: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Button {
                    onBack()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.body.weight(.medium))
                }
                .buttonStyle(.plain)

                VStack(alignment: .leading, spacing: 2) {
                    Text(service.name)
                        .font(.headline)
                    HStack(spacing: 4) {
                        Image(systemName: service.health.iconName)
                            .foregroundStyle(service.health.color)
                            .font(.caption)
                        Text(service.health.displayName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            if !service.statusPageURL.isEmpty, let url = URL(string: service.statusPageURL) {
                Link(destination: url) {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.up.right.square")
                            .font(.caption)
                        Text(service.statusPageURL)
                            .font(.caption)
                            .lineLimit(1)
                    }
                    .foregroundStyle(.link)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 10)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Components

    private var componentsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Components")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            VStack(spacing: 2) {
                ForEach(service.components) { component in
                    ComponentRowView(component: component)
                }
            }
        }
    }

    // MARK: - Incidents

    private var incidentsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Recent Incidents")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)

                let activeCount = service.incidents.filter { $0.isActive }.count
                if activeCount > 0 {
                    Text("\(activeCount) active")
                        .font(.caption2.weight(.medium))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.red.opacity(0.15))
                        .foregroundStyle(.red)
                        .clipShape(Capsule())
                }
            }

            VStack(spacing: 6) {
                ForEach(service.incidents) { incident in
                    incidentCard(incident)
                }
            }
        }
    }

    private func incidentCard(_ incident: ServiceIncident) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                withAnimation(.easeInOut(duration: 0.15)) {
                    expandedIncidentID = expandedIncidentID == incident.id ? nil : incident.id
                }
            } label: {
                HStack(alignment: .top) {
                    Circle()
                        .fill(incident.isActive ? Color.red : Color.green)
                        .frame(width: 8, height: 8)
                        .padding(.top, 4)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(incident.title)
                            .font(.callout.weight(.medium))
                            .foregroundStyle(.primary)
                            .multilineTextAlignment(.leading)

                        HStack(spacing: 8) {
                            Text(incident.status)
                                .font(.caption2)
                                .foregroundStyle(incident.isActive ? .red : .green)

                            Text(incident.createdAt, style: .relative)
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }

                    Spacer()

                    if !incident.updates.isEmpty {
                        Image(systemName: expandedIncidentID == incident.id
                              ? "chevron.up" : "chevron.down")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .buttonStyle(.plain)

            if expandedIncidentID == incident.id && !incident.updates.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(incident.updates) { update in
                        VStack(alignment: .leading, spacing: 4) {
                            if !update.status.isEmpty {
                                Text(update.status)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                            }
                            Text(update.body)
                                .font(.caption)
                                .foregroundStyle(.primary)
                                .fixedSize(horizontal: false, vertical: true)
                            Text(update.createdAt, style: .date)
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                        if update.id != incident.updates.last?.id {
                            Divider()
                        }
                    }
                }
                .padding(.leading, 20)
                .padding(.top, 4)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.primary.opacity(0.04))
        )
    }

    // MARK: - Empty State

    private var emptyDetailView: some View {
        VStack(spacing: 8) {
            Image(systemName: "checkmark.shield.fill")
                .font(.largeTitle)
                .foregroundStyle(.green)
            Text("No issues or incidents reported")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }
}

// MARK: - Component Row with Hover

private struct ComponentRowView: View {
    let component: ServiceComponent
    @State private var isHovered = false

    var body: some View {
        HStack {
            Image(systemName: component.status.iconName)
                .foregroundStyle(component.status.color)
                .font(.caption)
                .frame(width: 16)

            Text(component.name)
                .font(.system(.callout))

            Spacer()

            Text(component.status.displayName)
                .font(.caption)
                .foregroundStyle(component.status.color)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(backgroundColor)
        )
        .onHover { hovering in
            isHovered = hovering
        }
    }

    private var backgroundColor: Color {
        if isHovered {
            return Color.primary.opacity(0.06)
        } else if component.status != .operational {
            return component.status.color.opacity(0.08)
        }
        return .clear
    }
}
