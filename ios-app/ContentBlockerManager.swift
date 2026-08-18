import Foundation
import WebKit

/// Compiles two small WKContentRuleLists — one for ad domains, one for
/// tracker domains — once, and hands back cached WKContentRuleList
/// objects to attach/detach from a tab's userContentController depending
/// on the Ad Blocking / Web Tracking Protection toggles.
///
/// These are curated, short lists of well-known domains, not a full
/// EasyList/EasyPrivacy import — good enough to visibly cut down on the
/// most common ad networks and trackers without shipping a large
/// third-party list file.
final class ContentBlockerManager {
    static let shared = ContentBlockerManager()

    private let adBlockIdentifier = "camswap.adblock.v1"
    private let trackingBlockIdentifier = "camswap.trackingblock.v1"

    private(set) var adBlockList: WKContentRuleList?
    private(set) var trackingBlockList: WKContentRuleList?

    private let adDomains = [
        "doubleclick.net", "googlesyndication.com", "googleadservices.com",
        "adnxs.com", "adsrvr.org", "advertising.com", "adform.net",
        "criteo.com", "criteo.net", "outbrain.com", "taboola.com",
        "pubmatic.com", "rubiconproject.com", "openx.net", "media.net",
        "moatads.com", "serving-sys.com", "yieldmo.com", "smartadserver.com"
    ]

    private let trackerDomains = [
        "google-analytics.com", "googletagmanager.com", "googletagservices.com",
        "facebook.net", "connect.facebook.net", "hotjar.com", "mixpanel.com",
        "segment.io", "segment.com", "amplitude.com", "fullstory.com",
        "mouseflow.com", "yandex.ru/clck", "mc.yandex.ru", "scorecardresearch.com",
        "quantserve.com", "chartbeat.com", "newrelic.com", "nr-data.net",
        "branch.io", "adjust.com", "appsflyer.com"
    ]

    private init() {}

    /// Compiles both lists (idempotent — WKContentRuleListStore caches by
    /// identifier so repeated calls across launches are cheap) and calls
    /// back on the main thread once both are ready.
    func compileIfNeeded(completion: @escaping () -> Void) {
        let group = DispatchGroup()

        group.enter()
        compile(identifier: adBlockIdentifier, domains: adDomains) { [weak self] list in
            self?.adBlockList = list
            group.leave()
        }

        group.enter()
        compile(identifier: trackingBlockIdentifier, domains: trackerDomains) { [weak self] list in
            self?.trackingBlockList = list
            group.leave()
        }

        group.notify(queue: .main, execute: completion)
    }

    private func compile(identifier: String, domains: [String], done: @escaping (WKContentRuleList?) -> Void) {
        let rules = domains.map { domain -> [String: Any] in
            [
                "trigger": ["url-filter": ".*\(NSRegularExpression.escapedPattern(for: domain)).*"],
                "action": ["type": "block"]
            ]
        }
        guard let data = try? JSONSerialization.data(withJSONObject: rules, options: []),
              let json = String(data: data, encoding: .utf8) else {
            done(nil)
            return
        }
        WKContentRuleListStore.default().compileContentRuleList(
            forIdentifier: identifier,
            encodedContentRuleList: json
        ) { list, error in
            if let error = error {
                print("[camswap] content rule list compile failed (\(identifier)):", error)
            }
            done(list)
        }
    }
}
