import SwiftUI

struct SettlementsView: View {
    @ObservedObject var viewModel: ExpenseViewModel

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
                            tripName: viewModel.trip.name,
                            tripCode: viewModel.trip.code,
                            canToggleReceived: viewModel.canToggleSettlementReceived(settlement)
                        ) {
                            Task {
                                await viewModel.toggleSettlementReceived(settlement)
                            }
                        }
                    }
                } header: {
                    Text("Payments")
                } footer: {
                    Text("Tap any payment to open Venmo with pre-filled payment details. Both you and the recipient must have Venmo usernames linked.")
                }
            }
        }
        .navigationTitle("Settle Up")
    }
}

struct SettlementRow: View {
    let settlement: Settlement
    let baseCurrency: Currency
    let tripName: String
    let tripCode: String
    let canToggleReceived: Bool
    let toggleReceived: () -> Void

    @ObservedObject private var paymentService = PaymentService.shared
    @ObservedObject private var profileManager = ProfileManager.shared
    @State private var showingNoVenmoAlert = false
    @State private var isProcessingPayment = false
    @State private var paymentError: String?
    @State private var recipientVenmoUsername: String?
    @State private var isCheckingVenmo = false

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
                Task {
                    await checkVenmoAndPay()
                }
            }
        }
        .alert("Venmo Not Set Up", isPresented: $showingNoVenmoAlert) {
            Button("OK") {}
        } message: {
            if !hasVenmoUsername {
                Text("To pay via Venmo, go to your profile settings and add your Venmo username first.")
            } else {
                Text("The recipient hasn't linked their Venmo username yet. Ask them to add it in their profile settings.")
            }
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
        if isProcessingPayment || isCheckingVenmo {
            ProgressView()
        } else if !settlement.isReceived {
            if canInitiatePayment && hasVenmoUsername {
                Button {
                    Task {
                        await checkVenmoAndPay()
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.body)
                        Text("Pay via Venmo")
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

    private var hasVenmoUsername: Bool {
        return profileManager.currentProfile?.hasVenmoLinked ?? false
    }

    // MARK: - Payment Actions

    /// Check if both parties have Venmo and initiate payment
    private func checkVenmoAndPay() async {
        guard let profile = profileManager.currentProfile else { return }

        // Check if user has Venmo
        guard profile.hasVenmoLinked else {
            await MainActor.run {
                showingNoVenmoAlert = true
            }
            return
        }

        // Check if recipient has Venmo
        await MainActor.run {
            isCheckingVenmo = true
        }

        let (canPay, recipientUsername) = await paymentService.canPayViaVenmo(
            payer: profile,
            recipientFirebaseUID: settlement.to.firebaseUID
        )

        await MainActor.run {
            isCheckingVenmo = false

            if canPay, let username = recipientUsername {
                // Both have Venmo - initiate payment
                recipientVenmoUsername = username
                Task {
                    await initiateVenmoPayment(recipientUsername: username)
                }
            } else {
                // Recipient doesn't have Venmo
                showingNoVenmoAlert = true
            }
        }
    }

    /// Initiate Venmo payment with deep link
    private func initiateVenmoPayment(recipientUsername: String) async {
        isProcessingPayment = true
        paymentError = nil

        let result = await paymentService.initiateVenmoPayment(
            settlement: settlement,
            recipientVenmoUsername: recipientUsername,
            currency: baseCurrency
        )

        await MainActor.run {
            isProcessingPayment = false

            if result.success {
                // Send notification that payment was initiated
                sendPaymentInitiatedNotification()

                // Auto-mark as received after successful payment initiation
                toggleReceived()
            } else if let error = result.error {
                paymentError = error.localizedDescription
            }
        }
    }

    private func sendPaymentInitiatedNotification() {
        let amount = CurrencyAmount(amount: settlement.amount, currency: baseCurrency).formatted()
        let notification = NotificationService.NotificationType.paymentInitiated(
            tripName: tripName,
            recipientName: settlement.to.name,
            amount: amount
        )
        NotificationService.shared.sendTripNotification(notification, tripCode: tripCode)
    }
}
