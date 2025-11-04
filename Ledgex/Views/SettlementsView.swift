import SwiftUI

struct SettlementsView: View {
    @ObservedObject var viewModel: ExpenseViewModel
    @State private var showingPaymentMethods = false

    var body: some View {
        List {
            if !viewModel.allParticipantsConfirmed {
                Section {
                    VStack(alignment: .center, spacing: 16) {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: 50))
                            .foregroundColor(.orange)
                        Text("Waiting on everyone")
                            .font(.title3)
                            .fontWeight(.semibold)
                        if !viewModel.pendingConfirmations.isEmpty {
                            Text(viewModel.pendingConfirmations.map(\.name).joined(separator: ", "))
                                .font(.subheadline)
                                .foregroundColor(.primary)
                                .multilineTextAlignment(.center)
                        }
                        Text("Once everyone has finished adding expenses, settlements will appear here.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 32)
                }
            } else if viewModel.settlements.isEmpty {
                Section {
                    VStack(alignment: .center, spacing: 20) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 50))
                            .foregroundColor(.green)
                        Text("All settled up!")
                            .font(.title2)
                            .fontWeight(.semibold)
                        Text("No payments needed")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 32)
                }
            } else {
                Section {
                    ForEach(viewModel.settlements) { settlement in
                        SettlementRow(
                            settlement: settlement,
                            baseCurrency: viewModel.trip.baseCurrency,
                            canToggleReceived: viewModel.canToggleSettlementReceived(settlement),
                            showingPaymentMethods: $showingPaymentMethods
                        ) {
                            Task {
                                await viewModel.toggleSettlementReceived(settlement)
                            }
                        }
                    }
                } header: {
                    Text("Payments")
                } footer: {
                    if ProfileManager.shared.currentProfile?.hasLinkedPaymentAccounts == true {
                        Text("Tap any payment to initiate instant transfer via your linked payment apps")
                    } else {
                        Text("Tap the credit card icon above to link Venmo, Zelle, Cash App, or PayPal for instant payments")
                    }
                }
            }
        }
        .navigationTitle("Settle Up")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showingPaymentMethods = true
                } label: {
                    Image(systemName: "creditcard.and.123")
                }
            }
        }
        .sheet(isPresented: $showingPaymentMethods) {
            PaymentMethodsView()
        }
    }
}

struct SettlementRow: View {
    let settlement: Settlement
    let baseCurrency: Currency
    let canToggleReceived: Bool
    @Binding var showingPaymentMethods: Bool
    let toggleReceived: () -> Void

