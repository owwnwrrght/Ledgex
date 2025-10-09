import SwiftUI

struct TripListView: View {
    @ObservedObject var viewModel: TripListViewModel
    @ObservedObject private var firebaseManager = FirebaseManager.shared
    @ObservedObject private var profileManager = ProfileManager.shared
    @State private var showingAddTrip = false
    @State private var showingProfile = false
    @State private var joinTripCode = ""
    @State private var showingJoinError = false
    
    @ViewBuilder
    private var bottomBar: some View {
        if !firebaseManager.isFirebaseAvailable {
            HStack(spacing: 8) {
                Image(systemName: "wifi.slash")
                    .font(.caption)
                    .foregroundColor(.orange)
                
                Text("Offline mode - groups won't sync")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Button("Retry") {
                    Task {
                        await firebaseManager.checkFirebaseStatus()
                    }
                }
                .font(.caption2)
                .foregroundColor(.orange)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color.orange.opacity(0.05))
        }
    }
    
    var body: some View {
        List {
            ForEach(viewModel.trips) { trip in
                NavigationLink(destination: TripDetailView(trip: trip, tripListViewModel: viewModel)) {
                    TripRowView(trip: trip, syncStatus: firebaseManager.syncStatus, isFirebaseAvailable: firebaseManager.isFirebaseAvailable)
                }
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
            }
            .onDelete(perform: viewModel.removeTrip)
        }
        .listStyle(.plain)
        .navigationTitle("Groups")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button(action: { showingAddTrip = true }) {
                        Label("Create Group", systemImage: "plus.circle")
                    }
                    
                    Button(action: { viewModel.showingJoinTrip = true }) {
                        Label("Join Group", systemImage: "person.2")
                    }
                    .disabled(!firebaseManager.isFirebaseAvailable)
                } label: {
                    Image(systemName: "plus")
                        .font(.title3)
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            bottomBar
        }
        .sheet(isPresented: $showingAddTrip) {
            AddTripView(viewModel: viewModel)
        }
        .sheet(isPresented: $viewModel.showingJoinTrip) {
            JoinTripView(viewModel: viewModel)
        }
        .overlay {
            if viewModel.trips.isEmpty {
                VStack(spacing: 24) {
                    VStack(spacing: 16) {
                        Image(systemName: "person.3.sequence")
                            .font(.system(size: 72, weight: .ultraLight))
                            .foregroundColor(.blue.opacity(0.6))
                        
                        VStack(spacing: 8) {
                            Text("Ready to simplify shared expenses?")
                                .font(.title2)
                                .fontWeight(.medium)
                                .foregroundColor(.primary)
                            
                            Text("Create a group to track day-to-day costs with roommates, friends, or family")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 32)

                            Text("We'll start you with sensible defaults—you can customize the name, icon, and currency later in Group Settings.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 40)
                        }
                    }
                    
                    VStack(spacing: 12) {
                        Button(action: { showingAddTrip = true }) {
                            HStack {
                                Image(systemName: "plus.circle.fill")
                                Text("Create Your First Group")
                            }
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(Color.blue)
                            .cornerRadius(12)
                        }
                        .padding(.horizontal, 32)
                        
                        if firebaseManager.isFirebaseAvailable {
                            Button(action: { viewModel.showingJoinTrip = true }) {
                                HStack {
                                    Image(systemName: "person.2")
                                    Text("Join Existing Group")
                                }
                                .font(.subheadline)
                                .foregroundColor(.blue)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(Color.blue.opacity(0.1))
                                .cornerRadius(8)
                            }
                            .padding(.horizontal, 32)
                        }
                    }
                }
                .padding(.vertical, 40)
            }
        }
    }
    
    @ViewBuilder
    private func syncStatusIndicator(for status: FirebaseManager.SyncStatus) -> some View {
        switch status {
        case .idle:
            Image(systemName: "icloud")
                .foregroundColor(.gray)
        case .syncing:
            ProgressView()
                .scaleEffect(0.7)
        case .success:
            Image(systemName: "icloud.fill")
                .foregroundColor(.green)
        case .error(_):
            Image(systemName: "exclamationmark.icloud")
                .foregroundColor(.red)
        }
    }
}

struct TripRowView: View {
    let trip: Trip
    let syncStatus: FirebaseManager.SyncStatus
    let isFirebaseAvailable: Bool
    
    private var totalAmount: Decimal {
        trip.expenses.reduce(Decimal.zero) { $0 + $1.amount }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                // Trip icon
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.blue.opacity(0.08))
                    Text(trip.flagEmoji)
                        .font(.system(size: 28))
                }
                .frame(width: 48, height: 48)
                
                // Trip info
                VStack(alignment: .leading, spacing: 6) {
                    Text(trip.name)
                        .font(.headline)
                        .foregroundColor(.primary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    
                    // Stats row
                    HStack(spacing: 16) {
                        HStack(spacing: 4) {
                            Image(systemName: "person.2")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text("\(trip.people.count)")
                                .font(.subheadline)
                                .fontWeight(.medium)
                        }
                        
                        HStack(spacing: 4) {
                            Image(systemName: "dollarsign.circle")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text("\(trip.expenses.count)")
                                .font(.subheadline)
                                .fontWeight(.medium)
                        }
                        
                        if totalAmount > 0 {
                            HStack(spacing: 4) {
                                Image(systemName: "chart.line.uptrend.xyaxis")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text(CurrencyAmount(amount: totalAmount, currency: trip.baseCurrency).formatted())
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                            }
                        }
                        
                        Spacer()
                        
                        if isFirebaseAvailable {
                            syncStatusIndicator(for: syncStatus)
                        }
                    }
                    .foregroundColor(.secondary)
                    
                    confirmationSummary
                }
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 16)
            .background(Color(.systemBackground))
            .cornerRadius(12)
            .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
        }
    }
    
    @ViewBuilder
    private func syncStatusIndicator(for status: FirebaseManager.SyncStatus) -> some View {
        switch status {
        case .idle:
            Image(systemName: "icloud")
                .font(.caption)
                .foregroundColor(.gray)
        case .syncing:
            ProgressView()
                .scaleEffect(0.6)
        case .success:
            Image(systemName: "checkmark.icloud")
                .font(.caption)
                .foregroundColor(.green)
        case .error(_):
            Image(systemName: "exclamationmark.triangle")
                .font(.caption)
                .foregroundColor(.orange)
        }
    }

    @ViewBuilder
    private var confirmationSummary: some View {
        let total = trip.people.count
        if total > 0 {
            let confirmed = trip.people.filter { $0.hasCompletedExpenses }.count
            if confirmed == total {
                Label("Everyone ready to settle", systemImage: "checkmark.seal.fill")
                    .font(.caption)
                    .foregroundColor(.green)
            } else {
                Label("\(confirmed)/\(total) marked done", systemImage: "clock")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        } else {
            EmptyView()
        }
    }
}
