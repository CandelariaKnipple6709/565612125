import SwiftUI

/// Mirrors DuckDuckGo iOS's "Privacy Protections" screen: one row per
/// toggle, colored icon + label + on/off switch. See PrivacySettings.swift
/// for what each toggle actually does under the hood (and its honest
/// limitations — small curated blocklists, not full third-party feeds).
struct PrivacyProtectionsView: View {
    let onChanged: () -> Void

    @ObservedObject private var settings = PrivacySettings.shared

    var body: some View {
        List {
            Section {
                row(
                    icon: "magnifyingglass.circle.fill", color: .blue,
                    title: "Private Search",
                    subtitle: "Поиск через DuckDuckGo вместо Google — без слежки за запросами.",
                    isOn: $settings.privateSearchEnabled
                )
                row(
                    icon: "eye.slash.circle.fill", color: .green,
                    title: "Web Tracking Protection",
                    subtitle: "Блокирует известные домены-трекеры на страницах.",
                    isOn: $settings.webTrackingProtectionEnabled
                )
                row(
                    icon: "shield.lefthalf.filled", color: .purple,
                    title: "Threat Protection",
                    subtitle: "Блокирует переход на сайты из короткого локального списка подозрительных доменов.",
                    isOn: $settings.threatProtectionEnabled
                )
                row(
                    icon: "hand.raised.fill", color: .orange,
                    title: "Cookie Pop-Up Protection",
                    subtitle: "Скрывает/автоматически закрывает баннеры согласия на cookies (работает не на 100% сайтов).",
                    isOn: $settings.cookiePopupProtectionEnabled
                )
                row(
                    icon: "envelope.fill", color: .pink,
                    title: "Email Protection",
                    subtitle: "Пока не реализовано — требует отдельного почтового релей-сервиса. Переключатель ничего не делает.",
                    isOn: $settings.emailProtectionEnabled
                )
                row(
                    icon: "nosign", color: .red,
                    title: "Ad Blocking",
                    subtitle: "Блокирует известные рекламные домены.",
                    isOn: $settings.adBlockingEnabled
                )
            } footer: {
                Text("Изменения применяются к уже открытым вкладкам сразу; для полной подмены content-блокировщика может понадобиться обновить страницу.")
            }
        }
        .navigationTitle("Приватность")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: settings.privateSearchEnabled) { _ in onChanged() }
        .onChange(of: settings.webTrackingProtectionEnabled) { _ in onChanged() }
        .onChange(of: settings.threatProtectionEnabled) { _ in onChanged() }
        .onChange(of: settings.cookiePopupProtectionEnabled) { _ in onChanged() }
        .onChange(of: settings.emailProtectionEnabled) { _ in onChanged() }
        .onChange(of: settings.adBlockingEnabled) { _ in onChanged() }
    }

    private func row(icon: String, color: Color, title: String, subtitle: String, isOn: Binding<Bool>) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(color)
                .frame(width: 30)

            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.subheadline.weight(.medium))
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            Toggle("", isOn: isOn)
                .labelsHidden()
        }
        .padding(.vertical, 4)
    }
}
