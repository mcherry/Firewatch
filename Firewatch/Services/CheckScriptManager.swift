import Foundation

/// Manages the checks directory and ensures default scripts exist on first launch.
struct CheckScriptManager {

    static let checksDirectory: URL = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("Firewatch/checks")
    }()

    /// Creates the checks directory and writes default scripts if they don't already exist.
    static func ensureDefaultScripts() {
        let fm = FileManager.default

        if !fm.fileExists(atPath: checksDirectory.path) {
            try? fm.createDirectory(at: checksDirectory, withIntermediateDirectories: true)
        }

        for (filename, content) in defaultScripts {
            let dest = checksDirectory.appendingPathComponent(filename)
            if !fm.fileExists(atPath: dest.path) {
                try? content.write(to: dest, atomically: true, encoding: .utf8)
            }
        }
    }

    private static let defaultScripts: [(String, String)] = [
        ("01-github.js", githubScript),
        ("02-azure-devops.js", azureScript),
        ("03-aws.js", awsScript),
        ("04-pagerduty.js", pagerdutyScript),
        ("05-slack.js", slackScript),
        ("06-zendesk.js", zendeskScript),
        ("07-openai.js", openaiScript),
        ("08-claude.js", claudeScript),
        ("TEMPLATE.js.example", templateScript),
    ]
}

// MARK: - Statuspage.io Services (one-liners)

extension CheckScriptManager {

    static let githubScript = #"""
    // FIREWATCH_NAME = "GitHub"
    // FIREWATCH_URL = "https://www.githubstatus.com"

    statuspageCheck("https://www.githubstatus.com/api/v2/summary.json");
    """#

    static let openaiScript = #"""
    // FIREWATCH_NAME = "OpenAI"
    // FIREWATCH_URL = "https://status.openai.com"

    statuspageCheck("https://status.openai.com/api/v2/summary.json", { showcaseFilter: false });
    """#

    static let claudeScript = #"""
    // FIREWATCH_NAME = "Claude"
    // FIREWATCH_URL = "https://status.claude.com"

    statuspageCheck("https://status.claude.com/api/v2/summary.json");
    """#
}

// MARK: - Azure DevOps

extension CheckScriptManager {

    static let azureScript = #"""
    // FIREWATCH_NAME = "Azure DevOps"
    // FIREWATCH_URL = "https://status.dev.azure.com"

    var data = fetch("https://status.dev.azure.com/_apis/status/health");
    var healthMap = { healthy: "operational", degraded: "degraded", unhealthy: "major_outage" };
    var overallStatus = healthMap[(data.status.health || "").toLowerCase()] || "unknown";

    var severities = { operational: 0, degraded: 1, partial_outage: 2, major_outage: 3, unknown: -1 };

    var components = (data.services || []).map(function(svc) {
        var worstHealth = "operational";
        var worstSev = 0;
        var degradedGeos = [];

        (svc.geographies || []).forEach(function(geo) {
            var mapped = healthMap[(geo.health || "").toLowerCase()] || "unknown";
            var sev = severities[mapped] || -1;
            if (sev > worstSev) { worstSev = sev; worstHealth = mapped; }
            if (mapped !== "operational") {
                degradedGeos.push(geo.name + ": " + geo.health);
            }
        });

        return {
            name: svc.id,
            status: worstHealth,
            description: degradedGeos.length > 0 ? degradedGeos.join(", ") : null
        };
    });

    output({ status: overallStatus, components: components });
    """#
}

// MARK: - AWS

extension CheckScriptManager {

    static let awsScript = #"""
    // FIREWATCH_NAME = "AWS"
    // FIREWATCH_URL = "https://health.aws.amazon.com/health/status"

    var events = fetch("https://health.aws.amazon.com/public/currentevents", { encoding: "utf-16" });
    var statusMap = { "0": "degraded", "1": "partial_outage", "2": "major_outage", "3": "operational" };
    var statusLabels = { "0": "Informational", "1": "Investigating", "2": "Disruption", "3": "Resolved" };

    var activeEvents = events.filter(function(e) { return e.status !== "3"; });
    var resolvedEvents = events.filter(function(e) { return e.status === "3"; });

    var overallStatus = "operational";
    if (activeEvents.length > 0) {
        if (activeEvents.some(function(e) { return e.status === "2"; })) {
            overallStatus = "major_outage";
        } else {
            overallStatus = "partial_outage";
        }
    }

