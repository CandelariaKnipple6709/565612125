import SwiftUI

struct SettingsView: View {
    @Binding var serverUrl: String
    @Binding var room: String
    @Binding var showBadge: Bool

    let onApplyCamswap: () -> Void
    let onPrivacyChanged: () -> Void
    let onProxyChanged: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            Form {
                Section {
                    NavigationLink {
                        PrivacyProtectionsView(onChanged: onPrivacyChanged)
                    } label: {
                        Label("Приватность", systemImage: "hand.raised.fill")
                    }
                    NavigationLink {
                        ProxySettingsView(onChanged: onProxyChanged)
                    } label: {
                        Label("Прокси-подключение", systemImage: "network")
                    }
                }

                Section {
                    TextField("Signaling server (wss://...)", text: $serverUrl)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                    TextField("Код комнаты", text: $room)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                    Toggle("Показывать статус-бейдж (для отладки)", isOn: $showBadge)
                } header: {
                    Text("Подмена камеры")
                } footer: {
                    Text("Обычно эти поля заполняются автоматически сканированием QR-кода в студии на компьютере — сюда лезть не нужно, если сканирование уже сработало.")
                }

                Section {
                    Button {
                        onApplyCamswap()
                        dismiss()
                    } label: {
                        Text("Применить и перезагрузить вкладки")
                            .frame(maxWidth: .infinity)
                    }
                }
            }
            .navigationTitle("Настройки")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Готово") { dismiss() }
                }
            }
        }
    }
}
