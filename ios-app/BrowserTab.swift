import Foundation
import WebKit
import Combine
import UIKit

/// The camswap connection/video state, mirrored from the injected JS
/// (camswap.js posts {kind, text} to the native "camswapStatus" message
/// handler on every status change — see BrowserTab.userContentController
/// below). Drives the small colored status dot in the bottom bar
/// (ContentView) instead of the old in-page debug badge.
enum CamswapConnectionState: Equatable {
    /// Nothing configured yet, or the tab hasn't loaded a page that runs
    /// the script (e.g. the home screen).
    case idle
    /// Signaling WebSocket connecting, or connected and waiting in the
    /// room for the studio to start publishing.
    case connecting
    /// The signaling connection dropped and is retrying.
    case reconnecting
    /// WebRTC video is actually flowing — the substituted camera is live.
    case connected
    case error

    init(jsKind: String) {
        switch jsKind {
        case "connecting": self = .connecting
        case "reconnecting": self = .reconnecting
        case "connected": self = .connected
        case "error": self = .error
        default: self = .idle
        }
    }
}

/// WKUserContentController retains its message handlers strongly. Adding
/// `self` (a BrowserTab) directly as a handler would create a
/// BrowserTab -> webView -> configuration -> userContentController ->
/// BrowserTab retain cycle, the same leak WKWebView is notorious for.
/// This weak proxy is the standard fix: the controller retains the
/// proxy instead, and the proxy only holds a weak reference back.
private final class WeakScriptMessageHandler: NSObject, WKScriptMessageHandler {
    weak var target: WKScriptMessageHandler?
    init(target: WKScriptMessageHandler) { self.target = target }
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        target?.userContentController(userContentController, didReceive: message)
    }
}

/// One browser tab: owns its own WKWebView, tracks loading/URL/title
/// state for the UI, and knows how to (re)inject the camswap
/// camera-substitution script plus the active privacy protections into
/// itself. Every tab shares the same WKWebsiteDataStore (via
/// TabManager.sharedWebsiteDataStore) so cookies/proxy/login state are
/// consistent across tabs, like a normal browser.
final class BrowserTab: NSObject, ObservableObject, Identifiable, WKNavigationDelegate, WKScriptMessageHandler {
    let id = UUID()

    @Published var isLoading: Bool = false
    @Published var currentURLString: String = ""
    @Published var title: String = "Новая вкладка"
    @Published var statusText: String = "не настроено"
    @Published var isHome: Bool = true
    @Published var snapshot: UIImage?
    @Published var blockedThreat: String?
    @Published var camswapState: CamswapConnectionState = .idle

    let webView: WKWebView

    // Cached so a privacy-only toggle change (applyPrivacyScripts) can
    // fully rebuild the user-script set from scratch without needing the
    // caller to re-pass the camswap server/room/badge every time.
    private var lastServerUrl: String = ""
    private var lastRoom: String = ""
    private var lastVideoWidth: Int = 1280
    private var lastVideoHeight: Int = 720
    private var lastFPS: Int = 30
    private var lastShowStatusBadge: Bool = false

    /// Real Safari's user agent on iOS includes a "Version/X.Y.Z Safari/604.1"
    /// token that WKWebView does NOT add by default — without it, some sites
    /// treat the app as an unrecognized/embedded browser instead of Safari
    /// (see chat: this was asked about explicitly). Spoofing the latest
    /// Safari version (18.7.6, as reported by the user's own device) makes
    /// every tab identify itself exactly like stock Safari would.
    static let safariUserAgent =
        "Mozilla/5.0 (iPhone; CPU iPhone OS 18_7_6 like Mac OS X) AppleWebKit/605.1.15 " +
        "(KHTML, like Gecko) Version/18.7.6 Mobile/15E148 Safari/604.1"

