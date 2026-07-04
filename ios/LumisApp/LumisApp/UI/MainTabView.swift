import SwiftUI

/// Authenticated app shell: Home is the single surface, with a slide-in
/// sidebar (Past Chats + profile) opened from the toggle beneath the top bar,
/// a full-screen Settings sheet reached from the sidebar's initials mark, and
/// the live camera reached from the text bar.
struct MainTabView: View {
    @EnvironmentObject private var vm: LumisViewModel
    @EnvironmentObject private var authVM: AuthViewModel

    @State private var sidebarOpen = false
    @State private var showSettings = false
    @State private var showCamera = false

    var body: some View {
        ZStack(alignment: .leading) {
            HomeView(onMenu: openSidebar, onCamera: { showCamera = true })
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
                    initials: authVM.currentUser?.initials ?? "?",
                    name: authVM.currentUser?.displayName ?? "",
                    email: authVM.currentUser?.email ?? "",
                    onSettings: { showSettings = true },
                    onOpenChat: { chat in
                        vm.openPastChat(chat)
                        closeSidebar()
                    },
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
        .fullScreenCover(isPresented: $showSettings) {
            SettingsView(onClose: { showSettings = false })
                .environmentObject(authVM)
                .environmentObject(vm)
        }
        .onAppear { vm.start() }
    }

    private func openSidebar() {
        withAnimation(.spring(response: 0.45, dampingFraction: 0.82)) { sidebarOpen = true }
    }

    private func closeSidebar() {
        withAnimation(.spring(response: 0.45, dampingFraction: 0.82)) { sidebarOpen = false }
    }
}
