import SwiftUI

struct AuthView: View {
    @State private var isSignUp = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 30) {
                // Logo
                VStack(spacing: 10) {
                    Image(systemName: "bird.fill")
                        .font(.system(size: 60))
                        .foregroundColor(.blue)

                    Text("Twitter Clone")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                }
                .padding(.top, 60)

                Spacer()

                if isSignUp {
                    SignUpView(isSignUp: $isSignUp)
                } else {
                    SignInView(isSignUp: $isSignUp)
                }

                Spacer()
            }
            .padding()
        }
    }
}

struct SignInView: View {
    @EnvironmentObject var authViewModel: AuthViewModel
    @Binding var isSignUp: Bool

    @State private var email = ""
    @State private var password = ""

    var body: some View {
        VStack(spacing: 20) {
            Text("Sign in to continue")
                .font(.headline)
                .foregroundColor(.secondary)

            VStack(spacing: 15) {
                TextField("Email", text: $email)
                    .textFieldStyle(.roundedBorder)
                    .textContentType(.emailAddress)
                    .autocapitalization(.none)
                    .keyboardType(.emailAddress)

                SecureField("Password", text: $password)
                    .textFieldStyle(.roundedBorder)
                    .textContentType(.password)
            }

            if let error = authViewModel.errorMessage {
                Text(error)
                    .foregroundColor(.red)
                    .font(.caption)
                    .multilineTextAlignment(.center)
            }

            Button(action: {
                Task {
                    await authViewModel.signIn(email: email, password: password)
                }
            }) {
                if authViewModel.isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                } else {
                    Text("Sign In")
                }
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color.blue)
            .foregroundColor(.white)
            .cornerRadius(10)
            .disabled(email.isEmpty || password.isEmpty || authViewModel.isLoading)

            Button("Don't have an account? Sign Up") {
                isSignUp = true
            }
            .foregroundColor(.blue)
        }
    }
}

struct SignUpView: View {
    @EnvironmentObject var authViewModel: AuthViewModel
    @Binding var isSignUp: Bool

    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var username = ""
    @State private var displayName = ""

    var passwordsMatch: Bool {
        password == confirmPassword && !password.isEmpty
    }

    var isFormValid: Bool {
        !email.isEmpty &&
        !password.isEmpty &&
        passwordsMatch &&
        !username.isEmpty &&
        !displayName.isEmpty &&
        username.count >= 3
    }

    var body: some View {
        VStack(spacing: 20) {
            Text("Create your account")
                .font(.headline)
                .foregroundColor(.secondary)

            VStack(spacing: 15) {
                TextField("Display Name", text: $displayName)
                    .textFieldStyle(.roundedBorder)
                    .textContentType(.name)

                TextField("Username (no spaces)", text: $username)
                    .textFieldStyle(.roundedBorder)
                    .textContentType(.username)
                    .autocapitalization(.none)
                    .onChange(of: username) { _, newValue in
                        username = newValue.lowercased().replacingOccurrences(of: " ", with: "")
                    }

                TextField("Email", text: $email)
                    .textFieldStyle(.roundedBorder)
                    .textContentType(.emailAddress)
                    .autocapitalization(.none)
                    .keyboardType(.emailAddress)

                SecureField("Password", text: $password)
                    .textFieldStyle(.roundedBorder)
                    .textContentType(.newPassword)

                SecureField("Confirm Password", text: $confirmPassword)
                    .textFieldStyle(.roundedBorder)
                    .textContentType(.newPassword)

                if !confirmPassword.isEmpty && !passwordsMatch {
                    Text("Passwords don't match")
                        .foregroundColor(.red)
                        .font(.caption)
                }

                if !username.isEmpty && username.count < 3 {
                    Text("Username must be at least 3 characters")
                        .foregroundColor(.red)
                        .font(.caption)
                }
            }

            if let error = authViewModel.errorMessage {
                Text(error)
                    .foregroundColor(.red)
                    .font(.caption)
                    .multilineTextAlignment(.center)
            }

            Button(action: {
                Task {
                    await authViewModel.signUp(
                        email: email,
                        password: password,
                        username: username,
                        displayName: displayName
                    )
                }
            }) {
                if authViewModel.isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                } else {
                    Text("Create Account")
                }
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(isFormValid ? Color.blue : Color.gray)
            .foregroundColor(.white)
            .cornerRadius(10)
            .disabled(!isFormValid || authViewModel.isLoading)

            Button("Already have an account? Sign In") {
                isSignUp = false
            }
            .foregroundColor(.blue)
        }
    }
}

#Preview {
    AuthView()
        .environmentObject(AuthViewModel())
}
