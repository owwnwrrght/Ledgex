import SwiftUI
import AuthenticationServices

struct ProfileSetupView: View {
    @ObservedObject var profileManager = ProfileManager.shared
    @State private var name = ""
    @State private var showingProfile = false
    
    var body: some View {
        NavigationView {
            VStack(spacing: 30) {
                VStack(spacing: 15) {
                    Image(systemName: "person.circle.fill")
                        .font(.system(size: 80))
                        .foregroundColor(.blue)
                    
                    Text("Welcome to Ledgex!")
                        .font(.title)
                        .fontWeight(.bold)
                    
                    Text("Let's start by setting up your profile. This will automatically add you to groups you create or join.")
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                
                VStack(spacing: 15) {
                    TextField("Your name", text: $name)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .font(.title3)
                    
                    Button("Get Started") {
                        profileManager.createProfile(name: name)
                    }
                    .buttonStyle(.borderedProminent)
                    .font(.headline)
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .padding(.horizontal, 40)
                
                Spacer()
            }
            .padding()
            .navigationTitle("Profile Setup")
            .onAppear {
                if let profile = profileManager.currentProfile {
                    name = profile.name
                }
            }
        }
    }
}

struct ProfileView: View {
    @EnvironmentObject private var authViewModel: AuthViewModel
    @ObservedObject var profileManager = ProfileManager.shared
    @ObservedObject var notificationService = NotificationService.shared
    @Environment(\.dismiss) var dismiss
    @State private var name = ""
    @State private var preferredCurrency: Currency = .USD
    @State private var notificationsEnabled = true
    @State private var showingDeleteConfirmation = false
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Profile Information")) {
                    TextField("Your name", text: $name)
                    
                    Picker("Preferred Currency", selection: $preferredCurrency) {
                        ForEach(Currency.allCases, id: \.self) { currency in
                            Text(currency.displayName).tag(currency)
                        }
                    }
                }
                
                Section(header: Text("Notifications")) {
                    Toggle("Enable Notifications", isOn: $notificationsEnabled)
                        .onChange(of: notificationsEnabled) { newValue in
                            profileManager.setNotificationsEnabled(newValue)
                            if newValue {
                                Task {
                                    await notificationService.requestPermissions()
                                }
                            }
                        }
                    
                    if notificationsEnabled && notificationService.hasPermission {
                        HStack {
                            Text("Notification Status")
                            Spacer()
                            Label("Active", systemImage: "checkmark.circle.fill")
                                .foregroundColor(.green)
                                .font(.caption)
                        }
                    }
                }
                
                
                Section(footer: Text("This name will be automatically added to groups you create or join.")) {
                    EmptyView()
                }
                
                Section(header: Text("Account")) {
                    if authViewModel.isProcessing {
                        ProgressView("Working…")
                            .progressViewStyle(CircularProgressViewStyle())
                    }

                    if let message = authViewModel.errorMessage, !message.isEmpty {
                        Text(message)
                            .font(.footnote)
                            .foregroundColor(.red)
                            .multilineTextAlignment(.leading)
                    }

                    Button("Sign Out") {
                        authViewModel.signOut()
                        dismiss()
                    }
                    .disabled(authViewModel.isProcessing)

                    Button("Delete Account", role: .destructive) {
                        showingDeleteConfirmation = true
                    }
                    .disabled(authViewModel.isProcessing)
                }
            }
            .navigationTitle("My Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Save") {
                        profileManager.updateProfile(name: name.trimmingCharacters(in: .whitespacesAndNewlines), preferredCurrency: preferredCurrency)
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .onAppear {
            if let profile = profileManager.currentProfile {
                name = profile.name
                preferredCurrency = profile.preferredCurrency
                notificationsEnabled = profile.notificationsEnabled
            }
        }
        .alert("Delete Account?", isPresented: $showingDeleteConfirmation) {
            Button("Delete", role: .destructive) {
                authViewModel.initiateAccountDeletion()
            }
            Button("Cancel", role: .cancel) {
                showingDeleteConfirmation = false
            }
        } message: {
            Text("This will permanently remove your Ledgex account and associated data.")
        }
        .sheet(isPresented: $authViewModel.showAccountDeletionReauthSheet) {
            AccountDeletionReauthSheet()
                .environmentObject(authViewModel)
        }
        .sheet(isPresented: $authViewModel.requiresEmailReauth) {
            EmailAccountDeletionReauthSheet()
                .environmentObject(authViewModel)
        }
    }
}

