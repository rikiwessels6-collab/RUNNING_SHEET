import UIKit
import WebKit

/// Turns the over-rate report HTML into an A4 PDF, page by page, entirely on the device.
@MainActor
final class PDFMaker: NSObject, WKNavigationDelegate {
    private var web: WKWebView?
    private var completion: ((Data?) -> Void)?

    /// A4 in points, with 12 mm margins.
    private let paper = CGRect(x: 0, y: 0, width: 595.2, height: 841.8)
    private let margin: CGFloat = 34

    func make(html: String, in host: UIView, completion: @escaping (Data?) -> Void) {
        self.completion = completion
        // The page has to be in the view hierarchy to lay out properly, so park it off screen.
        let printableWidth = paper.width - margin * 2
        let web = WKWebView(frame: CGRect(x: -4000, y: 0, width: printableWidth, height: paper.height - margin * 2))
        web.isHidden = false
        web.alpha = 0.01
        web.navigationDelegate = self
        host.addSubview(web)
        self.web = web
        web.loadHTMLString(html, baseURL: nil)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in self?.render() }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { finish(nil) }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { finish(nil) }

    private func render() {
        guard let web else { finish(nil); return }
        let renderer = UIPrintPageRenderer()
        renderer.addPrintFormatter(web.viewPrintFormatter(), startingAtPageAt: 0)
        renderer.setValue(NSValue(cgRect: paper), forKey: "paperRect")
        renderer.setValue(NSValue(cgRect: paper.insetBy(dx: margin, dy: margin)), forKey: "printableRect")

        let data = NSMutableData()
        UIGraphicsBeginPDFContextToData(data, paper, nil)
        let pages = renderer.numberOfPages
        renderer.prepare(forDrawingPages: NSRange(location: 0, length: pages))
        for page in 0..<pages {
            UIGraphicsBeginPDFPage()
            renderer.drawPage(at: page, in: UIGraphicsGetPDFContextBounds())
        }
        UIGraphicsEndPDFContext()
        finish(pages > 0 ? data as Data : nil)
    }

    private func finish(_ data: Data?) {
        web?.removeFromSuperview()
        web = nil
        let done = completion
        completion = nil
        done?(data)
    }
}
