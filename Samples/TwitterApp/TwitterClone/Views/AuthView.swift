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
    @State private var showForgotPassword = false

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

            Button("Forgot Password?") {
                showForgotPassword = true
            }
            .foregroundColor(.secondary)
            .font(.subheadline)

            // Divider with "or"
            HStack {
                Rectangle()
                    .fill(Color.gray.opacity(0.3))
                    .frame(height: 1)
                Text("or")
                    .foregroundColor(.secondary)
                    .font(.subheadline)
                Rectangle()
                    .fill(Color.gray.opacity(0.3))
                    .frame(height: 1)
            }
            .padding(.vertical, 5)

            // OAuth Sign In Button
            Button(action: {
                Task {
                    await authViewModel.signInWithOAuth()
                }
            }) {
                HStack(spacing: 12) {
                    Image(systemName: "globe")
                        .font(.title3)
                    Text("Continue with Google / GitHub")
                }
                .frame(maxWidth: .infinity)
                .padding()
            }
            .buttonStyle(.bordered)
            .tint(.primary)

            Button("Don't have an account? Sign Up") {
                isSignUp = true
            }
            .foregroundColor(.blue)
        }
        .sheet(isPresented: $showForgotPassword) {
            ForgotPasswordView()
                .environmentObject(authViewModel)
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

struct ForgotPasswordView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var authViewModel: AuthViewModel

    @State private var email = ""
    @State private var otp = ""
    @State private var newPassword = ""
    @State private var confirmPassword = ""
    @State private var step: ResetStep = .enterEmail
    @State private var successMessage: String?

    enum ResetStep {
        case enterEmail
        case enterOTP
        case success
    }

    var passwordsMatch: Bool {
        newPassword == confirmPassword && !newPassword.isEmpty
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 25) {
                // Icon
                Image(systemName: step == .success ? "checkmark.circle.fill" : "lock.rotation")
                    .font(.system(size: 50))
                    .foregroundColor(step == .success ? .green : .blue)
                    .padding(.top, 30)

                switch step {
                case .enterEmail:
                    enterEmailView
                case .enterOTP:
                    enterOTPView
                case .success:
                    successView
                }

                Spacer()
            }
            .padding()
            .navigationTitle("Reset Password")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }

    private var enterEmailView: some View {
        VStack(spacing: 20) {
            Text("Enter your email address and we'll send you a code to reset your password.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            TextField("Email", text: $email)
                .textFieldStyle(.roundedBorder)
                .textContentType(.emailAddress)
                .autocapitalization(.none)
                .keyboardType(.emailAddress)

            if let error = authViewModel.errorMessage {
                Text(error)
                    .foregroundColor(.red)
                    .font(.caption)
                    .multilineTextAlignment(.center)
            }

            Button(action: {
                Task {
                    let success = await authViewModel.sendPasswordReset(email: email)
                    if success {
                        step = .enterOTP
                    }
                }
            }) {
                if authViewModel.isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                } else {
                    Text("Send Reset Code")
                }
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(email.isEmpty ? Color.gray : Color.blue)
            .foregroundColor(.white)
            .cornerRadius(10)
            .disabled(email.isEmpty || authViewModel.isLoading)
        }
    }

    private var enterOTPView: some View {
        VStack(spacing: 20) {
            Text("We sent a verification code to \(email). Enter the code and your new password below.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            VStack(spacing: 15) {
                TextField("Verification Code", text: $otp)
                    .textFieldStyle(.roundedBorder)
                    .textContentType(.oneTimeCode)
                    .keyboardType(.numberPad)

                SecureField("New Password", text: $newPassword)
                    .textFieldStyle(.roundedBorder)
                    .textContentType(.newPassword)

                SecureField("Confirm New Password", text: $confirmPassword)
                    .textFieldStyle(.roundedBorder)
                    .textContentType(.newPassword)

                if !confirmPassword.isEmpty && !passwordsMatch {
                    Text("Passwords don't match")
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
                    let success = await authViewModel.resetPassword(otp: otp, newPassword: newPassword)
                    if success {
                        step = .success
                    }
                }
            }) {
                if authViewModel.isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                } else {
                    Text("Reset Password")
                }
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(otp.isEmpty || !passwordsMatch ? Color.gray : Color.blue)
            .foregroundColor(.white)
            .cornerRadius(10)
            .disabled(otp.isEmpty || !passwordsMatch || authViewModel.isLoading)

            Button("Resend Code") {
                Task {
                    _ = await authViewModel.sendPasswordReset(email: email)
                }
            }
            .foregroundColor(.blue)
            .font(.subheadline)
        }
    }

    private var successView: some View {
        VStack(spacing: 20) {
            Text("Password Reset Successfully!")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Your password has been updated. You can now sign in with your new password.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            Button("Back to Sign In") {
                dismiss()
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color.blue)
            .foregroundColor(.white)
            .cornerRadius(10)
        }
    }
}

#Preview {
    AuthView()
        .environmentObject(AuthViewModel())
}