    // Components: one per affected region when there are active issues
    var components = [];
    if (activeEvents.length > 0) {
        var byRegion = {};
        activeEvents.forEach(function(e) {
            if (!byRegion[e.region_name]) byRegion[e.region_name] = [];
            byRegion[e.region_name].push(e);
        });

        var sevOrder = { operational: 0, degraded: 1, partial_outage: 2, major_outage: 3 };
        Object.keys(byRegion).sort().forEach(function(region) {
            var regionEvents = byRegion[region];
            var worst = "operational";
            var worstSev = 0;
            var summaries = [];
            regionEvents.forEach(function(e) {
                var mapped = statusMap[e.status] || "unknown";
                var sev = sevOrder[mapped] || 0;
                if (sev > worstSev) { worstSev = sev; worst = mapped; }
                summaries.push(e.summary);
            });
            components.push({ name: region, status: worst, description: summaries.join("; ") });
        });
    }

    // Incidents: active first, then recent resolved
    var allForDisplay = activeEvents.concat(resolvedEvents.slice(0, 5));
    var incidents = allForDisplay.slice(0, 10).map(function(event) {
        var updates = (event.event_log || []).slice(0, 5).map(function(logEntry) {
            var body = logEntry.message || logEntry.summary;
            return {
                body: stripHtml(body),
                status: (logEntry.status !== null && logEntry.status !== undefined)
                    ? (statusLabels[String(logEntry.status)] || "") : "",
                created_at: logEntry.timestamp
                    ? new Date(logEntry.timestamp * 1000).toISOString()
                    : new Date().toISOString()
            };
        });

        return {
            title: event.summary + " (" + event.region_name + ")",
            status: statusLabels[event.status] || "",
            impact: statusMap[event.status] || "unknown",
            created_at: event.date
                ? new Date(Number(event.date) * 1000).toISOString()
                : new Date().toISOString(),
            updated_at: null,
            is_active: event.status !== "3",
            updates: updates
        };
    });

    output({ status: overallStatus, components: components, incidents: incidents });
    """#
}

// MARK: - PagerDuty

extension CheckScriptManager {

    static let pagerdutyScript = #"""
    // FIREWATCH_NAME = "PagerDuty"
    // FIREWATCH_URL = "https://status.pagerduty.com"

    var data = fetch("https://status.pagerduty.com/api/data");
    var settings = ((data.layout || {}).layout_settings || {});
    var headline = (settings.statusPage || {}).globalStatusHeadline || "";
    var lower = headline.toLowerCase();

    var status = "unknown";
    if (/smooth|operational|running/.test(lower)) status = "operational";
    else if (/major|outage|critical/.test(lower)) status = "major_outage";
    else if (/partial|disruption/.test(lower)) status = "partial_outage";
    else if (/degrad|issue|investigat|monitor/.test(lower)) status = "degraded";

    var services = settings.business_services || [];
    var components = services.filter(function(svc) {
        return svc.grouping_element === true && svc.name && svc.name.length > 0;
    }).map(function(svc) {
        return { name: svc.name, status: status, description: null };
    });

    output({ status: status, components: components });
    """#
}

// MARK: - Slack

extension CheckScriptManager {

    static let slackScript = #"""
    // FIREWATCH_NAME = "Slack"
    // FIREWATCH_URL = "https://status.slack.com"

    var results = fetchAll([
        "https://status.slack.com/api/v2.0.0/current",
        "https://status.slack.com/api/v2.0.0/history"
    ]);
    var current = results[0];
    var history = results[1] || [];

    var activeIncidents = current.active_incidents || [];
    var hasActive = activeIncidents.length > 0;
    var overallStatus = hasActive ? "degraded" : (current.status === "ok" ? "operational" : "degraded");

    // Components from active incidents' affected services
    var components = [];
    activeIncidents.forEach(function(inc) {
        (inc.services || []).forEach(function(svcName) {
            components.push({ name: svcName, status: "degraded", description: inc.title || null });
        });
    });

    // Incidents from history
    var incidents = (Array.isArray(history) ? history : []).slice(0, 10).map(function(inc) {
        var updates = (inc.notes || []).map(function(note) {
            return {
                body: stripHtml(note.body),
                status: "",
                created_at: note.date_created || null
            };
        });

        return {
            title: inc.title,
            status: inc.status,
            impact: inc.type === "incident" ? "partial_outage" : "degraded",
            created_at: inc.date_created || null,
            updated_at: inc.date_updated || null,
            is_active: inc.status === "active",
            updates: updates
        };
    });

    output({ status: overallStatus, components: components, incidents: incidents });
    """#
}

// MARK: - Zendesk

extension CheckScriptManager {

    static let zendeskScript = #"""
    // FIREWATCH_NAME = "Zendesk"
    // FIREWATCH_URL = "https://status.zendesk.com"

