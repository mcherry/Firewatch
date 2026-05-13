# Changelog

All notable changes to Firewatch are documented here.

## [1.4.1] — 2026-05-13

### Changed
- Replaced third-party KeyboardShortcuts library with a native Carbon hotkey implementation — Firewatch now has zero external dependencies
- Custom shortcut recorder view in Settings replaces the library-provided one

## [1.4.0] — 2026-05-13

### Added
- **TCP port check** — new `tcpCheck(host, port, options?)` function available in check scripts. Connects to an arbitrary TCP port and returns `{success, latencyMs, error}` with configurable timeout. Useful for monitoring databases, mail servers, and other non-HTTP services.
- TCP port check example added to `TEMPLATE.js.example`

### Fixed
- Status icons are now consistent across the dashboard — all health states use circle-family SF Symbols instead of mixing triangles and circles

## [1.3.1] — 2026-05-12

### Fixed
- Services with active incidents but no degraded components now correctly show as degraded instead of operational
- Uptime History "Range" label no longer wraps to a second line

## [1.3.0] — 2026-05-12

### Added
- **Uptime history logging** — records service health to a local SQLite database at each poll interval
- **Uptime History window** — resizable window with per-service status timeline charts using Swift Charts
- **Time range selector** — view uptime history over 1 hour, 24 hours, 7 days, or 30 days
- **Uptime percentage badges** — shows calculated uptime % per service for the selected time range
- **Enable Uptime Logging** toggle in Settings → General
- **Uptime History button** in the dashboard footer (chart icon between Settings and Quit)
- Auto-refresh of the uptime graph when new poll data is logged while the window is open
- Color-coded status legend in the uptime history window

## [1.2.0] — 2026-05-11

### Added
- Automatic version checking against GitHub releases
- Sleep/wake awareness — pauses polling when the Mac sleeps, force-refreshes on wake

## [1.0.0] — 2026-05-06

### Added
- Initial release
- Menu bar status icon with color/shape reflecting overall service health
- Floating status dashboard with service list and component-level detail
- Service drill-down view with components, active incidents, and event history
- Configurable global keyboard shortcut (default: ⇧⌥S)
- Background polling with configurable refresh interval (30s–10min, default: 2min)
- macOS notification support for status change alerts
- JavaScript-based custom status checks via built-in JavaScriptCore engine
- Default check scripts for GitHub, Azure DevOps, AWS, PagerDuty, Slack, Zendesk, OpenAI, and Claude
- Dark mode support
- Settings window with General, Scripts, and About tabs