struct AccountDeletionReauthSheet: View {
    @EnvironmentObject private var authViewModel: AuthViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                Image(systemName: "lock.shield")
                    .font(.system(size: 48, weight: .thin))
                    .foregroundColor(.blue)

                Text("Confirm Account Deletion")
                    .font(.title2)
                    .fontWeight(.semibold)

                Text("For your security, Apple needs to confirm it's really you before we remove your Ledgex account.")
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .foregroundColor(.secondary)
                    .padding(.horizontal)

                if authViewModel.isProcessing {
                    ProgressView("Verifying…")
                }

                SignInWithAppleButton(.continue) { request in
                    authViewModel.prepareAccountDeletionReauthRequest(request)
                } onCompletion: { result in
                    authViewModel.handleSignInCompletion(result)
                }
                .signInWithAppleButtonStyle(.black)
                .frame(height: 50)
                .cornerRadius(12)
                .disabled(authViewModel.isProcessing)

                if let message = authViewModel.errorMessage, !message.isEmpty {
                    Text(message)
                        .font(.footnote)
                        .foregroundColor(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }

                Button("Cancel", role: .cancel) {
                    authViewModel.cancelAccountDeletionReauth()
                    dismiss()
                }
                .disabled(authViewModel.isProcessing)

                Spacer()
            }
            .padding()
            .navigationTitle("Reauthenticate")
            .navigationBarTitleDisplayMode(.inline)
        }
        .onDisappear {
            authViewModel.cancelAccountDeletionReauth()
        }
        .interactiveDismissDisabled(authViewModel.isProcessing)
    }
}

struct EmailAccountDeletionReauthSheet: View {
    @EnvironmentObject private var authViewModel: AuthViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            VStack(spacing: 16) {
                Image(systemName: "envelope.badge.shield.leadinghalf.fill")
                    .font(.system(size: 48, weight: .regular))
                    .foregroundColor(.blue)

                Text("Confirm With Password")
                    .font(.title3)
                    .fontWeight(.semibold)

                Text("Enter your email and password to confirm account deletion.")
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .foregroundColor(.secondary)
                    .padding(.horizontal)

                TextField("Email", text: $authViewModel.reauthEmail)
                    .textContentType(.emailAddress)
                    .keyboardType(.emailAddress)
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
                    .padding()
                    .background(Color(uiColor: .secondarySystemBackground))
                    .cornerRadius(10)
                    .disabled(authViewModel.isProcessing)

                SecureField("Password", text: $authViewModel.reauthPassword)
                    .textContentType(.password)
                    .padding()
                    .background(Color(uiColor: .secondarySystemBackground))
                    .cornerRadius(10)
                    .disabled(authViewModel.isProcessing)

                if let message = authViewModel.emailReauthError, !message.isEmpty {
                    Text(message)
                        .font(.footnote)
                        .foregroundColor(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }

                if authViewModel.isProcessing {
                    ProgressView("Deleting…")
                }

                Button("Confirm Deletion", role: .destructive) {
                    authViewModel.confirmEmailAccountDeletion()
                }
                .disabled(authViewModel.isProcessing)
                .buttonStyle(.borderedProminent)

                Button("Cancel", role: .cancel) {
                    authViewModel.cancelEmailReauth()
                    dismiss()
                }
                .disabled(authViewModel.isProcessing)

                Spacer()
            }
            .padding()
            .navigationTitle("Reauthenticate")
            .navigationBarTitleDisplayMode(.inline)
        }
        .onDisappear {
            authViewModel.cancelEmailReauth()
        }
        .interactiveDismissDisabled(authViewModel.isProcessing)
    }
}
