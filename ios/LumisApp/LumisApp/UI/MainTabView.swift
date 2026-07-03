import SwiftUI

/// Authenticated app shell. The tab bar is gone: Home is the single surface,
/// with a liquid-glass chat bar above the bottom edge, a slide-in sidebar
/// (recent actions + account) opened from the top-left menu button, and a
/// full-screen Settings sheet reached from the sidebar's initials button.
struct MainTabView: View {
    @EnvironmentObject private var vm: LumisViewModel
    @EnvironmentObject private var authVM: AuthViewModel

    @State private var sidebarOpen = false
    @State private var showSettings = false
    @State private var showCamera = false
    @State private var recent: [ActionHistoryItem] = []

    var body: some View {
        ZStack(alignment: .leading) {
            HomeView(onMenu: openSidebar)
                .overlay(alignment: .bottom) {
                    ChatBarView(onCamera: { showCamera = true })
                        .padding(.bottom, 12)
                }
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
                    recent: recent,
                    initials: authVM.currentUser?.initials ?? "?",
                    name: authVM.currentUser?.displayName ?? "",
                    email: authVM.currentUser?.email ?? "",
                    onSettings: { showSettings = true }
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
        .fullScreenCover(isPresented: $showSettings, onDismiss: { Task { await loadRecent() } }) {
            SettingsView(onClose: { showSettings = false })
                .environmentObject(authVM)
                .environmentObject(vm)
        }
        .onAppear {
            vm.start()
            Task { await loadRecent() }
        }
    }

    private func openSidebar() {
        Task { await loadRecent() }
        withAnimation(.spring(response: 0.45, dampingFraction: 0.82)) { sidebarOpen = true }
    }

    private func closeSidebar() {
        withAnimation(.spring(response: 0.45, dampingFraction: 0.82)) { sidebarOpen = false }
    }

    private func loadRecent() async {
        if let fetched = try? await APIClient.history(baseURL: LumisConfig.backendURL) {
            recent = Array(fetched.prefix(20))
        }
    }
}
