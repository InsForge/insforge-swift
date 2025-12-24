import SwiftUI

struct AuthView: View {
    @StateObject private var service = InsForgeService.shared
    @State private var isSignUp = false
    @State private var email = ""
    @State private var password = ""
    @State private var name = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @FocusState private var focusedField: Field?

    enum Field: Hashable {
        case name, email, password
    }

    var body: some View {
        VStack(spacing: 20) {
            // Logo/Title
            VStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 60))
                    .foregroundColor(.blue)
                Text("Todo App")
                    .font(.largeTitle)
                    .fontWeight(.bold)
            }
            .padding(.bottom, 40)

            // Form
            VStack(spacing: 16) {
                if isSignUp {
                    TextField("Name", text: $name)
                        .textFieldStyle(.roundedBorder)
                        .focused($focusedField, equals: .name)
                        .onSubmit { focusedField = .email }
                }

                TextField("Email", text: $email)
                    .textFieldStyle(.roundedBorder)
                    .focused($focusedField, equals: .email)
                    .onSubmit { focusedField = .password }

                SecureField("Password", text: $password)
                    .textFieldStyle(.roundedBorder)
                    .focused($focusedField, equals: .password)
                    .onSubmit {
                        if isFormValid {
                            handleAuth()
                        }
                    }
            }
            .frame(maxWidth: 300)
            .onAppear {
                // Auto-focus first field
                focusedField = isSignUp ? .name : .email
            }

            // Error message
            if let errorMessage = errorMessage {
                Text(errorMessage)
                    .foregroundColor(.red)
                    .font(.caption)
                    .multilineTextAlignment(.center)
            }

            // Submit button
            Button(action: handleAuth) {
                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Text(isSignUp ? "Sign Up" : "Sign In")
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(isLoading || !isFormValid)
            .frame(maxWidth: 300)

            // Toggle sign up/in
            Button(action: { isSignUp.toggle() }) {
                Text(isSignUp ? "Already have an account? Sign In" : "Don't have an account? Sign Up")
                    .font(.caption)
            }
            .buttonStyle(.plain)
        }
        .padding(40)
        .frame(width: 450, height: 500)
    }

    private var isFormValid: Bool {
        !email.isEmpty && !password.isEmpty && (!isSignUp || !name.isEmpty)
    }

    private func handleAuth() {
        Task {
            isLoading = true
            errorMessage = nil

            print("[AuthView] Starting authentication: \(isSignUp ? "Sign Up" : "Sign In")")
            print("[AuthView] Email: \(email)")

            do {
                if isSignUp {
                    print("[AuthView] Calling signUp...")
                    try await service.signUp(email: email, password: password, name: name)
                    print("[AuthView] Sign up successful!")
                } else {
                    print("[AuthView] Calling signIn...")
                    try await service.signIn(email: email, password: password)
                    print("[AuthView] Sign in successful!")
                }
            } catch let error as DecodingError {
                // Detailed decoding error
                print("[AuthView] DecodingError: \(error)")
                switch error {
                case .keyNotFound(let key, let context):
                    errorMessage = "Missing key '\(key.stringValue)' in response: \(context.debugDescription)"
                case .typeMismatch(let type, let context):
                    errorMessage = "Type mismatch for \(type): \(context.debugDescription)"
                case .valueNotFound(let type, let context):
                    errorMessage = "Value not found for \(type): \(context.debugDescription)"
                case .dataCorrupted(let context):
                    errorMessage = "Data corrupted: \(context.debugDescription)"
                @unknown default:
                    errorMessage = "Decoding error: \(error.localizedDescription)"
                }
                print("[AuthView] Error message: \(errorMessage ?? "unknown")")
            } catch {
                print("[AuthView] Error: \(error)")
                errorMessage = error.localizedDescription
            }

            isLoading = false
        }
    }
}
