import SwiftUI
import InsForge

@main
struct TwitterCloneApp: App {
    @StateObject private var authViewModel = AuthViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(authViewModel)
                .onOpenURL { url in
                    Task {
                        await authViewModel.handleAuthCallback(url: url)
                    }
                }
        }
    }
}
