import SwiftUI

/// Authenticated app shell: Home is the single surface, with a slide-in
/// sidebar (past chats only) opened from the glass toggle beneath the top
/// bar, a full-screen Settings sheet reached solely from the glass profile
/// button top-right, and the live camera reached from the text bar.
struct MainTabView: View {
    @EnvironmentObject private var vm: LumisViewModel
    @EnvironmentObject private var authVM: AuthViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var sidebarOpen = false
    @State private var showSettings = false
    @State private var showCamera = false

    var body: some View {
        ZStack(alignment: .leading) {
            HomeView(onMenu: openSidebar,
                     onCamera: { showCamera = true },
                     initials: authVM.currentUser?.initials ?? "?",
                     onProfile: { showSettings = true })
                // The main content eases aside as the sidebar comes in, then
                // slides back — a natural, weighted iOS dismissal.
                .scaleEffect(sidebarOpen ? 0.92 : 1, anchor: .trailing)
                .offset(x: sidebarOpen ? 60 : 0)
                // Tapping back into the home page closes the sidebar.
                .allowsHitTesting(!sidebarOpen)

            if sidebarOpen {
                LumisColors.scrim
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture(perform: closeSidebar)
                    .transition(.opacity)

                SidebarView(
                    onOpenChat: { chat in
                        vm.openPastChat(chat)
                        closeSidebar()
                    },
                    onNewChat: {
                        vm.dismissCurrentChat()
                        closeSidebar()
                    },
                    onClose: closeSidebar,
                    pastChats: vm.pastChats
                )
                .transition(.move(edge: .leading))
            }
        }
        .fullScreenCover(isPresented: $showCamera) {
            LiveCameraView(
                onCapture: { image in
                    vm.send(image: image, text: "")
                    showCamera = false
                },
                onClose: { showCamera = false }
            )
            .environmentObject(vm)
        }
        .sheet(isPresented: $showSettings) {
            SettingsView(onClose: { showSettings = false })
                .environmentObject(authVM)
                .environmentObject(vm)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .presentationBackground(.regularMaterial)
        }
        .onAppear {
            vm.start()
            #if DEBUG
            // UI-screenshot hook: open the Settings sheet directly.
            if ProcessInfo.processInfo.environment["LUMIS_UI_SETTINGS"] != nil {
                showSettings = true
            }
            #endif
        }
    }

    private func openSidebar() {
        withAnimation(reduceMotion ? nil : .spring(response: 0.45, dampingFraction: 0.82)) { sidebarOpen = true }
    }

    private func closeSidebar() {
        withAnimation(reduceMotion ? nil : .spring(response: 0.45, dampingFraction: 0.82)) { sidebarOpen = false }
    }
}
