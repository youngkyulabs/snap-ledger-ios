import SwiftData
import SwiftUI
import UIKit
import UserNotifications

struct OnboardingSetupPage: View {
    @Environment(\.modelContext) private var modelContext
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
                if notificationToggle {
                    reminderTimeCard
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .padding(.horizontal)
            .animation(.smooth(duration: 0.3), value: notificationToggle)

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
            Task { await OnboardingAppearStep.run { step = $0 } }
        }
    }

    private var ctaSection: some View {
        VStack(spacing: 8) {
            if !canProceed {
                Text("폴더를 먼저 선택해주세요.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
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
    }

    private var folderCard: some View {
        Button {
            showingPicker = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "folder.fill")
                    .font(.title2)
                    .foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 4) {
                    Text("CSV 저장 폴더").font(.headline).foregroundStyle(.primary)
                    Text(folderName ?? "선택 안 됨")
                        .font(.subheadline)
                        .foregroundStyle(folderName == nil ? .secondary : .primary)
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(.secondary)
            }
            .padding()
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
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
                Text("야간 알림").font(.headline)
                Text("매일 저녁 검토 항목을 알려드려요.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Toggle("야간 알림", isOn: Binding(
                get: { notificationToggle },
                set: { newValue in
                    if newValue {
                        Task { await requestPermission() }
                    } else {
                        notificationToggle = false
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
            notificationToggle = granted
        case .openSystemSettings:
            showingDeniedAlert = true
        case .keepOn:
            notificationToggle = true
        }
    }

    private func openSystemSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }
}

private struct OnboardingSetupSheetsAndAlerts: ViewModifier {
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
                Button("취소", role: .cancel) { notificationToggle = false }
            } message: {
                Text("알림을 받으려면 설정 → SnapLedger → 알림에서 켜주세요.")
            }
    }
}
