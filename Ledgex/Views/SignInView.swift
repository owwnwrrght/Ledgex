import AuthenticationServices
import SwiftUI

struct SignInView: View {
    @EnvironmentObject private var authViewModel: AuthViewModel
    @State private var showDebugLog = false
    
    var body: some View {
        VStack(spacing: 32) {
            Spacer()
            VStack(spacing: 12) {
                Image(systemName: "person.3.sequence")
                    .font(.system(size: 72, weight: .regular))
                    .foregroundStyle(LinearGradient.ledgexAccentBorder)
                Text("Sign in to Ledgex")
                    .font(.title)
                    .fontWeight(.bold)
                Text("Use Sign in with Apple for the fastest setup, or opt for email instead.")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }

            VStack(spacing: 16) {
                if authViewModel.currentFlow == .signInWithApple {
                    SignInWithAppleButton(.signIn) { request in
                        print("🔐 [SignInView] Sign in with Apple button tapped")
                        authViewModel.prepareSignInRequest(request)
                    } onCompletion: { result in
                        print("🔐 [SignInView] Sign in completion called")
                        authViewModel.handleSignInCompletion(result)
                    }
                    .signInWithAppleButtonStyle(.black)
                    .frame(height: 52)
                    .cornerRadius(12)
                    .disabled(authViewModel.isProcessing)

                    Button(action: authViewModel.switchToEmailFlow) {
                        Text("Prefer email and password?")
                            .font(.caption)
                            .underline()
                    }
                    .padding(.top, 4)
                } else {
                    emailSignInForm
                }

                if authViewModel.isProcessing {
                    ProgressView("Working…")
                        .progressViewStyle(CircularProgressViewStyle())
                }

                if let message = authViewModel.errorMessage {
                    VStack(spacing: 8) {
                        Text(message)
                            .font(.footnote)
                            .foregroundColor(.red)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)

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
                        .padding(.horizontal)

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
                            .ledgexOutlined(cornerRadius: 8)
                        }
                        .frame(maxHeight: 200)
                        .padding(.horizontal)
                    }
                }
            }
            Spacer()
        }
        .padding()
        .ledgexBackground()
    }

    private var emailSignInForm: some View {
        VStack(spacing: 12) {
            TextField("Email", text: $authViewModel.email)
                .textContentType(.emailAddress)
                .keyboardType(.emailAddress)
                .autocapitalization(.none)
                .disableAutocorrection(true)
                .padding()
                .background(Color(.secondarySystemBackground).opacity(0.92))
                .cornerRadius(12)
                .ledgexOutlined(cornerRadius: 12)

            SecureField("Password", text: $authViewModel.password)
                .textContentType(.password)
                .padding()
                .background(Color(.secondarySystemBackground).opacity(0.92))
                .cornerRadius(12)
                .ledgexOutlined(cornerRadius: 12)

            Button(action: authViewModel.signInWithEmail) {
                Text("Sign In")
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(LinearGradient.ledgexCallToAction)
                    .cornerRadius(14)
                    .shadow(color: Color.purple.opacity(0.18), radius: 8, x: 0, y: 6)
            }
            .disabled(authViewModel.isProcessing)

            Button(action: authViewModel.signUpWithEmail) {
                Text("Create a new account")
                    .font(.subheadline)
                    .foregroundColor(.blue)
                    .padding(.vertical, 6)
            }
            .disabled(authViewModel.isProcessing)

            Button(action: { authViewModel.currentFlow = .signInWithApple }) {
                Text("Back to Sign in with Apple")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.top, 8)
            }
        }
    }

    private func copyDebugLog() {
        let logText = authViewModel.detailedErrorLog.joined(separator: "\n")
        UIPasteboard.general.string = logText
    }
}
