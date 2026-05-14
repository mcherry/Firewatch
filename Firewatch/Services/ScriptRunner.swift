import Foundation
import JavaScriptCore
import Network

/// Runs a JavaScript status check script in a sandboxed JSContext.
/// Injects helper functions (fetch, fetchAll, fetchText, output, stripHtml, log,
/// statuspageCheck, ping, tcpCheck) and returns the result dictionary produced
/// by calling output().
final class ScriptRunner {

    private static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.httpAdditionalHeaders = [
            "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 15.7; rv:150.0) Gecko/20100101 Firefox/150.0"
        ]
        config.timeoutIntervalForRequest = 15
        return URLSession(configuration: config)
    }()

    static func run(script: String) -> (result: [String: Any]?, elapsedMs: Double) {
        let context = JSContext()!

        context.exceptionHandler = { _, exception in
            print("[Firewatch JS] Error: \(exception?.toString() ?? "unknown")")
        }

        injectOutput(into: context)
        injectFetch(into: context)
        injectFetchResponse(into: context)
        injectFetchText(into: context)
        injectFetchAll(into: context)
        injectStripHtml(into: context)
        injectLog(into: context)
        injectStatuspageCheck(into: context)
        injectTcpCheck(into: context)

        let startTime = CFAbsoluteTimeGetCurrent()
        context.evaluateScript(script)
        let elapsedMs = (CFAbsoluteTimeGetCurrent() - startTime) * 1000.0

        let result = context.objectForKeyedSubscript("__firewatch_result")
        let dict = result?.isUndefined == false && result?.isNull == false
            ? result?.toDictionary() as? [String: Any]
            : nil

        // Break retain cycles (context -> block -> context)
        for key in ["fetch", "fetchResponse", "fetchText", "fetchAll", "stripHtml", "log", "tcpCheck"] {
            context.setObject(nil, forKeyedSubscript: key as NSString)
        }

        return (dict, round(elapsedMs * 100) / 100)
    }

    // MARK: - output() and log()

    private static func injectOutput(into context: JSContext) {
        context.evaluateScript("""
        var __firewatch_result = null;
        function output(obj) { __firewatch_result = obj; }
        """)
    }

    private static func injectLog(into context: JSContext) {
        let block: @convention(block) (String) -> Void = { message in
            print("[Firewatch JS] \(message)")
        }
        context.setObject(block, forKeyedSubscript: "log" as NSString)
    }

    // MARK: - fetch(url, options?)

    private static func injectFetch(into context: JSContext) {
        let sess = session
        let block: @convention(block) (String, JSValue) -> JSValue = { urlString, optionsValue in
            let ctx = JSContext.current()!
            guard let url = URL(string: urlString) else {
                ctx.exception = JSValue(newErrorFromMessage: "Invalid URL: \(urlString)", in: ctx)
                return JSValue(undefinedIn: ctx)
            }

            var encoding: String.Encoding = .utf8
            if !optionsValue.isUndefined && !optionsValue.isNull,
               let opts = optionsValue.toDictionary(),
               let enc = opts["encoding"] as? String {
                switch enc.lowercased() {
                case "utf-16", "utf16": encoding = .utf16
                case "ascii": encoding = .ascii
                case "iso-8859-1", "latin1": encoding = .isoLatin1
                default: break
                }
            }

            let semaphore = DispatchSemaphore(value: 0)
            var resultData: Data?
            var resultError: Error?

            sess.dataTask(with: url) { data, _, error in
                resultData = data
                resultError = error
                semaphore.signal()
            }.resume()

            semaphore.wait()

            if let error = resultError {
                ctx.exception = JSValue(newErrorFromMessage: "Fetch failed: \(error.localizedDescription)", in: ctx)
                return JSValue(undefinedIn: ctx)
            }

            guard let data = resultData,
                  let text = String(data: data, encoding: encoding) else {
                ctx.exception = JSValue(newErrorFromMessage: "Cannot decode response from \(urlString)", in: ctx)
                return JSValue(undefinedIn: ctx)
            }

            let cleanText = text.hasPrefix("\u{FEFF}") ? String(text.dropFirst()) : text

            guard let jsonData = cleanText.data(using: .utf8),
                  let jsonObject = try? JSONSerialization.jsonObject(with: jsonData) else {
                ctx.exception = JSValue(newErrorFromMessage: "Invalid JSON from \(urlString)", in: ctx)
                return JSValue(undefinedIn: ctx)
            }

            return JSValue(object: jsonObject, in: ctx)
        }
        context.setObject(block, forKeyedSubscript: "fetch" as NSString)
    }

    // MARK: - fetchResponse(url)

    private static func injectFetchResponse(into context: JSContext) {
        let sess = session
        let block: @convention(block) (String) -> JSValue = { urlString in
            let ctx = JSContext.current()!
            guard let url = URL(string: urlString) else {
                ctx.exception = JSValue(newErrorFromMessage: "Invalid URL: \(urlString)", in: ctx)
                return JSValue(undefinedIn: ctx)
            }

            let semaphore = DispatchSemaphore(value: 0)
            var resultData: Data?
            var resultResponse: URLResponse?
            var resultError: Error?

            sess.dataTask(with: url) { data, response, error in
                resultData = data
                resultResponse = response
                resultError = error
                semaphore.signal()
            }.resume()

            semaphore.wait()

            if let error = resultError {
                ctx.exception = JSValue(newErrorFromMessage: "Fetch failed: \(error.localizedDescription)", in: ctx)
                return JSValue(undefinedIn: ctx)
            }

            let statusCode = (resultResponse as? HTTPURLResponse)?.statusCode ?? 0

            var body: Any = NSNull()
            if let data = resultData,
               let text = String(data: data, encoding: .utf8) {
                let cleanText = text.hasPrefix("\u{FEFF}") ? String(text.dropFirst()) : text
                if let jsonData = cleanText.data(using: .utf8),
                   let jsonObject = try? JSONSerialization.jsonObject(with: jsonData) {
                    body = jsonObject
                }
            }

            let result: [String: Any] = ["status": statusCode, "body": body]
            return JSValue(object: result, in: ctx)
        }
        context.setObject(block, forKeyedSubscript: "fetchResponse" as NSString)
    }

    // MARK: - fetchText(url)

    private static func injectFetchText(into context: JSContext) {
        let sess = session
        let block: @convention(block) (String) -> JSValue = { urlString in
            let ctx = JSContext.current()!
            guard let url = URL(string: urlString) else {
                ctx.exception = JSValue(newErrorFromMessage: "Invalid URL: \(urlString)", in: ctx)
                return JSValue(undefinedIn: ctx)
            }

            let semaphore = DispatchSemaphore(value: 0)
            var resultData: Data?
            var resultError: Error?

            sess.dataTask(with: url) { data, _, error in
                resultData = data
                resultError = error
                semaphore.signal()
            }.resume()

            semaphore.wait()

            if let error = resultError {
                ctx.exception = JSValue(newErrorFromMessage: "Fetch failed: \(error.localizedDescription)", in: ctx)
                return JSValue(undefinedIn: ctx)
            }

            guard let data = resultData, let text = String(data: data, encoding: .utf8) else {
                ctx.exception = JSValue(newErrorFromMessage: "Cannot decode response from \(urlString)", in: ctx)
                return JSValue(undefinedIn: ctx)
            }

            return JSValue(object: text, in: ctx)
        }
        context.setObject(block, forKeyedSubscript: "fetchText" as NSString)
    }

    // MARK: - fetchAll([urls])

    private static func injectFetchAll(into context: JSContext) {
        let sess = session
        let block: @convention(block) (JSValue) -> JSValue = { urlsValue in
            let ctx = JSContext.current()!
            guard let urls = urlsValue.toArray() as? [String] else {
                ctx.exception = JSValue(newErrorFromMessage: "fetchAll requires an array of URL strings", in: ctx)
                return JSValue(undefinedIn: ctx)
            }

            var results: [Any] = Array(repeating: NSNull(), count: urls.count)
            let group = DispatchGroup()
            let lock = NSLock()

            for (index, urlString) in urls.enumerated() {
                guard let url = URL(string: urlString) else { continue }
                group.enter()
                sess.dataTask(with: url) { data, _, error in
                    defer { group.leave() }
                    guard let data, error == nil,
                          let text = String(data: data, encoding: .utf8),
                          let jsonData = text.data(using: .utf8),
                          let json = try? JSONSerialization.jsonObject(with: jsonData) else { return }
                    lock.lock()
                    results[index] = json
                    lock.unlock()
                }.resume()
            }

            group.wait()
            return JSValue(object: results, in: ctx)
        }
        context.setObject(block, forKeyedSubscript: "fetchAll" as NSString)
    }

    // MARK: - stripHtml(text)

    private static func injectStripHtml(into context: JSContext) {
        let block: @convention(block) (String) -> String = { text in
            var result = text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            result = result.replacingOccurrences(of: "&nbsp;", with: " ")
            result = result.replacingOccurrences(of: "&amp;", with: "&")
            result = result.replacingOccurrences(of: "&lt;", with: "<")
            result = result.replacingOccurrences(of: "&gt;", with: ">")
            result = result.replacingOccurrences(of: "&#39;", with: "'")
            result = result.replacingOccurrences(of: "&quot;", with: "\"")
            return result.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        context.setObject(block, forKeyedSubscript: "stripHtml" as NSString)
    }

    // MARK: - statuspageCheck(url, options?)

    private static func injectStatuspageCheck(into context: JSContext) {
        context.evaluateScript(#"""
        function statuspageCheck(url, options) {
            var opts = options || {};
            var useShowcaseFilter = opts.showcaseFilter !== false;
            var data = fetch(url);

            var statusMap = {
                none: "operational", minor: "degraded",
                major: "partial_outage", critical: "major_outage"
            };
            var compStatusMap = {
                operational: "operational", degraded_performance: "degraded",
                partial_outage: "partial_outage", major_outage: "major_outage"
            };

            var components = (data.components || []).filter(function(c) {
                if (c.group) return false;
                if (useShowcaseFilter) return c.showcase === true;
                return true;
            }).map(function(c) {
                return {
                    name: c.name,
                    status: compStatusMap[c.status] || "unknown",
                    description: c.description || null
                };
            });

            var incidents = (data.incidents || []).slice(0, 10).map(function(inc) {
                return {
                    title: inc.name,
                    status: inc.status,
                    impact: statusMap[inc.impact] || "unknown",
                    created_at: inc.created_at,
                    updated_at: inc.updated_at || null,
                    is_active: inc.status !== "resolved" && inc.status !== "postmortem",
                    updates: (inc.incident_updates || []).map(function(u) {
                        return { body: u.body, status: u.status, created_at: u.created_at };
                    })
                };
            });

            output({
                status: statusMap[data.status.indicator] || "unknown",
                components: components,
                incidents: incidents
            });
        }
        """#)
    }

    // MARK: - tcpCheck(host, port, options?)

    private static func injectTcpCheck(into context: JSContext) {
        let block: @convention(block) (String, Int, JSValue) -> JSValue = { host, port, optionsValue in
            let ctx = JSContext.current()!

            var timeout: TimeInterval = 5
            if !optionsValue.isUndefined && !optionsValue.isNull,
               let opts = optionsValue.toDictionary(),
               let t = opts["timeout"] as? NSNumber {
                timeout = t.doubleValue
            }

            let result = tcpConnect(host: host, port: UInt16(port), timeout: timeout)
            return JSValue(object: result, in: ctx)
        }
        context.setObject(block, forKeyedSubscript: "tcpCheck" as NSString)
    }

    // MARK: - TCP Connect Implementation

    private static func tcpConnect(host: String, port: UInt16, timeout: TimeInterval) -> [String: Any] {
        guard let nwPort = NWEndpoint.Port(rawValue: port) else {
            return ["success": false, "latencyMs": NSNull(), "error": "Invalid port: \(port)"]
        }

        let connection = NWConnection(
            host: NWEndpoint.Host(host),
            port: nwPort,
            using: .tcp
        )

        let semaphore = DispatchSemaphore(value: 0)
        var success = false
        var errorMsg: String?
        let startTime = CFAbsoluteTimeGetCurrent()

        connection.stateUpdateHandler = { state in
            switch state {
            case .ready:
                success = true
                semaphore.signal()
            case .failed(let error):
                errorMsg = error.localizedDescription
                semaphore.signal()
            case .waiting(let error):
                errorMsg = "Waiting: \(error.localizedDescription)"
                semaphore.signal()
            default:
                break
            }
        }

        let queue = DispatchQueue(label: "com.firewatch.tcpcheck")
        connection.start(queue: queue)

        let result = semaphore.wait(timeout: .now() + timeout)
        let latency = (CFAbsoluteTimeGetCurrent() - startTime) * 1000.0
        connection.cancel()

        if result == .timedOut {
            return ["success": false, "latencyMs": NSNull(), "error": "Connection timed out after \(timeout)s"]
        }

        if success {
            return ["success": true, "latencyMs": round(latency * 100) / 100, "error": NSNull()]
        } else {
            return ["success": false, "latencyMs": NSNull(), "error": errorMsg ?? "Connection failed"]
        }
    }
}
