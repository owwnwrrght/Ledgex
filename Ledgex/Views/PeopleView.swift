import SwiftUI

struct PeopleView: View {
    @ObservedObject var viewModel: ExpenseViewModel
    @State private var showingAddPerson = false
    @State private var showingActionSheet = false
    @State private var processingPeople: Set<UUID> = []
    @State private var isStartingGroup = false
    
    var body: some View {
        List {
            if !viewModel.people.isEmpty {
                if viewModel.isInSetupPhase {
                    Section {
                        VStack(spacing: 16) {
                            HStack {
                                Image(systemName: "person.3.fill")
                                    .font(.title2)
                                    .foregroundColor(.blue)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Setting up group")
                                        .font(.headline)
                                    Text("\(viewModel.people.count) participant\(viewModel.people.count == 1 ? "" : "s") added")
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                            }

                            VStack(alignment: .leading, spacing: 8) {
                                Text("Once everyone has joined, start the group to begin adding expenses.")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                    .multilineTextAlignment(.leading)

                                Button(action: {
                                    isStartingGroup = true
                                    Task {
                                        await viewModel.startTrip()
                                        await MainActor.run {
                                            isStartingGroup = false
                                        }
                                    }
                                }) {
                                    HStack(spacing: 8) {
                                        if isStartingGroup {
                                            ProgressView()
                                                .tint(.white)
                                        } else {
                                            Image(systemName: "play.circle.fill")
                                                .font(.title3)
                                        }
                                        Text("Start Group")
                                            .font(.headline)
                                    }
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .background(Color.blue)
                                    .cornerRadius(12)
                                }
                                .disabled(isStartingGroup || viewModel.people.isEmpty)
                            }
                        }
                        .padding(.vertical, 8)
                    }
                } else {
                    Section {
                        VStack(spacing: 12) {
                            HStack {
                                Image(systemName: viewModel.allParticipantsConfirmed ? "checkmark.circle.fill" : "clock.fill")
                                    .font(.title2)
                                    .foregroundColor(viewModel.allParticipantsConfirmed ? .green : .orange)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(viewModel.allParticipantsConfirmed ? "Ready to settle up" : "Adding expenses")
                                        .font(.headline)
                                    Text("\(viewModel.people.count - viewModel.pendingConfirmations.count) of \(viewModel.people.count) confirmed")
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                            }

                            ProgressView(value: viewModel.confirmationProgress, total: 1.0)
                                .tint(viewModel.allParticipantsConfirmed ? .green : .blue)
                        }
                        .padding(.vertical, 8)
                    }
                }
            }

            Section {
                ForEach(viewModel.people) { person in
                    PersonRow(
                        person: person,
                        baseCurrency: viewModel.trip.baseCurrency,
                        canToggle: viewModel.canToggleCompletion(for: person),
                        isCurrentUser: viewModel.isCurrentUser(person: person),
                        isProcessing: processingPeople.contains(person.id)
                    ) {
                        processingPeople.insert(person.id)
                        Task {
                            await viewModel.toggleCompletion(for: person)
                            _ = await MainActor.run {
                                processingPeople.remove(person.id)
                            }
                        }
                    }
                }
                .onDelete(perform: viewModel.removePerson)
            } header: {
                Text("Participants")
            }
        }
        .navigationTitle("People")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(action: {
                    showingActionSheet = true
                }) {
                    Image(systemName: "plus")
                }
            }
        }
        .actionSheet(isPresented: $showingActionSheet) {
            ActionSheet(
                title: Text("Add Person"),
                message: Text("How would you like to add someone to the group?"),
                buttons: [
                    .default(Text("Add Someone Without App")) {
                        showingAddPerson = true
                    },
                    .default(Text("Share invite link")) {
                        if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                           let viewController = scene.windows.first?.rootViewController {
                            let link = TripLinkService.fallbackLink(for: viewModel.trip)
                            let message = "Join my group '\(viewModel.trip.name)' on Ledgex: \(link.absoluteString)"
                            let activityVC = UIActivityViewController(activityItems: [message, link], applicationActivities: nil)
                            viewController.present(activityVC, animated: true)
                        }
                    },
                    .cancel()
                ]
            )
        }
        .sheet(isPresented: $showingAddPerson) {
            AddPersonView(viewModel: viewModel)
        }
        .overlay {
            if viewModel.people.isEmpty {
                VStack(spacing: 20) {
                    Image(systemName: "person.3")
                        .font(.system(size: 60))
                        .foregroundColor(.gray)
                    Text("No people yet")
                        .font(.title2)
                        .foregroundColor(.secondary)
                    Text("Add group participants")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("You can add people even if they don't have the app")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .italic()
                }
            }
        }
    }
}

struct PersonRow: View {
    let person: Person
    let baseCurrency: Currency
    let canToggle: Bool
    let isCurrentUser: Bool
    let isProcessing: Bool
    let onToggle: () -> Void

    private var balance: Decimal {
        person.totalPaid - person.totalOwed
    }

    private var balanceColor: Color {
        if balance > 0.01 {
            return .green
        } else if balance < -0.01 {
            return .red
        } else {
            return .green
        }
    }

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text(person.name)
                        .font(.body)
                        .fontWeight(.semibold)

                    if person.isManuallyAdded {
                        Text("No app")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.secondary.opacity(0.15))
                            .cornerRadius(6)
                    }

                    confirmationBadge
                }

                balanceView
            }

            Spacer()
        }
        .padding(.vertical, 6)
    }
    
    private var confirmationBadge: some View {
        Group {
            if person.hasCompletedExpenses {
                HStack(spacing: 3) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption2)
                    Text("Done")
                        .font(.caption2)
                }
                .foregroundColor(.green)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.green.opacity(0.15))
                .cornerRadius(6)
            }
        }
    }

    private var balanceView: some View {
        HStack(spacing: 6) {
            if abs(balance) > 0.01 {
                Text(balance > 0 ? "Gets back" : "Owes")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Text(CurrencyAmount(amount: abs(balance), currency: baseCurrency).formatted())
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(balanceColor)
            } else {
                HStack(spacing: 3) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption)
                    Text("All settled")
                        .font(.subheadline)
                }
                .foregroundColor(.green)
            }
        }
    }
}

struct AddPersonView: View {
    @ObservedObject var viewModel: ExpenseViewModel
    @Environment(\.dismiss) var dismiss
    @State private var name = ""
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Person Details")) {
                    TextField("Name", text: $name)
                        .textInputAutocapitalization(.words)
                }
                
                Section(footer: Text("This person will be added to the group without needing the app. You can add expenses for them and they'll be included in all calculations.")) {
                    EmptyView()
                }
            }
            .navigationTitle("Add Person Without App")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Add") {
                        if !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            viewModel.addManualPerson(name: name.trimmingCharacters(in: .whitespacesAndNewlines))
                            dismiss()
                        }
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}
