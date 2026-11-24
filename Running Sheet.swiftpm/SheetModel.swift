import SwiftUI
import WebKit

/// Keeps the running sheet's saved data in a file inside the app (so matches survive even if the
/// web view's storage is cleared) and keeps automatic backups of everything.
@MainActor
final class SheetModel: ObservableObject {
    static let storageKey = "wbbl-running-sheet-v1"
    static let maxBackups = 20
    weak var webView: WKWebView?

    private var docs: URL { FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0] }
    private var stateURL: URL { docs.appendingPathComponent("running-sheet-state.json") }
    private var backupDir: URL {
        let dir = docs.appendingPathComponent("Backups", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    // MARK: Current data

    func load() -> String? {
        try? String(contentsOf: stateURL, encoding: .utf8)
    }

    func save(_ json: String) {
        guard json.count > 2 else { return }
        do {
            try json.write(to: stateURL, atomically: true, encoding: .utf8)
        } catch {
            print("Running sheet: could not save – \(error)")
        }
    }

    /// Reads the latest data straight from the page, saves it and backs it up (used when leaving the app).
    func flush() {
        webView?.evaluateJavaScript("localStorage.getItem('\(Self.storageKey)')") { [weak self] result, _ in
            guard let json = result as? String else { return }
            Task { @MainActor in
                self?.save(json)
                self?.snapshot(json, reason: "left the app", label: "")
            }
        }
    }

    // MARK: Backups

    func snapshot(_ json: String, reason: String, label: String) {
        guard json.count > 2 else { return }
        // Skip if nothing has changed since the newest backup.
        if let newest = backupFiles().first,
           let wrapper = readWrapper(newest),
           (wrapper["data"] as? String) == json { return }
        let wrapper: [String: Any] = [
            "created": Date().timeIntervalSince1970,
            "reason": reason,
            "label": label,
            "data": json
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: wrapper) else { return }
        let stamp = Self.fileStamp.string(from: Date())
        var url = backupDir.appendingPathComponent("\(stamp).json")
        var n = 2
        while FileManager.default.fileExists(atPath: url.path) {
            url = backupDir.appendingPathComponent("\(stamp)-\(n).json"); n += 1
        }
        try? data.write(to: url, options: .atomic)
        // Keep only the newest backups.
        for old in backupFiles().dropFirst(Self.maxBackups) { try? FileManager.default.removeItem(at: old) }
    }

    /// Newest first.
    func backupFiles() -> [URL] {
        let files = (try? FileManager.default.contentsOfDirectory(at: backupDir, includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
    }

    func backupList() -> [[String: String]] {
        backupFiles().compactMap { url in
            guard let w = readWrapper(url) else { return nil }
            let created = Date(timeIntervalSince1970: (w["created"] as? Double) ?? 0)
            return [
                "id": url.lastPathComponent,
                "when": Self.displayStamp.string(from: created),
                "reason": (w["reason"] as? String) ?? "",
                "label": (w["label"] as? String) ?? ""
            ]
        }
    }

    func backupData(_ id: String) -> String? {
        let url = backupDir.appendingPathComponent((id as NSString).lastPathComponent)
        return readWrapper(url)?["data"] as? String
    }

    private func readWrapper(_ url: URL) -> [String: Any]? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    private static let fileStamp: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyyMMdd-HHmmss"; return f
    }()
    private static let displayStamp: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "EEE d MMM, h:mm:ss a"; return f
    }()

    // MARK: Page start-up

    /// A string written as a JavaScript literal.
    static func jsLiteral(_ text: String?) -> String {
        guard let text,
              let data = try? JSONEncoder().encode(text),
              let literal = String(data: data, encoding: .utf8) else { return "null" }
        return literal
    }

    /// Runs before the page's own code: restores the saved data if the page has none, and sends
    /// every save back to the app.
    func bootScript() -> String {
        """
        (function(){
          var K='\(Self.storageKey)', saved=\(Self.jsLiteral(load()));
          // Restore from the app's saved file only when the page has nothing (first run, or web storage cleared).
          try { if (saved !== null && !localStorage.getItem(K)) localStorage.setItem(K, saved); } catch (e) {}
          var orig = Storage.prototype.setItem, timer = null;
          Storage.prototype.setItem = function(k, v) {
            orig.call(this, k, v);
            if (k === K) {
              clearTimeout(timer);
              timer = setTimeout(function(){
                try { window.webkit.messageHandlers.rs.postMessage({type:'save', data:String(v)}); } catch (e) {}
              }, 250);
            }
          };
        })();
        """
    }
}
