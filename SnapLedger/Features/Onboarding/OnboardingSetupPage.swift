import SwiftData
import SwiftUI
import UIKit
import UserNotifications

struct OnboardingSetupPage: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Bindable var settings: AppSettings
    let isVisible: Bool
    let onComplete: () -> Void

    @State private var showingPicker = false
    @State private var folderError: String?
    @State private var notificationToggle = false
    @State private var showingDeniedAlert = false
    @State private var step = 0

    private var folderName: String? {
        guard let data = settings.csvFolderBookmark else { return nil }
        return (try? BookmarkStore.resolve(data).url.lastPathComponent)
    }

    private var canProceed: Bool { settings.csvFolderBookmark != nil }

    var body: some View {
        VStack(spacing: 24) {
            Text("시작 전 준비")
                .font(.title.bold())
                .padding(.top, 32)
                .appearStep(1, current: step)

            VStack(spacing: 16) {
                folderCard
                    .appearStep(2, current: step)
                notificationCard
                    .appearStep(3, current: step)
                reminderTimeCard
                    .opacity(notificationToggle ? 1 : 0)
                    .animation(reduceMotion ? nil : .smooth(duration: 0.3), value: notificationToggle)
            }
            .padding(.horizontal)

            Spacer()

            ctaSection
                .appearStep(4, current: step)
        }
        .modifier(OnboardingSetupSheetsAndAlerts(
            showingPicker: $showingPicker,
            folderError: $folderError,
            showingDeniedAlert: $showingDeniedAlert,
            notificationToggle: $notificationToggle,
            onPickFolder: handlePickedFolder,
            onOpenSettings: openSystemSettings
        ))
        .onChange(of: isVisible, initial: true) { _, newValue in
            guard newValue, step == 0 else { return }
            notificationToggle = settings.reminderEnabled
            Task { await OnboardingAppearStep.run(reduceMotion: reduceMotion) { step = $0 } }
        }
    }

    private var ctaSection: some View {
        VStack(spacing: 8) {
            Text("폴더를 먼저 선택해 주세요.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .opacity(canProceed ? 0 : 1)
            Button {
                settings.hasCompletedOnboarding = true
                try? modelContext.save()
                onComplete()
            } label: {
                Text("시작하기")
                    .frame(maxWidth: .infinity)
                    .font(.headline)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!canProceed)
            .padding(.horizontal)
        }
        .padding(.bottom, 16)
        .animation(reduceMotion ? nil : .smooth(duration: 0.25), value: canProceed)
    }

    private var folderCard: some View {
        Button {
            showingPicker = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "folder.fill")
                    .font(.title2)
                    .foregroundStyle(.tint)
                    .symbolEffect(.wiggle, options: .repeating, isActive: !canProceed && !reduceMotion)
                VStack(alignment: .leading, spacing: 4) {
                    Text("저장 폴더").font(.headline).foregroundStyle(.primary)
                    Text(folderName ?? "선택 안 됨")
                        .font(.subheadline)
                        .foregroundStyle(folderName == nil ? Color.accentColor : Color.primary)
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(.secondary)
            }
            .padding()
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(canProceed ? Color.clear : Color.accentColor.opacity(0.15))
            )
            .animation(reduceMotion ? nil : .smooth(duration: 0.3), value: canProceed)
        }
        .buttonStyle(.plain)
    }

    private var reminderTimeCard: some View {
        HStack(spacing: 12) {
            Image(systemName: "clock.fill")
                .font(.title2)
                .foregroundStyle(.tint)
            DatePicker(
                "알림 시각",
                selection: reminderTimeBinding,
                displayedComponents: .hourAndMinute
            )
        }
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
    }

    private var reminderTimeBinding: Binding<Date> {
        Binding(
            get: {
                var components = DateComponents()
                components.hour = settings.reminderHour
                components.minute = settings.reminderMinute
                return Calendar.current.date(from: components) ?? .now
            },
            set: { newValue in
                let components = Calendar.current.dateComponents([.hour, .minute], from: newValue)
                settings.reminderHour = components.hour ?? settings.reminderHour
                settings.reminderMinute = components.minute ?? settings.reminderMinute
                try? modelContext.save()
            }
        )
    }

    private var notificationCard: some View {
        HStack(spacing: 12) {
            Image(systemName: "bell.fill")
                .font(.title2)
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 4) {
                Text("검토 알림").font(.headline)
                Text("매일 정한 시각에 검토할 항목을 알려드려요.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Toggle("검토 알림", isOn: Binding(
                get: { notificationToggle },
                set: { newValue in
                    if newValue {
                        Task { await requestPermission() }
                    } else {
                        withAnimation(reduceMotion ? nil : .smooth(duration: 0.3)) {
                            notificationToggle = false
                        }
                        persistReminderEnabled(false)
                    }
                }
            ))
            .labelsHidden()
        }
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
    }

    private func handlePickedFolder(_ url: URL) {
        do {
            try FolderBookmarkHelper.apply(url: url, to: settings, context: modelContext)
            folderError = nil
        } catch {
            folderError = "폴더를 등록하지 못했어요: \(error.localizedDescription)"
        }
    }

    @MainActor
    private func requestPermission() async {
        let scheduler = NotificationScheduler()
        let status = await scheduler.authorizationStatus()
        switch OnboardingPermissionAction.decide(status: status) {
        case .requestAuthorization:
            let granted = await scheduler.requestPermissionIfNeeded()
            withAnimation(reduceMotion ? nil : .smooth(duration: 0.3)) {
                notificationToggle = granted
            }
            persistReminderEnabled(granted)
        case .openSystemSettings:
            showingDeniedAlert = true
            persistReminderEnabled(false)
        case .keepOn:
            withAnimation(reduceMotion ? nil : .smooth(duration: 0.3)) {
                notificationToggle = true
            }
            persistReminderEnabled(true)
        }
    }

    /// 온보딩에서의 알림 선택을 모델에 반영 — 켜짐은 사용자가 직접 켜고 권한을 허용한 경우에만.
    private func persistReminderEnabled(_ value: Bool) {
        settings.reminderEnabled = value
        try? modelContext.save()
    }

    private func openSystemSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }
}

private struct OnboardingSetupSheetsAndAlerts: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Binding var showingPicker: Bool
    @Binding var folderError: String?
    @Binding var showingDeniedAlert: Bool
    @Binding var notificationToggle: Bool
    let onPickFolder: (URL) -> Void
    let onOpenSettings: () -> Void

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $showingPicker) {
                FolderPicker(onPick: onPickFolder)
                    .ignoresSafeArea()
            }
            .alert(
                "폴더 등록 실패",
                isPresented: Binding(
                    get: { folderError != nil },
                    set: { if !$0 { folderError = nil } }
                ),
                presenting: folderError
            ) { _ in
                Button("확인", role: .cancel) { folderError = nil }
            } message: { message in
                Text(message)
            }
            .alert("알림 권한이 꺼져 있어요", isPresented: $showingDeniedAlert) {
                Button("설정 열기") { onOpenSettings() }
                Button("취소", role: .cancel) {
                    withAnimation(reduceMotion ? nil : .smooth(duration: 0.3)) {
                        notificationToggle = false
                    }
                }
            } message: {
                Text("알림을 받으려면 설정 → \(Self.appDisplayName) → 알림에서 켜 주세요.")
            }
    }

    private static let appDisplayName: String = {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String
            ?? "SnapLedger"
    }()
}