    var today = new Date().toISOString().split("T")[0];
    var results = fetchAll([
        "https://status.zendesk.com/api/ssp/services.json",
        "https://status.zendesk.com/api/ssp/incidents.json?as_of_date=" + today + "&days_back=7"
    ]);
    var servicesResp = results[0];
    var incidentsResp = results[1];

    var allIncidents = (incidentsResp.data || []);
    var included = incidentsResp.included || [];

    // Find active (unresolved) incidents
    var activeIncidents = allIncidents.filter(function(inc) {
        return !inc.attributes.resolvedAt;
    });

    // Build set of affected service IDs from active incidents
    var activeServiceIds = {};
    activeIncidents.forEach(function(inc) {
        var refs = (inc.relationships && inc.relationships.incidentServices
            && inc.relationships.incidentServices.data) || [];
        refs.forEach(function(ref) { activeServiceIds[ref.id] = true; });
    });

    // Get affected service details
    var affectedDetails = included.filter(function(item) { return activeServiceIds[item.id]; });
    var affectedServiceNames = {};
    affectedDetails.forEach(function(d) {
        if (d.attributes.serviceName) affectedServiceNames[d.attributes.serviceName] = true;
    });

    // Map components
    var severities = { unknown: -1, operational: 0, degraded: 1, partial_outage: 2, major_outage: 3 };
    var components = (servicesResp.data || []).filter(function(svc) {
        return !svc.attributes.deprecated;
    }).map(function(svc) {
        var matching = affectedDetails.filter(function(d) {
            return d.attributes.serviceName === svc.attributes.name;
        });
        var hasOutage = matching.some(function(d) { return d.attributes.outage; });
        var hasDegradation = matching.some(function(d) { return d.attributes.degradation; });

        var status = "operational";
        if (hasOutage) status = "major_outage";
        else if (hasDegradation) status = "degraded";
        else if (affectedServiceNames[svc.attributes.name]) status = "partial_outage";

        return { name: svc.attributes.name, status: status, description: null };
    });

    // Overall health: worst component
    var overallStatus = "operational";
    components.forEach(function(c) {
        if ((severities[c.status] || 0) > (severities[overallStatus] || 0)) {
            overallStatus = c.status;
        }
    });

    // Map incidents
    var mappedIncidents = allIncidents.slice(0, 10).map(function(inc) {
        var incRefs = (inc.relationships && inc.relationships.incidentServices
            && inc.relationships.incidentServices.data) || [];
        var affectedNames = included.filter(function(item) {
            return incRefs.some(function(ref) { return ref.id === item.id; });
        }).map(function(item) {
            return item.attributes.serviceName;
        }).filter(Boolean).join(", ");

        var updates = [];
        if (affectedNames) {
            updates.push({
                body: "Affected: " + affectedNames,
                status: inc.attributes.status,
                created_at: inc.attributes.startedAt || null
            });
        }

        var impact = "partial_outage";
        if (inc.attributes.outage) impact = "major_outage";
        else if (inc.attributes.degradation) impact = "degraded";

        return {
            title: inc.attributes.name,
            status: inc.attributes.status,
            impact: impact,
            created_at: inc.attributes.startedAt || null,
            updated_at: inc.attributes.resolvedAt || null,
            is_active: !inc.attributes.resolvedAt,
            updates: updates
        };
    });

    output({ status: overallStatus, components: components, incidents: mappedIncidents });
    """#
}

// MARK: - Template

extension CheckScriptManager {

    static let templateScript = #"""
    // FIREWATCH_NAME = "My Service"
    // FIREWATCH_URL = "https://example.com/status"
    //
    // Firewatch Status Check Template
    // ================================
    // Copy this file, rename to NN-myservice.js, and restart Firewatch
    // (or click "Reload Scripts" in Settings).
    //
    // Available functions:
    //   fetch(url)             — HTTP GET, returns parsed JSON
    //   fetch(url, {encoding}) — HTTP GET with custom encoding (e.g., "utf-16")
    //   fetchText(url)         — HTTP GET, returns raw string
    //   fetchAll([urls])       — fetch multiple URLs concurrently, returns array
    //   output(obj)            — set the result (required, call exactly once)
    //   stripHtml(text)        — remove HTML tags and decode entities
    //   log(message)           — debug logging (visible in Console.app)
    //   statuspageCheck(url)   — one-liner for Statuspage.io services
    //
    // Status values: "operational", "degraded", "partial_outage", "major_outage", "unknown"

    // Simple example: check if a URL responds successfully
    try {
        fetch("https://example.com/api/health");
        output({ status: "operational" });
    } catch (e) {
        output({ status: "major_outage" });
    }
    """#
}
