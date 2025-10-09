import SwiftUI

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
        .sheet(isPresented: Binding(
            get: { authViewModel.requiresEmailReauth },
            set: { if !$0 { authViewModel.cancelEmailReauth() } }
        )) {
            EmailReauthSheet(authViewModel: authViewModel)
        }
    }
}

private struct EmailReauthSheet: View {
    @ObservedObject var authViewModel: AuthViewModel
    @FocusState private var passwordFocused: Bool

    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                VStack(spacing: 8) {
                    Text("Confirm Password")
                        .font(.title3)
                        .fontWeight(.semibold)

                    Text("Enter your password to delete your Ledgex account.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }

                VStack(alignment: .leading, spacing: 12) {
                    TextField("Email", text: Binding(
                        get: { authViewModel.reauthEmail },
                        set: { authViewModel.reauthEmail = $0 }
                    ))
                    .textContentType(.emailAddress)
                    .keyboardType(.emailAddress)
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
                    .padding(12)
                    .background(Color(uiColor: .secondarySystemBackground))
                    .cornerRadius(12)
                    .disabled(true)

                    SecureField("Password", text: Binding(
                        get: { authViewModel.reauthPassword },
                        set: { authViewModel.reauthPassword = $0 }
                    ))
                    .textContentType(.password)
                    .padding(12)
                    .background(Color(uiColor: .secondarySystemBackground))
                    .cornerRadius(12)
                    .focused($passwordFocused)

                    if let error = authViewModel.emailReauthError, !error.isEmpty {
                        Text(error)
                            .font(.footnote)
                            .foregroundColor(.red)
                    }
                }
                .padding(.horizontal)

                if authViewModel.isProcessing {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle())
                }

                HStack(spacing: 12) {
                    Button("Cancel") {
                        authViewModel.cancelEmailReauth()
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color(uiColor: .secondarySystemBackground))
                    .cornerRadius(12)

                    Button("Delete Account", role: .destructive) {
                        authViewModel.confirmEmailAccountDeletion()
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.red)
                    .cornerRadius(12)
                    .foregroundColor(.white)
                    .disabled(authViewModel.isProcessing)
                }
                .padding(.horizontal)

                Spacer()
            }
            .padding(.top, 32)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        authViewModel.cancelEmailReauth()
                    }
                }
            }
        }
    }
}
