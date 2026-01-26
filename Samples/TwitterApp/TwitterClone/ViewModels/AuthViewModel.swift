import Foundation
import SwiftUI
import InsForge
import InsForgeAuth

@MainActor
class AuthViewModel: ObservableObject {
    @Published var currentUser: InsForgeAuth.User?
    @Published var currentProfile: Profile?
    @Published var isLoading = false
    @Published var isAuthenticated = false
    @Published var errorMessage: String?

    private var client: InsForgeClient { insforge }

    init() {
        Task {
            await checkSession()
        }
    }

    func checkSession() async {
        isLoading = true
        defer { isLoading = false }

        do {
            let user = try await client.auth.getCurrentUser()
            self.currentUser = user
            self.isAuthenticated = true
            await loadProfile()
        } catch {
            print("Session check failed: \(error)")
        }
    }

    func signUp(email: String, password: String, username: String, displayName: String) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let result = try await client.auth.signUp(
                email: email,
                password: password,
                name: displayName
            )

            self.currentUser = result.user
            self.isAuthenticated = true

            // Create profile
            let profileInsert = ProfileInsert(
                userId: result.user.id,
                username: username,
                displayName: displayName
            )

            let _: ProfileInsert = try await client.database
                .from("profiles")
                .insert(profileInsert)

            await loadProfile()
        } catch {
            errorMessage = "Sign up failed: \(error.localizedDescription)"
        }
    }

    func signIn(email: String, password: String) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let result = try await client.auth.signIn(
                email: email,
                password: password
            )

            self.currentUser = result.user
            self.isAuthenticated = true
            await loadProfile()
        } catch {
            errorMessage = "Sign in failed: \(error.localizedDescription)"
        }
    }

    func signOut() async {
        isLoading = true
        defer { isLoading = false }

        do {
            try await client.auth.signOut()
            self.currentUser = nil
            self.currentProfile = nil
            self.isAuthenticated = false
        } catch {
            errorMessage = "Sign out failed: \(error.localizedDescription)"
        }
    }

    func handleAuthCallback(url: URL) async {
        do {
            let response = try await client.auth.handleAuthCallback(url)
            self.currentUser = response.user
            self.isAuthenticated = true
            await loadProfile()
        } catch {
            errorMessage = "Auth callback failed: \(error.localizedDescription)"
        }
    }

    private func loadProfile() async {
        guard let userId = currentUser?.id else { return }

        do {
            let profiles: [Profile] = try await client.database
                .from("profiles")
                .select()
                .eq("user_id", value: userId)
                .execute()

            if let profile = profiles.first {
                self.currentProfile = profile
            }
        } catch {
            print("Failed to load profile: \(error)")
        }
    }

    func updateProfile(_ update: ProfileUpdate) async {
        guard let userId = currentUser?.id else { return }

        do {
            let _: [ProfileUpdate] = try await client.database
                .from("profiles")
                .eq("user_id", value: userId)
                .update(update)

            await loadProfile()
        } catch {
            errorMessage = "Failed to update profile: \(error.localizedDescription)"
        }
    }

    // MARK: - OAuth Sign In

    /// URL scheme for OAuth callback (must match Info.plist CFBundleURLSchemes)
    static let oauthCallbackScheme = "twitterclone"
    static let oauthRedirectURL = "\(oauthCallbackScheme)://auth/callback"

    /// Sign in with OAuth provider
    /// Uses ASWebAuthenticationSession (in-app browser) when available, falls back to external browser
    func signInWithOAuth() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            if let response = try await client.auth.signInWithDefaultView(redirectTo: Self.oauthRedirectURL) {
                // ASWebAuthenticationSession completed successfully
                self.currentUser = response.user
                self.isAuthenticated = true
                // Check if profile exists, if not create one
                await loadOrCreateProfile(user: response.user)
            }
            // If nil, external browser was opened - app will receive callback via URL scheme
        } catch {
            errorMessage = "OAuth sign in failed: \(error.localizedDescription)"
        }
    }

    /// Handle OAuth callback from external browser (fallback when ASWebAuthenticationSession is not available)
    /// This is called when the app receives a URL via the registered URL scheme
    func handleOAuthCallback(url: URL) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let response = try await client.auth.handleAuthCallback(url)
            self.currentUser = response.user
            self.isAuthenticated = true

            // Check if profile exists, if not create one
            await loadOrCreateProfile(user: response.user)
        } catch {
            errorMessage = "OAuth sign in failed: \(error.localizedDescription)"
        }
    }

    /// Load existing profile or create new one for OAuth users
    private func loadOrCreateProfile(user: InsForgeAuth.User) async {
        do {
            let profiles: [Profile] = try await client.database
                .from("profiles")
                .select()
                .eq("user_id", value: user.id)
                .execute()

            if let profile = profiles.first {
                self.currentProfile = profile
            } else {
                // Create profile for new OAuth user
                let username = generateUsername(from: user.email)
                let displayName = user.name ?? username

                let profileInsert = ProfileInsert(
                    userId: user.id,
                    username: username,
                    displayName: displayName
                )

                let _: ProfileInsert = try await client.database
                    .from("profiles")
                    .insert(profileInsert)

                await loadProfile()
            }
        } catch {
            print("Failed to load/create profile: \(error)")
        }
    }

    /// Generate a username from email
    private func generateUsername(from email: String) -> String {
        let base = email.components(separatedBy: "@").first ?? "user"
        let cleaned = base.lowercased().replacingOccurrences(of: "[^a-z0-9]", with: "", options: .regularExpression)
        let timestamp = Int(Date().timeIntervalSince1970) % 10000
        return "\(cleaned)\(timestamp)"
    }

    // MARK: - Password Reset

    func sendPasswordReset(email: String) async -> Bool {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            try await client.auth.sendPasswordReset(email: email)
            return true
        } catch {
            errorMessage = "Failed to send reset email: \(error.localizedDescription)"
            return false
        }
    }

    func resetPassword(otp: String, newPassword: String) async -> Bool {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            try await client.auth.resetPassword(otp: otp, newPassword: newPassword)
            return true
        } catch {
            errorMessage = "Failed to reset password: \(error.localizedDescription)"
            return false
        }
    }
}
