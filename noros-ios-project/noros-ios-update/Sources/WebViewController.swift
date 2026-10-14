import UIKit
import WebKit
import LocalAuthentication

/// Отдаёт файлы из папки web внутри приложения по адресу app://noros/... (стабильный origin, работает localStorage).
final class BundleSchemeHandler: NSObject, WKURLSchemeHandler {
    private let root: URL
    init(root: URL) { self.root = root }
    private func mime(_ ext: String) -> String {
        switch ext.lowercased() {
        case "html": return "text/html; charset=utf-8"
        case "js": return "text/javascript; charset=utf-8"
        case "css": return "text/css; charset=utf-8"
        case "json": return "application/json"
        case "png": return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        case "svg": return "image/svg+xml"
        case "woff2": return "font/woff2"
        default: return "application/octet-stream"
        }
    }
    func webView(_ webView: WKWebView, start task: WKURLSchemeTask) {
        guard let url = task.request.url else { task.didFailWithError(URLError(.badURL)); return }
        var p = url.path; if p.isEmpty || p == "/" { p = "/index.html" }
        let file = root.appendingPathComponent(String(p.dropFirst()))
        guard let data = try? Data(contentsOf: file) else { task.didFailWithError(URLError(.fileDoesNotExist)); return }
        let resp = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": mime(file.pathExtension), "Content-Length": "\(data.count)", "Cache-Control": "no-cache"])!
        task.didReceive(resp); task.didReceive(data); task.didFinish()
    }
    func webView(_ webView: WKWebView, stop task: WKURLSchemeTask) {}
}

final class WebViewController: UIViewController, WKScriptMessageHandler, WKNavigationDelegate, WKUIDelegate {
    private var web: WKWebView!

    // Мост NorosApp: тот же интерфейс, что и в Android-версии (open / save / icon).
    private var bioKind: String {
        let c = LAContext(); var e: NSError?
        guard c.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &e) else { return "none" }
        return c.biometryType == .faceID ? "faceid" : (c.biometryType == .touchID ? "touchid" : "none")
    }
    private var bridgeJS: String { """
    (function(){
      window.NOROS_NATIVE_IOS = 1; window.__nrNoLive = 1; window.NOROS_BIO = '\(bioKind)';
      function post(o){ try{ window.webkit.messageHandlers.noros.postMessage(o); return 'ok'; }catch(e){ return String(e); } }
      window.NorosApp = {
        open: function(u){ return post({a:'open', u:String(u)}); },
        save: function(n,m,b){ return post({a:'save', n:String(n), m:String(m), b:String(b)}); },
        icon: function(on,off){ return post({a:'icon', on:String(on||'')}); },
        bio: function(r){ return post({a:'bio', r:String(r||'')}); }
      };
    })();
    """ }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(red: 0.04, green: 0.04, blue: 0.06, alpha: 1)
        let cfg = WKWebViewConfiguration()
        cfg.allowsInlineMediaPlayback = true
        cfg.userContentController.add(self, name: "noros")
        cfg.userContentController.addUserScript(WKUserScript(source: bridgeJS, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        let root = Bundle.main.resourceURL!.appendingPathComponent("web")
        cfg.setURLSchemeHandler(BundleSchemeHandler(root: root), forURLScheme: "app")
        web = WKWebView(frame: view.bounds, configuration: cfg)
        web.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        web.navigationDelegate = self
        web.uiDelegate = self
        web.scrollView.contentInsetAdjustmentBehavior = .never
        web.scrollView.bounces = false
        web.isOpaque = false
        web.backgroundColor = view.backgroundColor
        web.scrollView.backgroundColor = view.backgroundColor
        if #available(iOS 16.4, *) { web.isInspectable = true }
        view.addSubview(web)
        NotificationCenter.default.addObserver(forName: UIApplication.willResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            self?.web.evaluateJavaScript("window.NRlock&&NRlock.resign&&NRlock.resign()", completionHandler: nil)
        }
        web.load(URLRequest(url: URL(string: "app://noros/index.html")!))
    }

    override var prefersStatusBarHidden: Bool { false }
    override var preferredStatusBarStyle: UIStatusBarStyle { .lightContent }

    // MARK: JS → нативный код
    func userContentController(_ ucc: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let d = message.body as? [String: Any], let a = d["a"] as? String else { return }
        switch a {
        case "open":
            if let s = d["u"] as? String, let u = URL(string: s) { UIApplication.shared.open(u, options: [:], completionHandler: nil) }
        case "save":
            if let n = d["n"] as? String, let b = d["b"] as? String, let data = Data(base64Encoded: b) { share(name: n, data: data) }
        case "bio":
            let ctx = LAContext(); var err: NSError?
            let reason = (d["r"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "Вход в приложение"
            guard ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &err) else { self.bioResult(false); return }
            ctx.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason) { ok, _ in DispatchQueue.main.async { self.bioResult(ok) } }
        case "icon":
            let n = (d["on"] as? String ?? "").components(separatedBy: ".").last ?? ""
            let alt: String? = (n == "IcDark" || n == "IcRio") ? n : nil   // IcLight = основная иконка Noros
            guard UIApplication.shared.supportsAlternateIcons else { return }
            if UIApplication.shared.alternateIconName != alt { UIApplication.shared.setAlternateIconName(alt, completionHandler: nil) }
        default: break
        }
    }

    private func bioResult(_ ok: Bool) { web.evaluateJavaScript("window.__nrBio&&window.__nrBio(\(ok ? "true" : "false"))", completionHandler: nil) }

    private func share(name: String, data: Data) {
        let safe = name.replacingOccurrences(of: "/", with: "_")
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(safe)
        do { try data.write(to: url, options: .atomic) } catch { return }
        let vc = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        vc.popoverPresentationController?.sourceView = view
        vc.popoverPresentationController?.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.maxY - 40, width: 1, height: 1)
        present(vc, animated: true)
    }

    // MARK: навигация: внешние ссылки — в системе, iframe (личные кабинеты) — внутри
    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = action.request.url else { decisionHandler(.allow); return }
        let scheme = url.scheme?.lowercased() ?? ""
        let isMain = action.targetFrame?.isMainFrame ?? true
        if isMain && ["http", "https", "tg", "mailto", "tel"].contains(scheme) {
            UIApplication.shared.open(url, options: [:], completionHandler: nil)
            decisionHandler(.cancel); return
        }
        decisionHandler(.allow)
    }
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for action: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let u = action.request.url { UIApplication.shared.open(u, options: [:], completionHandler: nil) }
        return nil
    }
    // JS-диалоги (alert/confirm) — нативные
    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
        let a = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        a.addAction(UIAlertAction(title: "OK", style: .default) { _ in completionHandler() }); present(a, animated: true)
    }
    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
        let a = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        a.addAction(UIAlertAction(title: "OK", style: .default) { _ in completionHandler(true) })
        a.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in completionHandler(false) }); present(a, animated: true)
    }
}
