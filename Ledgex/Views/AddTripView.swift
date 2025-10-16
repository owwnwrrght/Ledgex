import SwiftUI

struct AddTripView: View {
    @ObservedObject var viewModel: TripListViewModel
    @ObservedObject var profileManager = ProfileManager.shared
    @Environment(\.dismiss) var dismiss
    @State private var name = ""
    @State private var selectedCurrency: Currency = .USD
    @State private var selectedFlag: String = Trip.defaultFlag
    @State private var showingFlagPicker = false
    @State private var hasInitializedDefaults = false
    
    var body: some View {
        NavigationView {
            Form {
                Section("Group Name") {
                    TextField("Group name (e.g., Roommates)", text: $name)
                }

                Section("Defaults (optional)") {
                    HStack {
                        Text("Group icon")
                        Spacer()
                        Button {
                            showingFlagPicker = true
                        } label: {
                            HStack(spacing: 6) {
                                Text(selectedFlag)
                                    .font(.title2)
                                Text("Change")
                                    .font(.caption)
                                    .foregroundColor(.blue)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color.blue.opacity(0.1))
                            .cornerRadius(10)
                        }
                        .buttonStyle(.plain)
                    }

                    Picker("Base currency", selection: $selectedCurrency) {
                        ForEach(Currency.allCases, id: \.self) { currency in
                            Text(currency.displayName).tag(currency)
                        }
                    }

                    Text("You can adjust these settings any time from Group Settings.")
                        .font(.footnote)
                        .foregroundColor(.secondary)
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
                    Button {
                        if !name.isEmpty {
                            Task {
                                await viewModel.createTrip(name: name, currency: selectedCurrency, flagEmoji: selectedFlag)
                                dismiss()
                            }
                        }
                    } label: {
                        if viewModel.isLoading {
                            ProgressView()
                                .progressViewStyle(.circular)
                        } else {
                            Text("Create")
                                .fontWeight(.semibold)
                        }
                    }
                    .disabled(name.isEmpty || viewModel.isLoading)
                    .accessibilityLabel("Create Group")
                }
            }
        }
        .onAppear {
            if !hasInitializedDefaults {
                selectedCurrency = defaultCurrency
                selectedFlag = Trip.defaultFlag
                hasInitializedDefaults = true
            }
        }
        .sheet(isPresented: $showingFlagPicker) {
            FlagPickerView(currentSelection: selectedFlag) { newFlag in
                selectedFlag = newFlag
            }
        }
    }

    private var defaultCurrency: Currency {
        profileManager.currentProfile?.preferredCurrency ?? .USD
    }
}
