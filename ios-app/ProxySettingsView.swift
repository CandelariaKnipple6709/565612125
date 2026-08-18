import SwiftUI

/// Dedicated proxy screen: entirely optional, off by default. Only
/// touches networking once "Использовать прокси" is on AND a host is
/// filled in (see ProxySettings.isConfigured).
///
/// Deliberately built with plain HStack rows instead of LabeledContent —
/// a build tried that first and the compiler choked on the two-trailing-
/// closure `LabeledContent { ... } label: { ... }` form (reported as
/// generic-inference errors on the enclosing Section). HStack + Text +
/// TextField is less elegant but has none of that ambiguity.
struct ProxySettingsView: View {
    let onChanged: () -> Void

    @ObservedObject private var proxy = ProxySettings.shared

    var body: some View {
        Form {
            Section {
                Toggle(isOn: $proxy.enabled) {
                    Label("Использовать прокси", systemImage: "network")
                }
            } footer: {
                Text("По умолчанию выключено — весь трафик идёт напрямую (или через ваш VPN). Включайте, только если стриминговый сервис недоступен напрямую и нужно зайти через прокси-сервер.")
            }

            if proxy.enabled {
                Section("Сервер") {
                    fieldRow(label: "Хост / IP") {
                        TextField("например 203.0.113.10", text: $proxy.host)
                            .keyboardType(.URL)
                            .autocapitalization(.none)
                            .disableAutocorrection(true)
                            .multilineTextAlignment(.trailing)
                    }
                    fieldRow(label: "Порт") {
                        TextField("8080", text: $proxy.port)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                    }
                }

                Section {
                    fieldRow(label: "Логин") {
                        TextField("логин", text: $proxy.username)
                            .autocapitalization(.none)
                            .disableAutocorrection(true)
                            .multilineTextAlignment(.trailing)
                    }
                    fieldRow(label: "Пароль") {
                        SecureField("пароль", text: $proxy.password)
                            .multilineTextAlignment(.trailing)
                    }
                } header: {
                    Text("Авторизация (необязательно)")
                } footer: {
                    Text("Пароль хранится в Keychain на этом устройстве, а не в обычных настройках приложения.")
                }

                Section {
                    HStack {
                        Circle()
                            .fill(proxy.isConfigured ? Color.green : Color.orange)
                            .frame(width: 8, height: 8)
                        Text(proxy.isConfigured ? "Прокси настроен и будет использоваться" : "Заполните хост и корректный порт, чтобы прокси заработал")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle("Прокси")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: proxy.enabled) { _ in onChanged() }
        .onChange(of: proxy.host) { _ in onChanged() }
        .onChange(of: proxy.port) { _ in onChanged() }
        .onChange(of: proxy.username) { _ in onChanged() }
        .onChange(of: proxy.password) { _ in onChanged() }
    }

    @ViewBuilder
    private func fieldRow<Field: View>(label: String, @ViewBuilder field: () -> Field) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer(minLength: 12)
            field()
        }
    }
}
