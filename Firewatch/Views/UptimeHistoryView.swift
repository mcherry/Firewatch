import SwiftUI
import Charts
import AppKit

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

// MARK: - Response Time Data Point

struct ResponseTimePoint: Identifiable {
    let id = UUID()
    let timestamp: Date
    let responseTimeMs: Double
}

// MARK: - Response Time Stats

struct ResponseTimeStats {
    let min: Double
    let avg: Double
    let max: Double
}

// MARK: - Per-Service Summary

struct ServiceUptimeSummary: Identifiable {
    let id: String
    let name: String
    let uptimePercent: Double
    let segments: [UptimeSegment]
    let responseTimePoints: [ResponseTimePoint]
    let responseTimeStats: ResponseTimeStats?
}

// MARK: - Main View

struct UptimeHistoryView: View {
    let uptimeStore: UptimeStore
    let statusManager: StatusManager

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

            Menu {
                Button("Export CSV…") { exportCSV() }
                Button("Export PDF…") { exportPDF() }
            } label: {
                Label("Export", systemImage: "square.and.arrow.up")
                    .font(.caption)
            }
            .menuStyle(.borderlessButton)
            .frame(width: 80)
            .disabled(summaries.isEmpty)

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

                if let stats = summary.responseTimeStats {
                    responseTimeStatsBadge(stats)
                }

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

            if !summary.responseTimePoints.isEmpty {
                Chart(summary.responseTimePoints) { point in
                    LineMark(
                        x: .value("Time", point.timestamp),
                        y: .value("Response Time", point.responseTimeMs)
                    )
                    .foregroundStyle(Color.blue.opacity(0.6))
                    .lineStyle(StrokeStyle(lineWidth: 1))
                }
                .chartXScale(domain: selectedRange.startDate ... Date())
                .chartXAxis(.hidden)
                .chartYAxis {
                    AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { _ in
                        AxisValueLabel()
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(.tertiary)
                    }
                }
                .frame(height: 40)
            }
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

