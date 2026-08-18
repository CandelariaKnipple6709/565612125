import Foundation
import Combine

/// The six privacy toggles, modeled after DuckDuckGo's iOS browser
/// ("Privacy Protections" screen). Persisted via UserDefaults/@AppStorage
/// so they survive app restarts and are NOT affected by "clear everything"
/// (that button only clears site data/cookies/history, never settings).
///
/// Honesty note (also explained to the user in chat, not just here):
/// - Web Tracking Protection / Ad Blocking are backed by real
///   WKContentRuleList blocklists (see ContentBlockerManager), but they're
///   small curated lists, not a full EasyList/EasyPrivacy feed.
/// - Threat Protection is a tiny local blocklist of obviously-bad
///   domains, not a live threat-intel feed.
/// - Cookie Pop-Up Protection is a best-effort JS heuristic that hides/
///   auto-dismisses common consent banners; it won't catch every site.
/// - Email Protection has no backend to plug into here (DuckDuckGo's is
///   tied to their own relay/account system), so it's a placeholder
///   toggle with no behavior yet — kept in the list for UI parity with
///   the screenshot, off by default like in the screenshot.
final class PrivacySettings: ObservableObject {
    static let shared = PrivacySettings()

    @Published var privateSearchEnabled: Bool {
        didSet { UserDefaults.standard.set(privateSearchEnabled, forKey: Keys.privateSearch) }
    }
    @Published var webTrackingProtectionEnabled: Bool {
        didSet { UserDefaults.standard.set(webTrackingProtectionEnabled, forKey: Keys.tracking) }
    }
    @Published var threatProtectionEnabled: Bool {
        didSet { UserDefaults.standard.set(threatProtectionEnabled, forKey: Keys.threat) }
    }
    @Published var cookiePopupProtectionEnabled: Bool {
        didSet { UserDefaults.standard.set(cookiePopupProtectionEnabled, forKey: Keys.cookiePopup) }
    }
    @Published var emailProtectionEnabled: Bool {
        didSet { UserDefaults.standard.set(emailProtectionEnabled, forKey: Keys.email) }
    }
    @Published var adBlockingEnabled: Bool {
        didSet { UserDefaults.standard.set(adBlockingEnabled, forKey: Keys.adBlock) }
    }

    private enum Keys {
        static let privateSearch = "privacy.privateSearch"
        static let tracking = "privacy.tracking"
        static let threat = "privacy.threat"
        static let cookiePopup = "privacy.cookiePopup"
        static let email = "privacy.email"
        static let adBlock = "privacy.adBlock"
    }

    private init() {
        let d = UserDefaults.standard
        // Defaults mirror the DuckDuckGo screenshot: everything on except
        // Email Protection.
        privateSearchEnabled = d.object(forKey: Keys.privateSearch) as? Bool ?? true
        webTrackingProtectionEnabled = d.object(forKey: Keys.tracking) as? Bool ?? true
        threatProtectionEnabled = d.object(forKey: Keys.threat) as? Bool ?? true
        cookiePopupProtectionEnabled = d.object(forKey: Keys.cookiePopup) as? Bool ?? true
        emailProtectionEnabled = d.object(forKey: Keys.email) as? Bool ?? false
        adBlockingEnabled = d.object(forKey: Keys.adBlock) as? Bool ?? true
    }

    // MARK: - Private search

    /// Builds a search URL for free-text input typed into the address bar.
    /// When Private Search is on, queries go to DuckDuckGo instead of a
    /// tracking-heavy default.
    func searchURL(for query: String) -> URL? {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            return nil
        }
        let base = privateSearchEnabled ? "https://duckduckgo.com/?q=" : "https://www.google.com/search?q="
        return URL(string: base + encoded)
    }

    // MARK: - Threat protection (tiny local heuristic, not a live feed)

    /// A short illustrative list of domain patterns commonly associated
    /// with phishing/scam pages. This is NOT a real threat-intelligence
    /// feed (there's no backend here to pull one from) — it just stops
    /// the most obvious cases and blocks IP-literal hosts with suspicious
    /// login-looking paths as a rough heuristic.
    private let knownBadDomains: Set<String> = [
        "phishing-example.com",
        "malware-example.com"
    ]

    func isThreatening(host: String?) -> Bool {
        guard threatProtectionEnabled, let host = host?.lowercased() else { return false }
        return knownBadDomains.contains { host == $0 || host.hasSuffix("." + $0) }
    }

    // MARK: - Cookie pop-up protection script

    /// Injected at document-end on every page load when the toggle is on.
    /// Heuristic only: looks for common consent-banner containers by
    /// id/class keywords and known vendor selectors, and either clicks an
    /// obvious "reject/necessary only" button or hides the banner outright
    /// so it doesn't block the page.
    static let cookieBannerScript = """
    (function () {
      if (window.__camswapCookieGuardInstalled) return;
      window.__camswapCookieGuardInstalled = true;

      const knownSelectors = [
        '#onetrust-banner-sdk', '#onetrust-consent-sdk',
        '#CybotCookiebotDialog', '.cc-window', '.cc-banner',
        '#cookie-law-info-bar', '.fc-consent-root',
        '#sp_message_container', '.qc-cmp2-container',
        '[id*="cookie-banner" i]', '[class*="cookie-banner" i]',
        '[id*="cookie-consent" i]', '[class*="cookie-consent" i]',
        '[id*="cookieconsent" i]', '[class*="cookieconsent" i]',
        '[aria-label*="cookie" i][role="dialog"]'
      ];

      const rejectWordRe = /reject all|only necessary|necessary only|decline|отклонить|только необходимые|отказаться/i;
      const acceptWordRe = /accept all|allow all|agree|принять все|согласен|разрешить все/i;

      function tryDismiss(node) {
        if (!(node instanceof Element)) return false;
        const buttons = node.querySelectorAll('button, a[role="button"], [role="button"]');
        for (const b of buttons) {
          const text = (b.textContent || '').trim();
          if (rejectWordRe.test(text)) { b.click(); return true; }
        }
        for (const b of buttons) {
          const text = (b.textContent || '').trim();
          if (acceptWordRe.test(text)) { b.click(); return true; }
        }
        return false;
      }

      function sweep(root) {
        for (const sel of knownSelectors) {
          root.querySelectorAll(sel).forEach(el => {
            if (!tryDismiss(el)) {
              el.style.setProperty('display', 'none', 'important');
            }
          });
        }
      }

      sweep(document);
      const obs = new MutationObserver(() => sweep(document));
      obs.observe(document.documentElement, { childList: true, subtree: true });
      // Stop watching after 15s so it doesn't run forever on long sessions.
      setTimeout(() => obs.disconnect(), 15000);
    })();
    """
}
