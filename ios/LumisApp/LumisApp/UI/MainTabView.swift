import SwiftUI

/// Authenticated app shell: the four screens behind a custom liquid-glass tab
/// bar. The Camera tab is full-screen immersive, so the bar hides there.
struct MainTabView: View {
    @EnvironmentObject private var vm: LumisViewModel
    @EnvironmentObject private var macVM: MacConnectionViewModel

    var body: some View {
        ZStack(alignment: .bottom) {
            LumisColors.parchment.ignoresSafeArea()

            Group {
                switch vm.selectedTab {
                case .home:     HomeView()
                case .history:  HistoryView()
                case .camera:   CameraView(mode: vm.cameraMode ?? .manual)
                case .settings: SettingsView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if vm.selectedTab != .camera {
                LumisTabBar(selected: $vm.selectedTab) { tab in select(tab) }
                    .transition(.move(edge: .bottom))
            }
        }
        .onAppear {
            vm.start()
            macVM.startPolling()
        }
        .onDisappear {
            macVM.stopPolling()
        }
    }

    private func select(_ tab: LumisTab) {
        if tab == .camera {
            vm.openCameraManually()
        } else {
            vm.cameraMode = nil
            vm.selectedTab = tab
        }
    }
}
