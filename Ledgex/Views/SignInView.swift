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
                    .foregroundColor(.blue)
                Text("Sign in to Ledgex")
                    .font(.title)
                    .fontWeight(.bold)
                Text("Use Sign in with Apple to securely access your shared groups and expenses.")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }

            VStack(spacing: 16) {
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

                if authViewModel.isProcessing {
                    ProgressView("Signing in…")
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
                            .background(Color(uiColor: .secondarySystemBackground))
                            .cornerRadius(8)
                        }
                        .frame(maxHeight: 200)
                        .padding(.horizontal)
                    }
                }
            }
            Spacer()
        }
        .padding()
        .background(Color(uiColor: .systemBackground))
    }

    private func copyDebugLog() {
        let logText = authViewModel.detailedErrorLog.joined(separator: "\n")
        UIPasteboard.general.string = logText
    }
}