    @ObservedObject private var paymentService = PaymentService.shared
    @ObservedObject private var profileManager = ProfileManager.shared
    @State private var showingPaymentOptions = false
    @State private var selectedProvider: PaymentProvider?
    @State private var isProcessingPayment = false
    @State private var paymentError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Text(settlement.from.name)
                            .font(.body)
                            .fontWeight(.semibold)
                        Image(systemName: "arrow.right")
                            .font(.caption)
                            .foregroundColor(.blue)
                        Text(settlement.to.name)
                            .font(.body)
                            .fontWeight(.semibold)
                    }

                    HStack(spacing: 8) {
                        Text(CurrencyAmount(amount: settlement.amount, currency: baseCurrency).formatted())
                            .font(.title3)
                            .fontWeight(.bold)
                            .foregroundColor(.blue)

                        if settlement.isReceived {
                            paymentStatusBadge
                        } else if let paymentText = settlement.paymentDisplayText {
                            Text(paymentText)
                                .font(.caption)
                                .foregroundColor(.orange)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.orange.opacity(0.15))
                                .cornerRadius(8)
                        }
                    }
                }

                Spacer()

                actionButtons
            }

            if let error = paymentError {
                errorBanner(error)
            }
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .onTapGesture {
            if !settlement.isReceived && canInitiatePayment {
                showingPaymentOptions = true
            }
        }
        .confirmationDialog("Choose Payment Method", isPresented: $showingPaymentOptions, titleVisibility: .visible) {
            paymentOptionsDialog
        }
    }

    @ViewBuilder
    private var paymentStatusBadge: some View {
        HStack(spacing: 3) {
            Image(systemName: settlement.isPaidViaApp ? "checkmark.circle.fill" : "checkmark.circle.fill")
                .font(.caption)
            Text(settlement.isPaidViaApp ? "Paid" : "Received")
                .font(.caption)
        }
        .foregroundColor(.green)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.green.opacity(0.15))
        .cornerRadius(8)
    }

    @ViewBuilder
    private var actionButtons: some View {
        if isProcessingPayment {
            ProgressView()
        } else if !settlement.isReceived {
            if canInitiatePayment {
                if hasLinkedAccounts {
                    Button {
                        showingPaymentOptions = true
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.up.circle.fill")
                                .font(.body)
                            Text("Pay Now")
                                .font(.subheadline)
                                .fontWeight(.medium)
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.green)
                        .cornerRadius(10)
                    }
                    .buttonStyle(.plain)
                } else {
                    Button {
                        showingPaymentMethods = true
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "creditcard.and.123")
                                .font(.body)
                            Text("Set Up")
                                .font(.subheadline)
                                .fontWeight(.medium)
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.orange)
                        .cornerRadius(10)
                    }
                    .buttonStyle(.plain)
                }
            } else if canToggleReceived {
                Button(action: toggleReceived) {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle")
                            .font(.body)
                        Text("Mark Received")
                            .font(.subheadline)
                            .fontWeight(.medium)
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.blue)
                    .cornerRadius(10)
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private var paymentOptionsDialog: some View {
        // Show setup button if no accounts linked
        if !hasLinkedAccounts {
            Button {
                showingPaymentMethods = true
                showingPaymentOptions = false
            } label: {
                Label("Set Up Payment Methods", systemImage: "creditcard.and.123")
            }
        } else {
            // Quick pay with default provider
            if let defaultProvider = profileManager.currentProfile?.defaultPaymentProvider,
               paymentService.isProviderAvailable(defaultProvider),
               let account = profileManager.currentProfile?.paymentAccount(for: defaultProvider) {
                Button {
                    initiatePayment(with: defaultProvider, account: account)
                } label: {
                    Label("Pay with \(defaultProvider.displayName)", systemImage: "bolt.fill")
                }
            }

            // Other available providers
            ForEach(availablePaymentProviders, id: \.self) { provider in
                if let account = profileManager.currentProfile?.paymentAccount(for: provider) {
                    Button {
                        initiatePayment(with: provider, account: account)
                    } label: {
                        Text("Pay with \(provider.displayName)")
                    }
                }
            }
        }

        Button("Mark as Paid Manually", role: .none) {
            toggleReceived()
        }

        Button("Cancel", role: .cancel) {}
    }

    @ViewBuilder
    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.red)
            Text(message)
                .font(.caption)
                .foregroundColor(.red)
        }
        .padding(8)
        .background(Color.red.opacity(0.1))
        .cornerRadius(8)
    }

    // MARK: - Helper Properties

    private var canInitiatePayment: Bool {
        guard let profile = profileManager.currentProfile else { return false }
        // User can initiate payment if they are the "from" person
        return settlement.from.id == profile.id
    }

    private var hasLinkedAccounts: Bool {
        return profileManager.currentProfile?.hasLinkedPaymentAccounts ?? false
    }

    private var availablePaymentProviders: [PaymentProvider] {
        guard let accounts = profileManager.currentProfile?.linkedPaymentAccounts else {
            return []
        }
        return accounts
            .filter { $0.isVerified && paymentService.isProviderAvailable($0.provider) }
            .map { $0.provider }
    }

    // MARK: - Payment Action

    private func initiatePayment(with provider: PaymentProvider, account: LinkedPaymentAccount) {
        isProcessingPayment = true
        paymentError = nil

        Task {
            let result = await paymentService.initiatePayment(
                settlement: settlement,
                provider: provider,
                recipientAccount: account
            )

            await MainActor.run {
                isProcessingPayment = false

                if result.success {
                    // Auto-mark as received after successful payment initiation
                    toggleReceived()
                } else if let error = result.error {
                    paymentError = error.localizedDescription
                }
            }
        }
    }
}