    private func responseTimeStatsBadge(_ stats: ResponseTimeStats) -> some View {
        Text("avg \(Int(stats.avg)) ms")
            .font(.caption.monospacedDigit())
            .foregroundStyle(.blue)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(Color.blue.opacity(0.1))
            .clipShape(Capsule())
            .help("Min: \(Int(stats.min)) ms  Avg: \(Int(stats.avg)) ms  Max: \(Int(stats.max)) ms")
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
        let activeServiceIDs = Set(statusManager.services.map { $0.id })

        DispatchQueue.global(qos: .userInitiated).async {
            let from = range.startDate
            let to = Date()
            let allServices = store.fetchAllServices()
                .filter { activeServiceIDs.isEmpty || activeServiceIDs.contains($0.id) }

            var results: [ServiceUptimeSummary] = []

            for svc in allServices {
                let entries = store.fetchHistory(serviceId: svc.id, from: from, to: to)
                let uptime = store.fetchUptimePercentage(serviceId: svc.id, from: from, to: to)
                let segments = buildSegments(from: entries, rangeStart: from, rangeEnd: to)

                let rtPoints = entries.compactMap { entry -> ResponseTimePoint? in
                    guard let rt = entry.responseTimeMs else { return nil }
                    return ResponseTimePoint(timestamp: entry.timestamp, responseTimeMs: rt)
                }

                let rtStats: ResponseTimeStats?
                if let stats = store.fetchResponseTimeStats(serviceId: svc.id, from: from, to: to) {
                    rtStats = ResponseTimeStats(min: stats.min, avg: stats.avg, max: stats.max)
                } else {
                    rtStats = nil
                }

                results.append(ServiceUptimeSummary(
                    id: svc.id,
                    name: svc.name,
                    uptimePercent: uptime,
                    segments: segments,
                    responseTimePoints: rtPoints,
                    responseTimeStats: rtStats
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

        segments.append(UptimeSegment(
            serviceId: serviceId,
            serviceName: serviceName,
            health: currentHealth,
            start: segmentStart,
            end: rangeEnd
        ))

        return segments
    }

    // MARK: - Export CSV

    private func exportCSV() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.nameFieldStringValue = "firewatch-uptime-\(selectedRange.rawValue).csv"

        guard panel.runModal() == .OK, let url = panel.url else { return }

        let store = uptimeStore
        let range = selectedRange
        let activeServiceIDs = Set(statusManager.services.map { $0.id })

        DispatchQueue.global(qos: .userInitiated).async {
            let from = range.startDate
            let to = Date()
            let entries = store.fetchHistory(from: from, to: to)
                .filter { activeServiceIDs.isEmpty || activeServiceIDs.contains($0.serviceId) }

            let healthNames = [-1: "Unknown", 0: "Operational", 1: "Degraded", 2: "Partial Outage", 3: "Major Outage"]
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime]

            var csv = "Timestamp,Service,Health,Response Time (ms)\n"
            for entry in entries {
                let ts = formatter.string(from: entry.timestamp)
                let health = healthNames[entry.health] ?? "Unknown"
                let rt = entry.responseTimeMs.map { String(format: "%.1f", $0) } ?? ""
                csv += "\(ts),\(csvEscape(entry.serviceName)),\(health),\(rt)\n"
            }

            try? csv.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    private func csvEscape(_ value: String) -> String {
        if value.contains(",") || value.contains("\"") || value.contains("\n") {
            return "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
        }
        return value
    }

    // MARK: - Export PDF

    private func exportPDF() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = "firewatch-uptime-\(selectedRange.rawValue).pdf"

        guard panel.runModal() == .OK, let url = panel.url else { return }

        let store = uptimeStore
        let range = selectedRange
        let currentSummaries = summaries

        DispatchQueue.global(qos: .userInitiated).async {
            let from = range.startDate
            let to = Date()
            let dateFormatter = DateFormatter()
            dateFormatter.dateStyle = .medium
            dateFormatter.timeStyle = .short

            let pageWidth: CGFloat = 612
            let pageHeight: CGFloat = 792
            let margin: CGFloat = 50
            let contentWidth = pageWidth - margin * 2

            var mediaBox = CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight)
            guard let context = CGContext(url as CFURL, mediaBox: &mediaBox, nil) else { return }

            var yPos: CGFloat = pageHeight - margin

            func startPage() {
                context.beginPage(mediaBox: &mediaBox)
                yPos = pageHeight - margin
            }

            func checkPageBreak(_ needed: CGFloat) {
                if yPos - needed < margin {
                    context.endPage()
                    startPage()
                }
            }

            func drawText(_ text: String, x: CGFloat, y: CGFloat, font: NSFont, color: NSColor = .black) {
                let attributes: [NSAttributedString.Key: Any] = [
                    .font: font,
                    .foregroundColor: color
                ]
                let str = NSAttributedString(string: text, attributes: attributes)
                let line = CTLineCreateWithAttributedString(str)
                context.saveGState()
                context.textPosition = CGPoint(x: x, y: y)
                CTLineDraw(line, context)
                context.restoreGState()
            }

            startPage()

            // Title
            drawText("Firewatch Uptime Report", x: margin, y: yPos, font: .boldSystemFont(ofSize: 18))
            yPos -= 22
            let rangeStr = "\(dateFormatter.string(from: from)) — \(dateFormatter.string(from: to))"
            drawText(rangeStr, x: margin, y: yPos, font: .systemFont(ofSize: 11), color: .gray)
            yPos -= 30

            // Per-service sections
            for summary in currentSummaries {
                checkPageBreak(100)

                // Service header
                drawText(summary.name, x: margin, y: yPos, font: .boldSystemFont(ofSize: 13))
                let uptimeStr = String(format: "Uptime: %.2f%%", summary.uptimePercent)
                drawText(uptimeStr, x: margin + contentWidth - 120, y: yPos, font: .systemFont(ofSize: 11))
                yPos -= 18

                if let stats = summary.responseTimeStats {
                    let rtStr = String(format: "Response Time — Min: %.0f ms  Avg: %.0f ms  Max: %.0f ms", stats.min, stats.avg, stats.max)
                    drawText(rtStr, x: margin, y: yPos, font: .systemFont(ofSize: 10), color: .gray)
                    yPos -= 18
                }

                // Data table header
                checkPageBreak(40)
                drawText("Timestamp", x: margin, y: yPos, font: .boldSystemFont(ofSize: 9))
                drawText("Health", x: margin + 200, y: yPos, font: .boldSystemFont(ofSize: 9))
                drawText("Response (ms)", x: margin + 340, y: yPos, font: .boldSystemFont(ofSize: 9))
                yPos -= 14

                // Data rows — sample to avoid massive PDFs
                let entries = store.fetchHistory(serviceId: summary.id, from: from, to: to)
                let sampled = sampleEntries(entries, maxRows: 50)

                for entry in sampled {
                    checkPageBreak(14)
                    let healthNames = [-1: "Unknown", 0: "Operational", 1: "Degraded", 2: "Partial Outage", 3: "Major Outage"]
                    drawText(dateFormatter.string(from: entry.timestamp), x: margin, y: yPos, font: .systemFont(ofSize: 9))
                    drawText(healthNames[entry.health] ?? "Unknown", x: margin + 200, y: yPos, font: .systemFont(ofSize: 9))
                    let rtStr = entry.responseTimeMs.map { String(format: "%.1f", $0) } ?? "—"
                    drawText(rtStr, x: margin + 340, y: yPos, font: .systemFont(ofSize: 9))
                    yPos -= 12
                }

                yPos -= 16
            }

            context.endPage()
            context.closePDF()
        }
    }

    /// Evenly samples entries to fit within maxRows.
    private func sampleEntries(_ entries: [StatusLogEntry], maxRows: Int) -> [StatusLogEntry] {
        guard entries.count > maxRows else { return entries }
        let step = Double(entries.count) / Double(maxRows)
        return (0..<maxRows).map { entries[Int(Double($0) * step)] }
    }
}
