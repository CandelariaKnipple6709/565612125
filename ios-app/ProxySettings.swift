import Foundation
import Combine
import Network

/// Optional HTTP proxy configuration (host/port/username/password),
/// entirely opt-in — disabled by default, and only touches networking
/// once the user flips "Использовать прокси" on and fills in a host.
///
/// The password is the only sensitive field, so it's the only one kept
/// in the Keychain (see KeychainHelper); host/port/username/enabled live
/// in UserDefaults like every other setting here.
///
/// Requires iOS 17+ (WKWebsiteDataStore.proxyConfigurations, part of the
/// Network framework's ProxyConfiguration API). This is the newest API
/// used in this app and the one most likely to need adjustment if a
/// future SDK changes its shape — see the note in TabManager where it's
/// applied.
final class ProxySettings: ObservableObject {
    static let shared = ProxySettings()

    @Published var enabled: Bool {
        didSet { UserDefaults.standard.set(enabled, forKey: Keys.enabled) }
    }
    @Published var host: String {
        didSet { UserDefaults.standard.set(host, forKey: Keys.host) }
    }
    @Published var port: String {
        didSet { UserDefaults.standard.set(port, forKey: Keys.port) }
    }
    @Published var username: String {
        didSet { UserDefaults.standard.set(username, forKey: Keys.username) }
    }
    @Published var password: String {
        didSet {
            if password.isEmpty {
                KeychainHelper.delete(account: Keys.passwordAccount)
            } else {
                KeychainHelper.set(password, account: Keys.passwordAccount)
            }
        }
    }

    private enum Keys {
        static let enabled = "proxy.enabled"
        static let host = "proxy.host"
        static let port = "proxy.port"
        static let username = "proxy.username"
        static let passwordAccount = "proxy.password"
    }

    private init() {
        let d = UserDefaults.standard
        enabled = d.bool(forKey: Keys.enabled)
        host = d.string(forKey: Keys.host) ?? ""
        port = d.string(forKey: Keys.port) ?? ""
        username = d.string(forKey: Keys.username) ?? ""
        password = KeychainHelper.get(account: Keys.passwordAccount) ?? ""
    }

    var isConfigured: Bool {
        enabled && !host.trimmingCharacters(in: .whitespaces).isEmpty && UInt16(port) != nil
    }

    /// URLCredential used to answer the proxy's Basic/NTLM auth challenge
    /// when username/password are set. Returns nil if there's nothing to
    /// offer, in which case the proxy is used unauthenticated.
    var credential: URLCredential? {
        guard !username.isEmpty else { return nil }
        return URLCredential(user: username, password: password, persistence: .forSession)
    }

    @available(iOS 17.0, *)
    func makeProxyConfiguration() -> ProxyConfiguration? {
        guard isConfigured, let portNumber = UInt16(port), let nwPort = NWEndpoint.Port(rawValue: portNumber) else {
            return nil
        }
        let endpoint = NWEndpoint.hostPort(host: NWEndpoint.Host(host), port: nwPort)
        return ProxyConfiguration(httpCONNECTProxy: endpoint)
    }
}
