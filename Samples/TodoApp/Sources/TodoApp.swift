import SwiftUI

@main
struct TodoApp: App {
    @StateObject private var service = InsForgeService.shared
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(service)
                .frame(minWidth: 800, minHeight: 600)
        }
        .defaultSize(width: 1000, height: 700)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}

// AppDelegate to handle window activation
class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Activate the application and bring windows to front
        NSApplication.shared.activate(ignoringOtherApps: true)

        // Make sure the main window becomes key
        if let window = NSApplication.shared.windows.first {
            window.makeKeyAndOrderFront(nil)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }
}

struct ContentView: View {
    @StateObject private var service = InsForgeService.shared

    var body: some View {
        Group {
            if service.isAuthenticated {
                TodoListView()
            } else {
                AuthView()
            }
        }
        .task {
            // Try to restore session
            do {
                try await service.getCurrentUser()
            } catch {
                // User not logged in
            }
        }
    }
}