    init(configuration: WKWebViewConfiguration) {
        webView = WKWebView(frame: .zero, configuration: configuration)
        webView.allowsBackForwardNavigationGestures = true
        webView.customUserAgent = BrowserTab.safariUserAgent
        super.init()
        webView.navigationDelegate = self
        // Registered once here (not in applyCamswapConfig, which gets
        // called repeatedly) since WKUserContentController.add(_:name:)
        // throws/asserts if the same handler name is added twice without
        // an intervening remove.
        webView.configuration.userContentController.add(
            WeakScriptMessageHandler(target: self),
            name: "camswapStatus"
        )
    }

    // MARK: - WKScriptMessageHandler

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == "camswapStatus",
              let body = message.body as? [String: Any],
              let kindRaw = body["kind"] as? String else { return }
        camswapState = CamswapConnectionState(jsKind: kindRaw)
        if let text = body["text"] as? String, !text.isEmpty {
            statusText = text
        }
    }

    // MARK: - camswap camera substitution

    /// Rebuilds the injected script set (config header + the embedded
    /// camswap.js) plus the privacy-protection scripts, then reloads so
    /// everything takes effect again from document-start.
    func applyCamswapConfig(
        serverUrl: String,
        room: String,
        videoWidth: Int = 1280,
        videoHeight: Int = 720,
        fps: Int = 30,
        showStatusBadge: Bool = false
    ) {
        lastServerUrl = serverUrl
        lastRoom = room
        lastVideoWidth = videoWidth
        lastVideoHeight = videoHeight
        lastFPS = fps
        lastShowStatusBadge = showStatusBadge

        let controller = webView.configuration.userContentController
        controller.removeAllUserScripts()

        let configJSON = """
        window.__CAMSWAP_CONFIG__ = {
          serverUrl: \(jsString(serverUrl)),
          room: \(jsString(room)),
          videoWidth: \(videoWidth),
          videoHeight: \(videoHeight),
          fps: \(fps),
          showStatusBadge: \(showStatusBadge ? "true" : "false")
        };
        """
        let configScript = WKUserScript(
            source: configJSON,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false
        )
        controller.addUserScript(configScript)

        guard let camswapSource = CamswapScript.source else {
            statusText = "ОШИБКА: не удалось декодировать встроенный camswap.js"
            return
        }
        let mainScript = WKUserScript(
            source: camswapSource,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false
        )
        controller.addUserScript(mainScript)

        appendPrivacyScripts(to: controller)

        statusText = "конфигурация применена (комната: \(room))"
    }

    /// Re-applies privacy protections only. Unlike appendPrivacyScripts,
    /// this does a FULL rebuild of the user-script set (config + camswap
    /// + privacy) using the cached camswap values, so that turning a
    /// protection OFF actually removes its script instead of just never
    /// adding a new one on top of the old one — WKUserContentController
    /// has no "remove this one script" API, only removeAllUserScripts().
    func applyPrivacyScripts() {
        applyCamswapConfig(
            serverUrl: lastServerUrl,
            room: lastRoom,
            videoWidth: lastVideoWidth,
            videoHeight: lastVideoHeight,
            fps: lastFPS,
            showStatusBadge: lastShowStatusBadge
        )
        // Reload so the rebuilt script set actually takes effect on the
        // already-loaded page (document-start scripts can't be
        // retroactively applied to a page that already parsed).
        if !isHome {
            webView.reload()
        }
    }

    /// Adds the cookie-banner-guard script and the ad/tracker
    /// WKContentRuleLists according to the current PrivacySettings, on
    /// top of whatever's already in the controller. Only safe to call
    /// right after removeAllUserScripts() (i.e. from inside
    /// applyCamswapConfig) — see applyPrivacyScripts above for the
    /// toggle-only path, which needs a full rebuild instead.
    private func appendPrivacyScripts(to controller: WKUserContentController) {
        let settings = PrivacySettings.shared

        if settings.cookiePopupProtectionEnabled {
            let script = WKUserScript(
                source: PrivacySettings.cookieBannerScript,
                injectionTime: .atDocumentEnd,
                forMainFrameOnly: false
            )
            controller.addUserScript(script)
        }

        controller.removeAllContentRuleLists()
        let blocker = ContentBlockerManager.shared
        if settings.adBlockingEnabled, let list = blocker.adBlockList {
            controller.add(list)
        }
        if settings.webTrackingProtectionEnabled, let list = blocker.trackingBlockList {
            controller.add(list)
        }
    }

    // MARK: - navigation

    func load(urlString: String) {
        var s = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.isEmpty { return }
        if !s.contains("://") {
            // Looks like a bare domain (has a dot, no spaces) -> treat as
            // URL; otherwise treat as a search query.
            let looksLikeDomain = s.contains(".") && !s.contains(" ")
            if looksLikeDomain {
                s = "https://" + s
            } else if let searchURL = PrivacySettings.shared.searchURL(for: s) {
                isHome = false
                currentURLString = searchURL.absoluteString
                webView.load(URLRequest(url: searchURL))
                return
            }
        }
        guard let url = URL(string: s) else {
            statusText = "некорректный URL: \(urlString)"
            return
        }
        isHome = false
        currentURLString = s
        webView.load(URLRequest(url: url))
    }

    func reload() {
        webView.reload()
    }

    func goHome() {
        isHome = true
        currentURLString = ""
        title = "Новая вкладка"
        webView.loadHTMLString("", baseURL: nil)
    }

    func captureSnapshot() {
        guard !isHome else { return }
        let config = WKSnapshotConfiguration()
        webView.takeSnapshot(with: config) { [weak self] image, _ in
            self?.snapshot = image
        }
    }

    // MARK: - WKNavigationDelegate

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        isLoading = true
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        if let host = navigationAction.request.url?.host, PrivacySettings.shared.isThreatening(host: host) {
            blockedThreat = host
            decisionHandler(.cancel)
            return
        }
        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        isLoading = false
        if let url = webView.url {
            currentURLString = url.absoluteString
        }
        webView.evaluateJavaScript("document.title") { [weak self] result, _ in
            guard let self = self else { return }
            let pageTitle = (result as? String) ?? self.currentURLString
            self.title = pageTitle.isEmpty ? self.currentURLString : pageTitle
            if !self.currentURLString.isEmpty {
                HistoryStore.shared.record(title: self.title, urlString: self.currentURLString)
            }
        }
        captureSnapshot()
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        isLoading = false
        statusText = "ошибка загрузки: \(error.localizedDescription)"
    }

    /// Answers HTTP proxy Basic auth challenges with the credential from
    /// ProxySettings, if any is configured. Falls through to default
    /// handling for anything else (server TLS trust, non-proxy auth).
    func webView(
        _ webView: WKWebView,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        // NOT using URLProtectionSpace.isProxy here on purpose: NSObject
        // (which URLProtectionSpace inherits from) has its own unrelated
        // `isProxy()` method (an old Objective-C runtime check for
        // NSProxy instances, always false for a normal object). On this
        // SDK that inherited method is what actually resolves when you
        // write `.isProxy` — confirmed from a real build log, where it
        // surfaced as "produces expected type 'Bool'; did you mean to
        // call it with '()'?" pointing at this exact spot. Calling it
        // would silently always return false and this proxy-auth
        // handler would never fire. `proxyType` has no such collision:
        // it's non-nil only for an actual proxy protection space, so
        // it's both unambiguous and semantically what we want here.
        let isProxyChallenge: Bool = challenge.protectionSpace.proxyType != nil
        let storedCredential: URLCredential? = ProxySettings.shared.credential

        if isProxyChallenge, let credential = storedCredential {
            completionHandler(.useCredential, credential)
            return
        }
        completionHandler(.performDefaultHandling, nil)
    }

    // MARK: - helpers

    private func jsString(_ s: String) -> String {
        let escaped = s
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }
}
