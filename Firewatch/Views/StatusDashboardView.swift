import SwiftUI
import AppKit

// NSVisualEffectView wrapper that always renders, even when the window isn't key
struct VisualEffectBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.state = .active
        view.material = .popover
        view.blendingMode = .behindWindow
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

struct StatusDashboardView: View {
    @EnvironmentObject var statusManager: StatusManager
    @State private var selectedService: ServiceInfo?

    var body: some View {
        VStack(spacing: 0) {
            if let service = selectedService {
                ServiceDetailView(service: service) {
                    selectedService = nil
                }
            } else {
                dashboardContent
            }
        }
        .frame(width: 420)
        .background(VisualEffectBackground())
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .onReceive(NotificationCenter.default.publisher(for: .panelDidClose)) { _ in
            selectedService = nil
        }
    }

    // MARK: - Dashboard Content

    private var dashboardContent: some View {
        VStack(spacing: 0) {
            headerView
            Divider()

            if statusManager.services.isEmpty && statusManager.isRefreshing {
                ProgressView("Loading services…")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
            } else if statusManager.services.isEmpty {
                emptyStateView
            } else {
                serviceListView
            }

            Divider()
            footerView
        }
    }

    // MARK: - Header

    private var headerView: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Firewatch")
                    .font(.headline)
                if let date = statusManager.lastRefreshDate {
                    Text("Updated \(date, style: .relative) ago")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            overallStatusBadge

            Button {
                statusManager.manualRefresh()
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.body)
                    .rotationEffect(.degrees(statusManager.isRefreshing ? 360 : 0))
                    .animation(
                        statusManager.isRefreshing
                            ? .linear(duration: 1).repeatForever(autoreverses: false)
                            : .default,
                        value: statusManager.isRefreshing
                    )
            }
            .buttonStyle(.plain)
            .help("Refresh")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var overallStatusBadge: some View {
        let health = statusManager.overallHealth
        return HStack(spacing: 4) {
            Image(systemName: health.iconName)
                .foregroundStyle(health.color)
                .font(.caption)
            Text(health.displayName)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(health.color.opacity(0.1))
        .clipShape(Capsule())
    }

    // MARK: - Service List

    private var serviceListView: some View {
        VStack(spacing: 1) {
            ForEach(statusManager.services) { service in
                ServiceRowView(service: service)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        selectedService = service
                    }
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: 8) {
            Image(systemName: "wifi.slash")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("Unable to load services")
                .foregroundStyle(.secondary)
            Button("Retry") {
                statusManager.manualRefresh()
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 30)
    }

    // MARK: - Footer

    private var footerView: some View {
        HStack {
            Button {
                NotificationCenter.default.post(name: .openSettings, object: nil)
            } label: {
                Image(systemName: "gear")
                    .font(.body)
            }
            .buttonStyle(.plain)
            .help("Settings")

            Spacer()

            Button("Quit") {
                NSApp.terminate(nil)
            }
            .buttonStyle(.plain)
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}
