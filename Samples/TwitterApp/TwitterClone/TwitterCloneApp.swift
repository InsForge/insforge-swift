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
                    // Handle OAuth callback
                    if url.scheme == AuthViewModel.oauthCallbackScheme {
                        Task {
                            await authViewModel.handleOAuthCallback(url: url)
                        }
                    }
                }
        }
    }
}
