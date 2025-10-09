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
                            canToggleReceived: viewModel.canToggleSettlementReceived(settlement)
                        ) {
                            Task {
                                await viewModel.toggleSettlementReceived(settlement)
                            }
                        }
                    }
                } header: {
                    Text("Payments")
                }
            }
        }
        .navigationTitle("Settle Up")
    }
}

struct SettlementRow: View {
    let settlement: Settlement
    let baseCurrency: Currency
    let canToggleReceived: Bool
    let toggleReceived: () -> Void

    var body: some View {
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
                        HStack(spacing: 3) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.caption)
                            Text("Received")
                                .font(.caption)
                        }
                        .foregroundColor(.green)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.green.opacity(0.15))
                        .cornerRadius(8)
                    }
                }
            }

            Spacer()

            if canToggleReceived && !settlement.isReceived {
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
        .padding(.vertical, 8)
    }
}
