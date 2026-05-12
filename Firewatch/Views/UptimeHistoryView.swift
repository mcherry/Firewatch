import SwiftUI
import Charts

// MARK: - Time Range

enum UptimeTimeRange: String, CaseIterable, Identifiable {
    case hour = "1h"
    case day = "24h"
    case week = "7d"
    case month = "30d"

    var id: String { rawValue }

    var label: String { rawValue }

    var startDate: Date {
        let now = Date()
        switch self {
        case .hour: return now.addingTimeInterval(-3600)
        case .day: return now.addingTimeInterval(-86400)
        case .week: return now.addingTimeInterval(-604800)
        case .month: return now.addingTimeInterval(-2592000)
        }
    }
}

// MARK: - Chart Segment

/// A contiguous run of the same health state for one service.
struct UptimeSegment: Identifiable {
    let id = UUID()
    let serviceId: String
    let serviceName: String
    let health: ServiceHealth
    let start: Date
    let end: Date
}

// MARK: - Per-Service Summary

struct ServiceUptimeSummary: Identifiable {
    let id: String
    let name: String
    let uptimePercent: Double
    let segments: [UptimeSegment]
}

// MARK: - Main View

struct UptimeHistoryView: View {
    let uptimeStore: UptimeStore

    @State private var selectedRange: UptimeTimeRange = .day
    @State private var summaries: [ServiceUptimeSummary] = []
    @State private var isLoading = false

    var body: some View {
        VStack(spacing: 0) {
            headerView
            Divider()

            if isLoading {
                Spacer()
                ProgressView("Loading history…")
                Spacer()
            } else if summaries.isEmpty {
                emptyStateView
            } else {
                ScrollView {
                    VStack(spacing: 16) {
                        ForEach(summaries) { summary in
                            serviceChartView(summary)
                        }
                    }
                    .padding()
                }
            }

            Divider()
            legendView
        }
        .frame(minWidth: 600, minHeight: 400)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear { loadData() }
        .onChange(of: selectedRange) { loadData() }
        .onReceive(NotificationCenter.default.publisher(for: .uptimeDataUpdated)) { _ in
            loadData()
        }
    }

    // MARK: - Header

    private var headerView: some View {
        HStack {
            Text("Uptime History")
                .font(.headline)

            Spacer()

            Picker("Range", selection: $selectedRange) {
                ForEach(UptimeTimeRange.allCases) { range in
                    Text(range.label).tag(range)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 200)
        }
        .padding()
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "chart.bar.xaxis")
                .font(.system(size: 36))
                .foregroundStyle(.secondary)
            Text("No Uptime Data")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("Enable uptime logging in Settings to start\nrecording service health history.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Per-Service Chart

    private func serviceChartView(_ summary: ServiceUptimeSummary) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(summary.name)
                    .font(.subheadline.weight(.medium))

                Spacer()

                uptimeBadge(summary.uptimePercent)
            }

            Chart(summary.segments) { segment in
                RectangleMark(
                    xStart: .value("Start", segment.start),
                    xEnd: .value("End", segment.end),
                    y: .value("Service", segment.serviceName)
                )
                .foregroundStyle(segment.health.color)
                .cornerRadius(2)
            }
            .chartXScale(domain: selectedRange.startDate ... Date())
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: xAxisTickCount)) { _ in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                        .foregroundStyle(Color.primary.opacity(0.08))
                    AxisValueLabel(format: xAxisFormat)
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }
            }
            .chartYAxis(.hidden)
            .frame(height: 32)
        }
        .padding(.vertical, 4)
    }

    // MARK: - Badge

    private func uptimeBadge(_ percent: Double) -> some View {
        let color: Color = percent >= 99.9 ? .green
            : percent >= 99.0 ? .yellow
            : percent >= 95.0 ? .orange
            : .red

        return Text(String(format: "%.2f%%", percent))
            .font(.caption.monospacedDigit())
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(color.opacity(0.12))
            .clipShape(Capsule())
    }

    // MARK: - Legend

    private var legendView: some View {
        HStack(spacing: 16) {
            legendDot(.green, "Operational")
            legendDot(.yellow, "Degraded")
            legendDot(.orange, "Partial Outage")
            legendDot(.red, "Major Outage")
            legendDot(.secondary, "Unknown")
            Spacer()
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    private func legendDot(_ color: Color, _ label: String) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - X-Axis Helpers

    private var xAxisTickCount: Int {
        switch selectedRange {
        case .hour: return 6
        case .day: return 8
        case .week: return 7
        case .month: return 6
        }
    }

    private var xAxisFormat: Date.FormatStyle {
        switch selectedRange {
        case .hour:
            return .dateTime.hour().minute()
        case .day:
            return .dateTime.hour()
        case .week:
            return .dateTime.weekday(.abbreviated)
        case .month:
            return .dateTime.month(.abbreviated).day()
        }
    }

    // MARK: - Data Loading

    private func loadData() {
        isLoading = true
        let store = uptimeStore
        let range = selectedRange

        DispatchQueue.global(qos: .userInitiated).async {
            let from = range.startDate
            let to = Date()
            let allServices = store.fetchAllServices()

            var results: [ServiceUptimeSummary] = []

            for svc in allServices {
                let entries = store.fetchHistory(serviceId: svc.id, from: from, to: to)
                let uptime = store.fetchUptimePercentage(serviceId: svc.id, from: from, to: to)
                let segments = buildSegments(from: entries, rangeStart: from, rangeEnd: to)
                results.append(ServiceUptimeSummary(
                    id: svc.id,
                    name: svc.name,
                    uptimePercent: uptime,
                    segments: segments
                ))
            }

            DispatchQueue.main.async {
                summaries = results
                isLoading = false
            }
        }
    }

    /// Converts a list of log entries into contiguous segments of the same health state.
    private func buildSegments(from entries: [StatusLogEntry], rangeStart: Date, rangeEnd: Date) -> [UptimeSegment] {
        guard let first = entries.first else { return [] }

        var segments: [UptimeSegment] = []
        var currentHealth = first.serviceHealth
        var segmentStart = max(first.timestamp, rangeStart)
        let serviceName = first.serviceName
        let serviceId = first.serviceId

        for i in 1..<entries.count {
            let entry = entries[i]
            if entry.serviceHealth != currentHealth {
                // Close the previous segment at this entry's timestamp
                segments.append(UptimeSegment(
                    serviceId: serviceId,
                    serviceName: serviceName,
                    health: currentHealth,
                    start: segmentStart,
                    end: entry.timestamp
                ))
                currentHealth = entry.serviceHealth
                segmentStart = entry.timestamp
            }
        }

        // Close the final segment
        segments.append(UptimeSegment(
            serviceId: serviceId,
            serviceName: serviceName,
            health: currentHealth,
            start: segmentStart,
            end: rangeEnd
        ))

        return segments
    }
}
