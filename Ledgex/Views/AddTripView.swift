import SwiftUI

struct AddTripView: View {
    @ObservedObject var viewModel: TripListViewModel
    @ObservedObject var profileManager = ProfileManager.shared
    @Environment(\.dismiss) var dismiss
    @State private var name = ""
    
    var body: some View {
        NavigationView {
            Form {
                Section("Group Name") {
                    TextField("Group name (e.g., Roommates)", text: $name)
                }

                Section {
                    Text("We'll start your group with default icon \(Trip.defaultFlag), base currency \(defaultCurrency.displayName), and other sensible defaults. You can customize everything later in Group Settings.")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.leading)
                        .padding(.vertical, 4)
                }
            }
            .navigationTitle("New Group")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Create") {
                        if !name.isEmpty {
                            Task {
                                await viewModel.createTrip(name: name, currency: defaultCurrency, flagEmoji: Trip.defaultFlag)
                                dismiss()
                            }
                        }
                    }
                    .disabled(name.isEmpty || viewModel.isLoading)
                }
            }
        }
        .onAppear {
            name = ""
        }
    }

    private var defaultCurrency: Currency {
        profileManager.currentProfile?.preferredCurrency ?? .USD
    }
}
