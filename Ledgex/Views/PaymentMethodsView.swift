import SwiftUI

struct PaymentMethodsView: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject private var profileManager = ProfileManager.shared
    @StateObject private var paymentService = PaymentService.shared

    @State private var showingAddAccount = false
    @State private var selectedProvider: PaymentProvider?
    @State private var accountIdentifier = ""
    @State private var accountDisplayName = ""
    @State private var isAddingAccount = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationView {
            List {
                linkedAccountsSection
                availableProvidersSection
                informationSection
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Payment Methods")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $showingAddAccount) {
                addAccountSheet
            }
        }
    }

    // MARK: - Linked Accounts Section

    @ViewBuilder
    private var linkedAccountsSection: some View {
        if let profile = profileManager.currentProfile, !profile.linkedPaymentAccounts.isEmpty {
            Section {
                ForEach(profile.linkedPaymentAccounts) { account in
                    linkedAccountRow(account)
                }
                .onDelete(perform: deleteAccount)
            } header: {
                Text("Linked Accounts")
            } footer: {
                Text("These payment methods can be used for quick settlements")
            }
        }
    }

    @ViewBuilder
    private func linkedAccountRow(_ account: LinkedPaymentAccount) -> some View {
        HStack(spacing: 16) {
            // Provider icon
            ZStack {
                Circle()
                    .fill(providerColor(account.provider).opacity(0.15))
                    .frame(width: 44, height: 44)
                Image(systemName: systemIcon(for: account.provider))
                    .font(.system(size: 20))
                    .foregroundColor(providerColor(account.provider))
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(account.provider.displayName)
                    .font(.body)
                    .fontWeight(.semibold)

                Text(account.formattedIdentifier)
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                if account.isVerified {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.shield.fill")
                            .font(.caption2)
                        Text("Verified")
                            .font(.caption)
                    }
                    .foregroundColor(.green)
                }
            }

            Spacer()

            if profileManager.currentProfile?.defaultPaymentProvider == account.provider {
                Text("Default")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.blue)
                    .cornerRadius(6)
            }
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .onTapGesture {
            setAsDefault(account.provider)
        }
    }

    // MARK: - Available Providers Section

    @ViewBuilder
    private var availableProvidersSection: some View {
        Section {
            ForEach(PaymentProvider.allCases, id: \.self) { provider in
                if provider != .manual {
                    availableProviderRow(provider)
                }
            }
        } header: {
            Text("Add Payment Method")
        } footer: {
            Text("Link your accounts for instant payments within the app")
        }
    }

    @ViewBuilder
    private func availableProviderRow(_ provider: PaymentProvider) -> some View {
        Button {
            selectedProvider = provider
            showingAddAccount = true
        } label: {
            HStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(providerColor(provider).opacity(0.15))
                        .frame(width: 44, height: 44)
                    Image(systemName: systemIcon(for: provider))
                        .font(.system(size: 20))
                        .foregroundColor(providerColor(provider))
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(provider.displayName)
                        .font(.body)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)

                    if !paymentService.isProviderAvailable(provider) {
                        HStack(spacing: 4) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.caption2)
                            Text("App not installed")
                                .font(.caption)
                        }
                        .foregroundColor(.orange)
                    }
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.vertical, 8)
        }
        .disabled(!paymentService.isProviderAvailable(provider) && provider.isDeepLinkBased)
    }

    // MARK: - Information Section

    @ViewBuilder
    private var informationSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                InfoRow(icon: "lock.shield.fill", text: "Your payment information is encrypted and secure")
                InfoRow(icon: "creditcard.fill", text: "Link accounts once, use for all settlements")
                InfoRow(icon: "arrow.left.arrow.right", text: "Payments happen instantly through your linked apps")
                InfoRow(icon: "checkmark.circle.fill", text: "Settlements are automatically marked as complete")
            }
            .padding(.vertical, 8)
        } header: {
            Text("How It Works")
        }
    }

    // MARK: - Add Account Sheet

    @ViewBuilder
    private var addAccountSheet: some View {
        NavigationView {
            Form {
                if let provider = selectedProvider {
                    Section {
                        HStack {
                            Spacer()
                            VStack(spacing: 12) {
                                ZStack {
                                    Circle()
                                        .fill(providerColor(provider).opacity(0.15))
                                        .frame(width: 80, height: 80)
                                    Image(systemName: systemIcon(for: provider))
                                        .font(.system(size: 40))
                                        .foregroundColor(providerColor(provider))
                                }
                                Text("Link \(provider.displayName)")
                                    .font(.headline)
                            }
                            .padding(.vertical)
                            Spacer()
                        }
                    }

                    Section {
                        TextField(placeholderText(for: provider), text: $accountIdentifier)
                            .textContentType(.emailAddress)
                            .autocapitalization(.none)
                            .autocorrectionDisabled()

                        TextField("Display Name (Optional)", text: $accountDisplayName)
                            .textContentType(.name)
                    } header: {
                        Text("Account Details")
                    } footer: {
                        Text(footerText(for: provider))
                    }

                    if let errorMessage = errorMessage {
                        Section {
                            HStack(spacing: 8) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundColor(.red)
                                Text(errorMessage)
                                    .font(.subheadline)
                                    .foregroundColor(.red)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Add Payment Method")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        resetAddAccountForm()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        addAccount()
                    } label: {
                        if isAddingAccount {
                            ProgressView()
                        } else {
                            Text("Add")
                        }
                    }
                    .disabled(accountIdentifier.isEmpty || isAddingAccount)
                }
            }
        }
    }

    // MARK: - Helper Functions

    private func placeholderText(for provider: PaymentProvider) -> String {
        switch provider {
        case .venmo, .cashApp:
            return "Username (e.g., @username)"
        case .paypal:
            return "PayPal.me username"
        case .zelle:
            return "Email or Phone"
        case .applePay:
            return "Apple ID Email"
        case .manual:
            return "Account identifier"
        }
    }

    private func footerText(for provider: PaymentProvider) -> String {
        switch provider {
        case .venmo:
            return "Enter your Venmo username (with or without @)"
        case .cashApp:
            return "Enter your Cash App $Cashtag"
        case .paypal:
            return "Enter your PayPal.me username (e.g., JohnDoe for paypal.me/JohnDoe)"
        case .zelle:
            return "Enter the email or phone number linked to your Zelle account"
        case .applePay:
            return "Enter your Apple ID email for Apple Pay Cash"
        case .manual:
            return "Enter your account identifier"
        }
    }

    private func systemIcon(for provider: PaymentProvider) -> String {
        switch provider {
        case .applePay: return "apple.logo"
        case .venmo: return "v.circle.fill"
        case .paypal: return "p.circle.fill"
        case .zelle: return "z.circle.fill"
        case .cashApp: return "dollarsign.circle.fill"
        case .manual: return "creditcard.fill"
        }
    }

    private func providerColor(_ provider: PaymentProvider) -> Color {
        switch provider {
        case .applePay: return .black
        case .venmo: return .blue
        case .paypal: return Color(red: 0.0, green: 0.3, blue: 0.6)
        case .zelle: return Color(red: 0.4, green: 0.0, blue: 0.6)
        case .cashApp: return .green
        case .manual: return .gray
        }
    }

    private func addAccount() {
        guard let provider = selectedProvider, !accountIdentifier.isEmpty else { return }

        isAddingAccount = true
        errorMessage = nil

        // Validate format based on provider
        if !validateAccountIdentifier(accountIdentifier, for: provider) {
            errorMessage = "Invalid format for \(provider.displayName)"
            isAddingAccount = false
            return
        }

        // Create linked account
        let account = LinkedPaymentAccount(
            provider: provider,
            accountIdentifier: accountIdentifier,
            displayName: accountDisplayName.isEmpty ? nil : accountDisplayName,
            isVerified: true, // In production, you'd verify this
            linkedAt: Date()
        )

        // Add to profile
        Task {
            await MainActor.run {
                if var profile = profileManager.currentProfile {
                    print("💳 [PaymentMethodsView] Adding payment account: \(provider.displayName) - \(accountIdentifier)")
                    print("💳 [PaymentMethodsView] Current linked accounts: \(profile.linkedPaymentAccounts.count)")

                    profile.linkedPaymentAccounts.append(account)

                    print("💳 [PaymentMethodsView] After adding: \(profile.linkedPaymentAccounts.count) accounts")

                    // Set as default if it's the first account
                    if profile.linkedPaymentAccounts.count == 1 {
                        print("💳 [PaymentMethodsView] Setting \(provider.displayName) as default provider")
                        profile.defaultPaymentProvider = provider
                    }

                    profileManager.updateProfile(profile)
                    print("💳 [PaymentMethodsView] Profile updated with new payment account")
                } else {
                    print("❌ [PaymentMethodsView] No current profile found!")
                }

                isAddingAccount = false
                resetAddAccountForm()
            }
        }
    }

    private func validateAccountIdentifier(_ identifier: String, for provider: PaymentProvider) -> Bool {
        switch provider {
        case .venmo, .cashApp:
            return !identifier.isEmpty
        case .paypal:
            return !identifier.isEmpty
        case .zelle:
            return identifier.contains("@") || identifier.count >= 10
        case .applePay:
            return identifier.contains("@")
        case .manual:
            return !identifier.isEmpty
        }
    }

    private func deleteAccount(at offsets: IndexSet) {
        guard var profile = profileManager.currentProfile else { return }
        profile.linkedPaymentAccounts.remove(atOffsets: offsets)

        // Clear default if it was deleted
        if let defaultProvider = profile.defaultPaymentProvider,
           !profile.linkedPaymentAccounts.contains(where: { $0.provider == defaultProvider }) {
            profile.defaultPaymentProvider = nil
        }

        profileManager.updateProfile(profile)
    }

    private func setAsDefault(_ provider: PaymentProvider) {
        guard var profile = profileManager.currentProfile else { return }
        profile.defaultPaymentProvider = provider
        profileManager.updateProfile(profile)
    }

    private func resetAddAccountForm() {
        showingAddAccount = false
        selectedProvider = nil
        accountIdentifier = ""
        accountDisplayName = ""
        errorMessage = nil
        isAddingAccount = false
    }
}

// MARK: - Info Row Component
struct InfoRow: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.body)
                .foregroundColor(.blue)
                .frame(width: 24)
            Text(text)
                .font(.subheadline)
                .foregroundColor(.primary)
        }
    }
}

// MARK: - Preview
struct PaymentMethodsView_Previews: PreviewProvider {
    static var previews: some View {
        PaymentMethodsView()
    }
}
