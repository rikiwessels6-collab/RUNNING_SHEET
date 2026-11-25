import SwiftUI
import WebKit
import MessageUI

struct SheetView: UIViewRepresentable {
    @ObservedObject var model: SheetModel

    func makeCoordinator() -> Coordinator { Coordinator(model: model) }

    func makeUIView(context: Context) -> WKWebView {
        let controller = WKUserContentController()
        controller.add(context.coordinator, name: "rs")
        controller.addUserScript(WKUserScript(source: model.bootScript(),
                                              injectionTime: .atDocumentStart,
                                              forMainFrameOnly: true))
        let config = WKWebViewConfiguration()
        config.userContentController = controller
        config.websiteDataStore = .default()

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.isInspectable = true
        webView.allowsBackForwardNavigationGestures = false
        model.webView = webView
        context.coordinator.webView = webView
        context.coordinator.startBattery()

        if let url = Self.sheetURL() {
            webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        } else {
            webView.loadHTMLString("<h2 style='font-family:-apple-system;padding:40px'>running-sheet.html is missing from the Resources folder.</h2>", baseURL: nil)
        }
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    static func sheetURL() -> URL? {
        Bundle.main.url(forResource: "running-sheet", withExtension: "html")
    }

    // MARK: - Messages from the sheet (save, share, PDF, print) and link handling

    @MainActor
    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate, WKUIDelegate {
        let model: SheetModel
        weak var webView: WKWebView?
        private var pdfMaker: PDFMaker?
        private var dlsScanner: DLSScanner?
        private let mailDelegate = MailDelegate()

        init(model: SheetModel) { self.model = model }

        func userContentController(_ userContentController: WKUserContentController,
                                   didReceive message: WKScriptMessage) {
            guard let body = message.body as? [String: Any],
                  let type = body["type"] as? String else { return }
            switch type {
            case "save":
                if let data = body["data"] as? String { model.save(data) }
            case "text":
                if let text = body["text"] as? String { share([text]) }
            case "file":
                let name = (body["name"] as? String) ?? "running-sheet.json"
                let text = (body["text"] as? String) ?? ""
                if let url = writeTemp(name: name, data: Data(text.utf8)) { share([url]) }
            case "pdf":
                let name = (body["name"] as? String) ?? "Over-Rate Report.pdf"
                let html = (body["html"] as? String) ?? ""
                makePDF(html: html, name: name) { [weak self] url in self?.share([url]) }
            case "pdfmail":
                let name = (body["name"] as? String) ?? "Over-Rate Report.pdf"
                let html = (body["html"] as? String) ?? ""
                let to = (body["to"] as? [String]) ?? []
                let cc = (body["cc"] as? [String]) ?? []
                let subject = (body["subject"] as? String) ?? ""
                let text = (body["body"] as? String) ?? ""
                makePDF(html: html, name: name) { [weak self] url in
                    self?.mail(url, to: to, cc: cc, subject: subject, body: text)
                }
            case "dlsPhoto":
                scanDLS(source: (body["source"] as? String) ?? "camera")
            case "print":
                printSheet()
            case "snapshot":
                if let data = body["data"] as? String {
                    model.snapshot(data, reason: (body["reason"] as? String) ?? "", label: (body["label"] as? String) ?? "")
                }
            case "listBackups":
                sendBackups()
            case "export":
                let name = (body["name"] as? String) ?? "Running sheet.json"
                let text = (body["text"] as? String) ?? ""
                if let url = writeTemp(name: name, data: Data(text.utf8)), let presenter = topController() {
                    // Save straight into Files / iCloud Drive
                    let picker = UIDocumentPickerViewController(forExporting: [url], asCopy: true)
                    presenter.present(picker, animated: true)
                }
            case "restore":
                if let id = body["id"] as? String { restore(id) }
            default:
                break
            }
        }

        private func makePDF(html: String, name: String, then: @escaping (URL) -> Void) {
            guard let host = webView else { return }
            let maker = PDFMaker()
            pdfMaker = maker
            maker.make(html: html, in: host) { [weak self] data in
                guard let self else { return }
                self.pdfMaker = nil
                guard let data, let url = self.writeTemp(name: name, data: data) else {
                    self.alert("Couldn't make the PDF. Try again, or use “Print this page”.")
                    return
                }
                then(url)
            }
        }

        private func scanDLS(source: String) {
            guard let presenter = topController() else { return }
            let scanner = DLSScanner()
            dlsScanner = scanner
            scanner.start(source: source, from: presenter) { [weak self] result in
                self?.dlsScanner = nil
                guard let result,
                      let data = try? JSONSerialization.data(withJSONObject: result),
                      let json = String(data: data, encoding: .utf8) else { return }
                self?.webView?.evaluateJavaScript("window.__rsDlsScan && window.__rsDlsScan(\(json))", completionHandler: nil)
            }
        }

        /// Opens Mail with the report attached and the details filled in (share sheet if Mail isn't set up).
        private func mail(_ url: URL, to: [String], cc: [String], subject: String, body: String) {
            guard MFMailComposeViewController.canSendMail(), let presenter = topController() else {
                share([url]); return
            }
            let composer = MFMailComposeViewController()
            composer.mailComposeDelegate = mailDelegate
            composer.setToRecipients(to)
            composer.setCcRecipients(cc)
            composer.setSubject(subject)
            composer.setMessageBody(body, isHTML: false)
            if let data = try? Data(contentsOf: url) {
                composer.addAttachmentData(data, mimeType: "application/pdf", fileName: url.lastPathComponent)
            }
            presenter.present(composer, animated: true)
        }

        // MARK: Battery – warns in the sheet below 20% when not charging

        func startBattery() {
            UIDevice.current.isBatteryMonitoringEnabled = true
            NotificationCenter.default.addObserver(self, selector: #selector(batteryChanged),
                                                   name: UIDevice.batteryLevelDidChangeNotification, object: nil)
            NotificationCenter.default.addObserver(self, selector: #selector(batteryChanged),
                                                   name: UIDevice.batteryStateDidChangeNotification, object: nil)
        }

        @objc private func batteryChanged() { sendBattery() }

        private func sendBattery() {
            let device = UIDevice.current
            let charging = device.batteryState == .charging || device.batteryState == .full
            webView?.evaluateJavaScript("window.__rsBattery && window.__rsBattery(\(device.batteryLevel), \(charging))", completionHandler: nil)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            sendBattery()
        }

        private func sendBackups() {
            let list = model.backupList()
            guard let data = try? JSONSerialization.data(withJSONObject: list),
                  let json = String(data: data, encoding: .utf8) else { return }
            webView?.evaluateJavaScript("window.__rsBackups && window.__rsBackups(\(json))", completionHandler: nil)
        }

        private func restore(_ id: String) {
            guard let data = model.backupData(id) else {
                alert("That backup couldn't be read."); return
            }
            if let current = model.load() { model.snapshot(current, reason: "before restore", label: "") }
            model.save(data)
            let js = "localStorage.setItem('\(SheetModel.storageKey)', \(SheetModel.jsLiteral(data))); location.reload();"
            webView?.evaluateJavaScript(js, completionHandler: nil)
        }

        private func printSheet() {
            guard let webView else { return }
            let info = UIPrintInfo(dictionary: nil)
            info.outputType = .general
            info.jobName = "WBBL Running Sheet"
            let pc = UIPrintInteractionController.shared
            pc.printInfo = info
            pc.printFormatter = webView.viewPrintFormatter()
            if UIDevice.current.userInterfaceIdiom == .pad {
                pc.present(from: anchorRect(), in: webView, animated: true, completionHandler: nil)
            } else {
                pc.present(animated: true, completionHandler: nil)
            }
        }

        private func writeTemp(name: String, data: Data) -> URL? {
            let safe = name.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(safe)
            do { try data.write(to: url, options: .atomic); return url } catch { return nil }
        }

        private func share(_ items: [Any]) {
            guard let webView, let presenter = topController() else { return }
            let sheet = UIActivityViewController(activityItems: items, applicationActivities: nil)
            if let pop = sheet.popoverPresentationController {
                pop.sourceView = webView
                pop.sourceRect = anchorRect()
            }
            presenter.present(sheet, animated: true)
        }

        private func alert(_ text: String) {
            let a = UIAlertController(title: nil, message: text, preferredStyle: .alert)
            a.addAction(UIAlertAction(title: "OK", style: .default))
            topController()?.present(a, animated: true)
        }

        private func anchorRect() -> CGRect {
            guard let webView else { return .zero }
            return CGRect(x: webView.bounds.midX, y: webView.safeAreaInsets.top + 60, width: 1, height: 1)
        }

        private func topController() -> UIViewController? {
            var vc = webView?.window?.rootViewController
            while let presented = vc?.presentedViewController { vc = presented }
            return vc
        }

        // Links: keep the sheet in the app, send mail / web links to the right app.
        func webView(_ webView: WKWebView,
                     decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
            guard let url = navigationAction.request.url, let scheme = url.scheme?.lowercased() else { return .allow }
            if ["file", "about", "blob", "data"].contains(scheme) { return .allow }
            _ = await UIApplication.shared.open(url)
            return .cancel
        }

        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                     for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            if let url = navigationAction.request.url, url.scheme != "about" { UIApplication.shared.open(url) }
            return nil
        }

        // If the web content process is ever killed (memory pressure), reload – data comes back from the saved file.
        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            webView.reload()
        }
    }
}

/// Closes the Mail screen when it's sent or cancelled.
final class MailDelegate: NSObject, MFMailComposeViewControllerDelegate {
    func mailComposeController(_ controller: MFMailComposeViewController,
                               didFinishWith result: MFMailComposeResult, error: Error?) {
        controller.dismiss(animated: true)
    }
}
