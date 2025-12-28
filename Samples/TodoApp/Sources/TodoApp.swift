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
                .onOpenURL { url in
                    print("[TodoApp] Received URL: \(url)")
                    // Handle OAuth callback
                    if url.scheme == "todoapp" && url.host == "auth" {
                        Task {
                            do {
                                try await service.handleOAuthCallback(url)
                                print("[TodoApp] OAuth authentication successful")
                            } catch {
                                print("[TodoApp] OAuth authentication failed: \(error)")
                            }
                        }
                    }
                }
        }
        .defaultSize(width: 1000, height: 700)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}

// AppDelegate to handle window activation and URL events
class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Register URL event handler
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleURLEvent(_:replyEvent:)),
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL)
        )

        // Activate the application and bring windows to front
        NSApplication.shared.activate(ignoringOtherApps: true)

        // Make sure the main window becomes key
        if let window = NSApplication.shared.windows.first {
            window.makeKeyAndOrderFront(nil)
        }

        print("[AppDelegate] Application finished launching, URL handler registered")
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }

    @objc func handleURLEvent(_ event: NSAppleEventDescriptor, replyEvent: NSAppleEventDescriptor) {
        guard let urlString = event.paramDescriptor(forKeyword: AEKeyword(keyDirectObject))?.stringValue,
              let url = URL(string: urlString) else {
            print("[AppDelegate] Failed to extract URL from event")
            return
        }

        print("[AppDelegate] Received URL event: \(url)")

        // Handle OAuth callback
        if url.scheme == "todoapp" && url.host == "auth" {
            Task {
                do {
                    try await InsForgeService.shared.handleOAuthCallback(url)
                    print("[AppDelegate] OAuth authentication successful")
                } catch {
                    print("[AppDelegate] OAuth authentication failed: \(error)")
                }
            }
        }
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
