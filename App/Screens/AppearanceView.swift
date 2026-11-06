import SwiftUI
import MnemoCore

struct AppearanceView: View {
    @Environment(AppStore.self) private var store
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text(store.t("Оформление", "Appearance")).font(.largeTitle.bold())
                Text(store.t("26 тем приложения", "26 app themes")).foregroundStyle(.secondary)
                Toggle(store.t("Светлая и тёмная вместе с iOS", "Follow iOS appearance"), isOn: store.setting(\.followSystem)).padding(16).glassEffect(in: .rect(cornerRadius: 24))
                ThemeGrid()
                SectionTitle(title: store.t("Анимация главной", "Home animation"))
                AnimationPicker()
            }.padding(20)
        }.background { AmbientBackground() }.navigationBarTitleDisplayMode(.inline)
    }
}

struct ThemeGrid: View {
    @Environment(AppStore.self) private var store
    var compact = false
    var body: some View {
        LazyVGrid(columns: [.init(.flexible()), .init(.flexible())], spacing: 14) {
            ForEach(compact ? Array(AppTheme.all.prefix(8)) : AppTheme.all) { theme in
                Button {
                    store.perform { try store.commit { $0.settings.themeID = theme.id } }; Haptics.tap(store.settings.haptics)
                } label: {
                    VStack(alignment: .leading, spacing: 10) {
                        ZStack {
                            Color(hex: theme.background)
                            Circle().fill(Color(hex: theme.glow).opacity(0.8)).frame(width: 90, height: 90).blur(radius: 24).offset(x: 38, y: -12)
                            VStack(spacing: 10) {
                                HStack { Text(store.t("Сегодня", "Today")).font(.caption.bold()); Spacer(); Image(systemName: "sun.max") }
                                ZStack {
                                    Circle().stroke(Color(hex: theme.accent).opacity(0.4), style: StrokeStyle(lineWidth: 1, dash: [2, 5])).frame(width: 46, height: 46)
                                    Text("24").font(.title3.bold())
                                }
                                Capsule().fill(Color(hex: theme.accent)).frame(height: 10)
                            }.padding(14).foregroundStyle(Color(hex: theme.text))
                        }.frame(height: 128).clipShape(RoundedRectangle(cornerRadius: 24))
                            .overlay { RoundedRectangle(cornerRadius: 24).stroke(store.settings.themeID == theme.id ? Color(hex: store.theme.accent) : .primary.opacity(0.08), lineWidth: store.settings.themeID == theme.id ? 2 : 1) }
                        HStack(spacing: 4) {
                            Text(theme.name(store.lang)).font(.caption.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.7)
                            if store.settings.themeID == theme.id { Image(systemName: "checkmark.circle.fill").font(.caption).foregroundStyle(Color(hex: store.theme.accent)) }
                        }
                    }.contentShape(Rectangle())
                }.buttonStyle(PressStyle()).accessibilityLabel(theme.name(store.lang)).accessibilityAddTraits(store.settings.themeID == theme.id ? .isSelected : [])
            }
        }
    }
}

struct AnimationPicker: View {
    @Environment(AppStore.self) private var store
    private var options: [(String, String, String)] {
        [("sphere", store.t("Сфера 3D", "3D sphere"), "globe"), ("galaxy", store.t("Галактика", "Galaxy"), "sparkles"),
         ("liquid", store.t("Жидкий шар", "Liquid orb"), "drop"), ("cards", store.t("Стопка карточек", "Card stack"), "rectangle.stack")]
    }
    var body: some View {
        GlassPanel {
            VStack(spacing: 12) {
                ForEach(options, id: \.0) { option in
                    Button {
                        store.perform { try store.commit { $0.settings.animation = option.0 } }
                    } label: {
                        SettingRow(symbol: option.2, title: option.1) {
                            if store.settings.animation == option.0 { Image(systemName: "checkmark").foregroundStyle(Color(hex: store.theme.accent)) }
                        }
                    }.buttonStyle(.plain)
                }
            }
        }
    }
}

struct CardThemePicker: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Binding var selected: Int
    @State private var category = 0
    var body: some View {
        NavigationStack {
            ZStack {
                AmbientBackground()
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        ScrollView(.horizontal) {
                            HStack(spacing: 8) {
                                ForEach(0..<6) { index in
                                    Button { category = index } label: {
                                        Text(store.lang == .ru ? CardTheme.categoriesRU[index] : CardTheme.categoriesEN[index]).font(.subheadline.weight(.semibold)).padding(.horizontal, 14).padding(.vertical, 12)
                                    }.buttonStyle(.glass).tint(category == index ? Color(hex: store.theme.accent) : .primary)
                                }
                            }
                        }.scrollIndicators(.hidden)
                        LazyVGrid(columns: [.init(.flexible()), .init(.flexible()), .init(.flexible())], spacing: 16) {
                            ForEach(CardTheme.all.filter { $0.category == category }) { theme in
                                Button { selected = theme.id; Haptics.tap(store.settings.haptics); dismiss() } label: {
                                    VStack(alignment: .leading, spacing: 8) {
                                        CardSurface(themeID: theme.id).frame(height: 80).clipShape(RoundedRectangle(cornerRadius: 18))
                                            .overlay(alignment: .bottomLeading) { Text("Aa").font(.headline).padding(8).foregroundStyle(Color(hex: theme.text)).background(Color(hex: theme.palette.hex).opacity(0.98), in: RoundedRectangle(cornerRadius: 10)).padding(5) }
                                            .overlay { RoundedRectangle(cornerRadius: 18).stroke(selected == theme.id ? Color(hex: store.theme.accent) : .clear, lineWidth: 3) }
                                        Text(theme.name(store.lang)).font(.caption2).lineLimit(2).frame(height: 30, alignment: .topLeading)
                                    }
                                }.buttonStyle(PressStyle()).accessibilityLabel(theme.name(store.lang)).accessibilityAddTraits(selected == theme.id ? .isSelected : [])
                            }
                        }
                    }.padding(20)
                }
            }.navigationTitle(store.t("150 тем карточек", "150 card styles")).navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .topBarTrailing) { Button(store.t("Готово", "Done")) { dismiss() } } }
        }.onAppear { category = selected / 25 }
    }
}
