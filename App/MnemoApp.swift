import SwiftUI
import MnemoCore
import UserNotifications

@main struct MnemoApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var store = AppStore()
    @State private var agent = GeminiAgent()
    var body: some Scene {
        WindowGroup {
            RootView().environment(store).environment(agent)
                .environment(\.locale, store.lang.locale)
                .preferredColorScheme(store.settings.followSystem ? nil : (store.theme.dark ? .dark : .light))
                .tint(Color(hex: store.theme.accent))
                .onReceive(NotificationCenter.default.publisher(for: .mnemoOpenReview)) { _ in
                    guard !store.locked else { return }; store.startReview()
                }
        }
    }
}

extension Notification.Name { static let mnemoOpenReview = Notification.Name("mnemo.open.review") }

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self; return true
    }
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) { completionHandler([.banner, .sound]) }
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        Task { @MainActor in NotificationCenter.default.post(name: .mnemoOpenReview, object: nil) }; completionHandler()
    }
}

struct RootView: View {
    @Environment(AppStore.self) private var store
    @Environment(GeminiAgent.self) private var agent
    @Environment(\.scenePhase) private var phase
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        @Bindable var store = store
        ZStack {
            AmbientBackground()
            if store.loadFailed {
                EmptyMessage(symbol: "externaldrive.badge.exclamationmark", title: store.t("Не удалось открыть данные", "Could not open your data"), detail: store.t("Исходный файл сохранён. Не переустанавливайте приложение: сначала скопируйте данные.", "The original file is intact. Preserve it before reinstalling the app."))
            } else if !store.settings.onboardingComplete {
                OnboardingView()
            } else {
                mainContent
            }
            if store.locked || (store.settings.faceID && phase != .active) {
                LockScreen().background(Color(hex: store.theme.background).ignoresSafeArea()).zIndex(100)
            }
        }.foregroundStyle(Color(hex: store.theme.text))
            .alert(store.t("Не получилось", "Something went wrong"), isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })) {
                Button("OK") { store.error = nil }
            } message: { Text(store.error ?? "") }
            .alert(store.t("Mnemo", "Mnemo"), isPresented: Binding(get: { store.notice != nil }, set: { if !$0 { store.notice = nil } })) {
                Button("OK") { store.notice = nil }
            } message: { Text(store.notice ?? "") }
            .onChange(of: phase) { _, phase in
                if phase == .background && store.settings.faceID { store.locked = true; agent.stop() }
                if phase == .active { store.visit() }
            }
            .onOpenURL { url in
                if url.scheme == "mnemo" && url.host == "review" && !store.locked { store.startReview() }
            }
            .onChange(of: scheme) { _, scheme in store.systemDark = scheme == .dark }
            .task { store.systemDark = scheme == .dark; store.visit() }
    }
    private var mainContent: some View {
        @Bindable var store = store
        return NavigationStack {
            Group {
                switch store.selectedTab {
                case 1: DecksView()
                case 2: StatisticsView()
                case 3: SettingsView()
                default: TodayView()
                }
            }.background(.clear).toolbarBackground(.hidden, for: .navigationBar)
                .safeAreaInset(edge: .bottom, spacing: 0) { GlassNavigation().padding(.horizontal, 16).padding(.bottom, 8).padding(.top, 8) }
        }.background(.clear)
            .sheet(isPresented: $store.showAgent) { AgentView().presentationDragIndicator(.visible).presentationBackground(.clear) }
            .fullScreenCover(item: $store.reviewRequest) { request in ReviewView(request: request) }
    }
}

