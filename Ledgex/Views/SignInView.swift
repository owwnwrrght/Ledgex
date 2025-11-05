import AuthenticationServices
import SwiftUI

struct SignInView: View {
    @EnvironmentObject private var authViewModel: AuthViewModel
    @State private var showDebugLog = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // Header Section
            VStack(spacing: 16) {
                Image(systemName: "banknote.fill")
                    .font(.system(size: 56, weight: .medium))
                    .foregroundColor(Color(red: 0.2, green: 0.3, blue: 0.5))

                Text("Ledgex")
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundColor(.primary)

                Text("Simplify your group expenses")
                    .font(.system(size: 15))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.bottom, 48)

            // Sign In Buttons Section
            VStack(spacing: 16) {
                if authViewModel.currentFlow == .signInWithApple {
                    // Social Sign In Buttons
                    VStack(spacing: 12) {
                        appleSignInButton
                        googleSignInButton
                    }
                    .padding(.horizontal, 32)

                    // Divider
                    HStack {
                        Rectangle()
                            .fill(Color(.separator))
                            .frame(height: 0.5)
                        Text("or")
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 12)
                        Rectangle()
                            .fill(Color(.separator))
                            .frame(height: 0.5)
                    }
                    .padding(.horizontal, 32)
                    .padding(.vertical, 8)

                    // Email Option Button
                    Button(action: authViewModel.switchToEmailFlow) {
                        Text("Continue with Email")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(Color(red: 0.2, green: 0.3, blue: 0.5))
                    }
                    .padding(.top, 4)
                } else {
                    emailSignInForm
                }

                // Processing Indicator
                if authViewModel.isProcessing {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle())
                        .padding(.top, 16)
                }

                // Error Message
                if let message = authViewModel.errorMessage {
                    VStack(spacing: 8) {
                        Text(message)
                            .font(.system(size: 13))
                            .foregroundColor(.red)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                            .padding(.top, 16)

                        if !authViewModel.detailedErrorLog.isEmpty {
                            Button(action: { showDebugLog.toggle() }) {
                                HStack(spacing: 4) {
                                    Image(systemName: showDebugLog ? "chevron.down" : "chevron.right")
                                        .font(.caption2)
                                    Text("Debug Details")
                                        .font(.caption)
                                }
                                .foregroundColor(.blue)
                            }
                        }
                    }
                }

                // Debug Log
                if showDebugLog && !authViewModel.detailedErrorLog.isEmpty {
                    VStack(spacing: 8) {
                        HStack {
                            Text("Authentication Debug Log")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundColor(.secondary)
                            Spacer()
                            Button(action: copyDebugLog) {
                                HStack(spacing: 4) {
                                    Image(systemName: "doc.on.doc")
                                        .font(.caption2)
                                    Text("Copy")
                                        .font(.caption2)
                                }
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.mini)
                        }
                        .padding(.horizontal, 32)

                        ScrollView {
                            VStack(alignment: .leading, spacing: 4) {
                                ForEach(authViewModel.detailedErrorLog, id: \.self) { log in
                                    Text(log)
                                        .font(.system(.caption2, design: .monospaced))
                                        .foregroundColor(.secondary)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                            .padding(8)
                            .background(Color(.secondarySystemBackground).opacity(0.85))
                            .cornerRadius(8)
                        }
                        .frame(maxHeight: 200)
                        .padding(.horizontal, 32)
                    }
                }
            }

            Spacer()
            Spacer()
        }
        .background(
            WindowAccessor { window in
                authViewModel.updatePresentationAnchor(window)
            }
            .allowsHitTesting(false)
        )
        .ledgexBackground()
    }

    // MARK: - Apple Sign In Button
    private var appleSignInButton: some View {
        SignInWithAppleButton(.signIn) { request in
            print("🔐 [SignInView] Sign in with Apple button tapped")
            authViewModel.prepareSignInRequest(request)
        } onCompletion: { result in
            print("🔐 [SignInView] Sign in completion called")
            authViewModel.handleSignInCompletion(result)
        }
        .signInWithAppleButtonStyle(.black)
        .frame(height: 52)
        .cornerRadius(8)
        .disabled(authViewModel.isProcessing)
    }

    // MARK: - Google Sign In Button
    private var googleSignInButton: some View {
        Button(action: authViewModel.signInWithGoogle) {
            HStack(spacing: 12) {
                Image(systemName: "g.circle.fill")
                    .font(.system(size: 20))
                    .foregroundColor(.white)

                Text("Continue with Google")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.white)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(Color(red: 0.26, green: 0.52, blue: 0.96))
            .cornerRadius(8)
        }
        .disabled(authViewModel.isProcessing)
        .accessibilityLabel("Sign in with Google")
    }

    // MARK: - Email Sign In Form
    private var emailSignInForm: some View {
        VStack(spacing: 16) {
            VStack(spacing: 12) {
                TextField("Email", text: $authViewModel.email)
                    .textContentType(.emailAddress)
                    .keyboardType(.emailAddress)
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
                    .padding(16)
                    .background(Color(.systemGray6))
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color(.separator), lineWidth: 0.5)
                    )

                SecureField("Password", text: $authViewModel.password)
                    .textContentType(.password)
                    .padding(16)
                    .background(Color(.systemGray6))
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color(.separator), lineWidth: 0.5)
                    )
            }
            .padding(.horizontal, 32)

            VStack(spacing: 12) {
                Button(action: authViewModel.signInWithEmail) {
                    Text("Sign In")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(Color(red: 0.2, green: 0.3, blue: 0.5))
                        .cornerRadius(8)
                }
                .disabled(authViewModel.isProcessing)

                Button(action: authViewModel.signUpWithEmail) {
                    Text("Create Account")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(Color(red: 0.2, green: 0.3, blue: 0.5))
                }
                .disabled(authViewModel.isProcessing)
            }
            .padding(.horizontal, 32)

            Button(action: { authViewModel.currentFlow = .signInWithApple }) {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 12))
                    Text("Back")
                        .font(.system(size: 15))
                }
                .foregroundColor(.secondary)
            }
            .padding(.top, 8)
        }
    }

    private func copyDebugLog() {
        let logText = authViewModel.detailedErrorLog.joined(separator: "\n")
        UIPasteboard.general.string = logText
    }
}
