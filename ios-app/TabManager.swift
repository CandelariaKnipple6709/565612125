import Foundation
import WebKit
import Combine

/// Owns every open tab, the shared WKWebsiteDataStore (so cookies/login
/// state/proxy are consistent across tabs, like a real browser), and the
/// camswap/privacy configuration that gets (re)applied to each tab.
final class TabManager: ObservableObject {
    @Published var tabs: [BrowserTab] = []
    @Published var activeTabID: UUID?

    /// Shared across every tab's WKWebViewConfiguration so cookies and
    /// the proxy setting apply consistently no matter which tab is
    /// active — this mirrors how Safari/Chrome share one cookie jar
    /// across tabs unless you're in a private/incognito tab.
    private let websiteDataStore = WKWebsiteDataStore.default()

    var activeTab: BrowserTab? {
        tabs.first { $0.id == activeTabID }
    }

    private var cancellables = Set<AnyCancellable>()
    /// Forwards each tab's own @Published changes (isLoading,
    /// currentURLString, statusText, etc.) into TabManager's own
    /// objectWillChange. Without this, SwiftUI views that only hold
    /// @StateObject var tabManager (not a direct @ObservedObject on the
    /// active BrowserTab) would never re-render when e.g. the address
    /// bar's URL or the loading spinner changes on the active tab.
    private var tabObservers: [UUID: AnyCancellable] = [:]

    init() {
        // Deliberately not reloading any tabs once this finishes. Doing
        // so used to force-reload every open tab the instant the ad/
        // tracker blocklists finished compiling — including whatever the
        // user was actively doing right then (e.g. a streaming site
        // mid-way through requesting camera permission), which silently
        // blanked the page and restarted the camswap signaling connection
        // from scratch. Content rule lists only need to be attached
        // before a page's OWN load starts to matter, so it's enough that
        // they're ready in ContentBlockerManager for the next real
        // navigation/reload to pick up — no callback needed here at all.
        ContentBlockerManager.shared.compileIfNeeded {}
        newTab(activate: true)
    }

    // MARK: - tab lifecycle

    @discardableResult
    func newTab(activate: Bool = true) -> BrowserTab {
        let tab = BrowserTab(configuration: makeWebViewConfiguration())
        tabs.append(tab)
        tabObservers[tab.id] = tab.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
        if activate {
            activeTabID = tab.id
        }
        applyCamswapConfig(to: tab)
        return tab
    }

    func closeTab(_ tab: BrowserTab) {
        guard let idx = tabs.firstIndex(where: { $0.id == tab.id }) else { return }
        tabs.remove(at: idx)
        tabObservers[tab.id] = nil
        if activeTabID == tab.id {
            if tabs.isEmpty {
                newTab(activate: true)
            } else {
                activeTabID = tabs[max(0, idx - 1)].id
            }
        }
    }

    func selectTab(_ tab: BrowserTab) {
        activeTabID = tab.id
    }

    // MARK: - shared configuration (proxy, media, data store)

    private func makeWebViewConfiguration() -> WKWebViewConfiguration {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        config.allowsPictureInPictureMediaPlayback = false
        config.websiteDataStore = websiteDataStore
        applyProxyConfiguration()
        return config
    }

    /// Applies (or clears) the optional HTTP proxy on the shared website
    /// data store. Safe to call repeatedly — e.g. every time the user
    /// edits the proxy settings — since it just replaces the array.
    ///
    /// Uses WKWebsiteDataStore.proxyConfigurations, added in iOS 17 as
    /// part of the Network framework's ProxyConfiguration API. This is
    /// the newest/least-battle-tested API in the app: if a future SDK
    /// changes its shape, this is the first place to check a build log.
    func applyProxyConfiguration() {
        if #available(iOS 17.0, *) {
            if let proxy = ProxySettings.shared.makeProxyConfiguration() {
                websiteDataStore.proxyConfigurations = [proxy]
            } else {
                websiteDataStore.proxyConfigurations = []
            }
        }
    }

    // MARK: - camswap config (applies to every tab — the substituted

    func applyCamswapConfig(to tab: BrowserTab) {
        tab.applyCamswapConfig(
            serverUrl: UserDefaults.standard.string(forKey: "camswap.serverUrl") ?? "",
            room: UserDefaults.standard.string(forKey: "camswap.room") ?? "",
            showStatusBadge: UserDefaults.standard.object(forKey: "camswap.showBadge") as? Bool ?? true
        )
    }

    func applyCamswapConfigToAllTabs(serverUrl: String, room: String, showStatusBadge: Bool) {
        for tab in tabs {
            tab.applyCamswapConfig(serverUrl: serverUrl, room: room, showStatusBadge: showStatusBadge)
            if !tab.isHome {
                tab.reload()
            }
        }
    }

    // MARK: - privacy

    func reapplyPrivacyToAllTabs() {
        for tab in tabs {
            tab.applyPrivacyScripts()
        }
    }

    // MARK: - clear everything

    /// Wipes ALL website data (cookies, cache, localStorage, IndexedDB,
    /// service workers — every WKWebsiteDataType, for all time) and the
    /// local History list. Bookmarks are a completely separate store
    /// (BookmarkStore) and are never touched here, on purpose.
    func clearAllBrowsingData(completion: @escaping () -> Void) {
        let types = WKWebsiteDataStore.allWebsiteDataTypes()
        websiteDataStore.removeData(ofTypes: types, modifiedSince: .distantPast) { [weak self] in
            HistoryStore.shared.clearAll()
            self?.tabs.forEach { $0.goHome() }
            DispatchQueue.main.async { completion() }
        }
    }
}