struct LockScreen: View {
    @Environment(AppStore.self) private var store
    @State private var unlocking = false
    @State private var error = ""
    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "rectangle.on.rectangle").font(.system(size: 52, weight: .light)).foregroundStyle(Color(hex: store.theme.accent))
            Text("Mnemo").font(.largeTitle.bold())
            Text(store.t("Ваши карточки под защитой", "Your cards are protected")).foregroundStyle(.secondary)
            PrimaryButton(title: store.t("Открыть с Face ID", "Unlock"), symbol: "faceid") { unlock() }.disabled(unlocking)
            if !error.isEmpty { Text(error).font(.footnote).multilineTextAlignment(.center) }
        }.padding(32).task { if store.locked { unlock() } }
    }
    private func unlock() {
        guard !unlocking else { return }; unlocking = true
        Task {
            defer { unlocking = false }
            do { if try await Authentication.unlock(language: store.lang) { store.locked = false; store.visit() } }
            catch { self.error = error.localizedDescription }
        }
    }
}

struct GlassNavigation: View {
    @Environment(AppStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var finger: CGFloat?
    @State private var hover = -1
    @Namespace private var namespace
    private var labels: [String] { [store.t("Сегодня", "Today"), store.t("Колоды", "Decks"), store.t("Статистика", "Statistics"), store.t("Настройки", "Settings")] }
    private let icons = ["sun.max", "rectangle.on.rectangle", "chart.bar.xaxis", "gearshape"]
    var body: some View {
        GlassEffectContainer(spacing: 12) {
            HStack(spacing: 10) {
                GeometryReader { geometry in
                    let width = (geometry.size.width - 8) / 4
                    let x = finger ?? (4 + width * (CGFloat(store.selectedTab) + 0.5))
                    ZStack(alignment: .leading) {
                        Capsule().fill(.clear).glassEffect(.regular, in: .capsule)
                        Capsule().fill(Color(hex: store.theme.accent).opacity(0.08))
                            .frame(width: width, height: finger == nil ? 56 : 62)
                            .glassEffect(.regular.tint(Color(hex: store.theme.accent).opacity(0.12)).interactive(), in: .capsule)
                            .glassEffectID("lens", in: namespace)
                            .offset(x: x - width / 2)
                            .animation(reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.74), value: x)
                        HStack(spacing: 0) {
                            ForEach(0..<4) { index in
                                Button { select(index) } label: {
                                    VStack(spacing: 4) {
                                        Image(systemName: icons[index]).font(.system(size: 21, weight: .medium))
                                        Text(labels[index]).font(.system(size: 10, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.65)
                                    }.foregroundStyle(index == (finger == nil ? store.selectedTab : hover) ? Color(hex: store.theme.accent) : Color(hex: store.theme.text))
                                        .frame(width: width, height: 60).contentShape(Capsule())
                                }.buttonStyle(.plain).accessibilityIdentifier("tab-\(index)")
                                    .accessibilityLabel(labels[index]).accessibilityAddTraits(index == store.selectedTab ? .isSelected : [])
                            }
                        }.padding(.horizontal, 4)
                    }.frame(height: 66)
                        .simultaneousGesture(DragGesture(minimumDistance: 5).onChanged { value in
                            finger = min(geometry.size.width - width / 2 - 4, max(width / 2 + 4, value.location.x))
                            let next = min(3, max(0, Int((value.location.x - 4) / width)))
                            if hover != next { hover = next; Haptics.tap(store.settings.haptics) }
                        }.onEnded { value in
                            select(min(3, max(0, Int((value.location.x - 4) / width)))); finger = nil; hover = -1
                        })
                }.frame(height: 66)
                Button { store.showAgent = true } label: {
                    Image(systemName: "sparkles").font(.system(size: 25)).frame(width: 58, height: 66)
                }.buttonStyle(.plain).glassEffect(.regular.tint(Color(hex: store.theme.accent).opacity(0.2)).interactive(), in: .capsule)
                    .accessibilityLabel(store.t("Открыть Gemini", "Open Gemini")).accessibilityIdentifier("open-agent")
            }
        }
    }
    private func select(_ index: Int) {
        guard store.selectedTab != index else { return }
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) { store.selectedTab = index }
        Haptics.tap(store.settings.haptics)
    }
}
