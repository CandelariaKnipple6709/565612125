import SwiftUI
import WebKit

struct ContentView: View {
    @StateObject private var tabManager = TabManager()
    @ObservedObject private var bookmarkStore = BookmarkStore.shared
    @ObservedObject private var privacy = PrivacySettings.shared

    @AppStorage("camswap.startURL") private var startURL: String = "https://your-streaming-service.example.com"
    @AppStorage("camswap.serverUrl") private var serverUrl: String = "wss://your-signaling-server.example.com"
    @AppStorage("camswap.room") private var room: String = "stream-1234"
    @AppStorage("camswap.showBadge") private var showBadge: Bool = true

    @State private var showSettings = false
    @State private var showScanner = false
    @State private var showTabSwitcher = false
    @State private var showBookmarksHistory = false
    @State private var showClearConfirm = false
    @State private var justCleared = false

    @State private var addressBarText: String = ""
    @FocusState private var addressBarFocused: Bool

    private var activeTab: BrowserTab? { tabManager.activeTab }

    var body: some View {
        VStack(spacing: 0) {
            topBar
                .padding(.horizontal, 12)
                .padding(.top, 6)
                .padding(.bottom, 8)
                .background(.bar)

            Divider()

            ZStack {
                if let tab = activeTab {
                    if tab.isHome {
                        HomeView(bookmarks: bookmarkStore.bookmarks) { bookmark in
                            navigate(to: bookmark.urlString)
                        }
                    } else {
                        // .id(tab.id) forces SwiftUI to treat this as a
                        // brand-new UIViewRepresentable when the active tab
                        // changes, so it actually swaps the displayed
                        // WKWebView instead of leaving the previous tab's
                        // view on screen (UIViewRepresentable's
                        // updateUIView is a no-op here — see
                        // WebViewRepresentable.swift).
                        WebViewRepresentable(webView: tab.webView)
                            .id(tab.id)
                    }

                    if let threat = tab.blockedThreat {
                        threatOverlay(host: threat, tab: tab)
                    }
                } else {
                    ProgressView()
                }
            }

            Divider()

            bottomToolbar
                .padding(.horizontal, 8)
                .padding(.vertical, 8)
                .background(.bar)
        }
        .onAppear {
            addressBarText = startURL
            tabManager.applyCamswapConfigToAllTabs(serverUrl: serverUrl, room: room, showStatusBadge: showBadge)
            navigate(to: startURL)
        }
        .onChange(of: activeTab?.currentURLString ?? "") { newValue in
            if !addressBarFocused {
                addressBarText = newValue
            }
        }
        .onChange(of: tabManager.activeTabID) { _ in
            addressBarText = activeTab?.currentURLString ?? ""
        }
        .sheet(isPresented: $showSettings) {
            SettingsView(
                serverUrl: $serverUrl,
                room: $room,
                showBadge: $showBadge,
                onApplyCamswap: {
                    tabManager.applyCamswapConfigToAllTabs(serverUrl: serverUrl, room: room, showStatusBadge: showBadge)
                },
                onPrivacyChanged: {
                    tabManager.reapplyPrivacyToAllTabs()
                },
                onProxyChanged: {
                    tabManager.applyProxyConfiguration()
                }
            )
        }
        .sheet(isPresented: $showTabSwitcher) {
            TabSwitcherView(
                tabs: tabManager.tabs,
                activeTabID: tabManager.activeTabID,
                onSelect: { tab in
                    tabManager.selectTab(tab)
                    showTabSwitcher = false
                },
                onClose: { tab in tabManager.closeTab(tab) },
                onNewTab: {
                    tabManager.newTab(activate: true)
                    showTabSwitcher = false
                }
            )
        }
        .sheet(isPresented: $showBookmarksHistory) {
            BookmarksHistoryView(
                onOpen: { urlString in
                    showBookmarksHistory = false
                    navigate(to: urlString)
                }
            )
        }
        .fullScreenCover(isPresented: $showScanner) {
            QRScannerView(
                onScan: { server, code in
                    serverUrl = server
                    room = code
                    showScanner = false
                    tabManager.applyCamswapConfigToAllTabs(serverUrl: serverUrl, room: room, showStatusBadge: showBadge)
                },
                onCancel: { showScanner = false }
            )
            .ignoresSafeArea()
        }
        .alert("Очистить куки, кэш и историю?", isPresented: $showClearConfirm) {
            Button("Отмена", role: .cancel) {}
            Button("Очистить всё", role: .destructive) {
                tabManager.clearAllBrowsingData {
                    justCleared = true
                    addressBarText = ""
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { justCleared = false }
                }
            }
        } message: {
            Text("Куки, кэш, локальные данные сайтов и история будут удалены за всё время. Закладки останутся нетронутыми.")
        }
        .overlay(alignment: .bottom) {
            if justCleared {
                Text("Готово — данные и история очищены")
                    .font(.footnote.weight(.medium))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(.thinMaterial, in: Capsule())
                    .padding(.bottom, 90)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }

    // MARK: - top bar

    private var topBar: some View {
        VStack(spacing: 6) {
            HStack(spacing: 10) {
                tabsButton

                addressBar

                Button {
                    guard let tab = activeTab else { return }
                    tab.isLoading ? tab.webView.stopLoading() : tab.reload()
                } label: {
                    Image(systemName: (activeTab?.isLoading ?? false) ? "xmark" : "arrow.clockwise")
                }
                .disabled(activeTab == nil)
            }

            HStack(spacing: 10) {
                Text(activeTab?.statusText ?? "")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Spacer()

                Button { showScanner = true } label: {
                    Image(systemName: "qrcode.viewfinder")
                }
                Button { showSettings = true } label: {
                    Image(systemName: "gearshape")
                }
            }
            .font(.subheadline)
        }
    }

    private var tabsButton: some View {
        Button {
            showTabSwitcher = true
        } label: {
            ZStack(alignment: .topTrailing) {
                Image(systemName: "square.on.square")
                    .font(.title3)
                Text("\(tabManager.tabs.count)")
                    .font(.system(size: 9, weight: .bold))
                    .padding(2)
                    .background(Circle().fill(Color.accentColor))
                    .foregroundStyle(.white)
                    .offset(x: 8, y: -6)
            }
        }
    }

    private var addressBar: some View {
        HStack(spacing: 6) {
            Image(systemName: privacy.privateSearchEnabled ? "lock.shield.fill" : "lock.fill")
                .font(.caption)
                .foregroundStyle(.secondary)

            TextField("Поиск или адрес сайта", text: $addressBarText)
                .textFieldStyle(.plain)
                .keyboardType(.webSearch)
                .textInputAutocapitalization(.never)
                .disableAutocorrection(true)
                .focused($addressBarFocused)
                .submitLabel(.go)
                .onSubmit { navigate(to: addressBarText) }

            if !addressBarText.isEmpty {
                Button {
                    addressBarText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
            }

            if let tab = activeTab, !tab.isHome {
                Button {
                    toggleBookmark(for: tab)
                } label: {
                    Image(systemName: bookmarkStore.isBookmarked(urlString: tab.currentURLString) ? "star.fill" : "star")
                        .foregroundStyle(bookmarkStore.isBookmarked(urlString: tab.currentURLString) ? .yellow : .secondary)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color(.secondarySystemBackground), in: Capsule())
    }

    // MARK: - bottom toolbar

    private var bottomToolbar: some View {
        HStack {
            Button {
                activeTab?.webView.goBack()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.title3)
            }
            .disabled(!(activeTab?.webView.canGoBack ?? false))
            .frame(maxWidth: .infinity)

            Button {
                showBookmarksHistory = true
            } label: {
                Image(systemName: "book")
                    .font(.title3)
            }
            .frame(maxWidth: .infinity)

            Button {
                showClearConfirm = true
            } label: {
                Image(systemName: "trash.circle.fill")
                    .font(.system(size: 34))
                    .foregroundStyle(.red)
            }
            .frame(maxWidth: .infinity)

            Button {
                tabManager.newTab(activate: true)
            } label: {
                Image(systemName: "plus")
                    .font(.title3)
            }
            .frame(maxWidth: .infinity)

            Button {
                activeTab?.webView.goForward()
            } label: {
                Image(systemName: "chevron.right")
                    .font(.title3)
            }
            .disabled(!(activeTab?.webView.canGoForward ?? false))
            .frame(maxWidth: .infinity)
        }
    }

    private func threatOverlay(host: String, tab: BrowserTab) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.shield.fill")
                .font(.system(size: 44))
                .foregroundStyle(.red)
            Text("Заблокирован переход на подозрительный сайт")
                .font(.headline)
                .multilineTextAlignment(.center)
            Text(host)
                .font(.footnote)
                .foregroundStyle(.secondary)
            Button("Назад") {
                tab.blockedThreat = nil
                tab.goHome()
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.regularMaterial)
    }

    // MARK: - actions

    private func navigate(to urlString: String) {
        addressBarFocused = false
        guard let tab = activeTab else { return }
        if urlString == startURL { /* keep as-is */ } else if !urlString.isEmpty {
            startURL = urlString
        }
        tab.load(urlString: urlString)
    }

    private func toggleBookmark(for tab: BrowserTab) {
        if bookmarkStore.isBookmarked(urlString: tab.currentURLString) {
            if let existing = bookmarkStore.bookmarks.first(where: { $0.urlString == tab.currentURLString }) {
                bookmarkStore.remove(existing)
            }
        } else {
            bookmarkStore.add(title: tab.title, urlString: tab.currentURLString)
        }
    }
}

#Preview {
    ContentView()
}
