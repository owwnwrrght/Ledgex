import Foundation
import SwiftUI
import OSLog
import Combine

// MARK: - View Models
@MainActor
class TripListViewModel: ObservableObject {
    @Published var trips: [Trip] = [] {
        didSet {
            DataManager.shared.saveTrips(trips)
        }
    }
    @Published var showingJoinTrip = false
    @Published var showingAddTrip = false
    @Published var selectedTrip: Trip?
    @Published var isLoading = false
    @Published var lastError: AppError?

    let dataStore: TripDataStore
    let profileManager = ProfileManager.shared
    private var notificationObservers: [NSObjectProtocol] = []
    private let logger = Logger(subsystem: "com.OwenWright.Ledgex-ios", category: "TripListViewModel")

    init(dataStore: TripDataStore? = nil) {
        self.dataStore = dataStore ?? FirebaseManager.shared
        self.trips = DataManager.shared.loadTrips()

        let signInObserver = NotificationCenter.default.addObserver(forName: .ledgexUserDidSignIn, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                print("🔔 [TripListViewModel] Received sign-in notification, syncing trips...")
                await self?.syncTripsFromFirebase()
            }
        }
        let signOutObserver = NotificationCenter.default.addObserver(forName: .ledgexUserDidSignOut, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handleSignedOut()
            }
        }
        let deleteObserver = NotificationCenter.default.addObserver(forName: .ledgexUserDidDeleteAccount, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handleSignedOut()
            }
        }
        notificationObservers.append(contentsOf: [signInObserver, signOutObserver, deleteObserver])

        // Sync trips from Firestore when initialized
        Task { [weak self] in
            await self?.syncTripsFromFirebase()
        }
    }

    func syncTripsFromFirebase() async {
        guard let firebase = dataStore as? FirebaseManager else {
            print("⚠️ [TripSync] dataStore is not FirebaseManager, skipping sync")
            return
        }

        print("🔄 [TripSync] Starting trip sync from Firestore...")
        print("🔄 [TripSync] Current local trips count: \(trips.count)")

        do {
            let remoteTrips = try await firebase.fetchUserTrips()
            print("🔄 [TripSync] Fetched \(remoteTrips.count) remote trips from Firestore")

            if !remoteTrips.isEmpty {
                print("📥 [TripSync] Syncing \(remoteTrips.count) trips from Firestore")
                print("📥 [TripSync] Remote trip codes: \(remoteTrips.map { $0.code })")

                // Merge with local trips and migrate old data
                var mergedTrips = trips
                for var remoteTrip in remoteTrips {
                    // Migration: Update people with Firebase UIDs if they match current user
                    var needsMigration = false
                    if let currentProfile = profileManager.currentProfile {
                        for (index, person) in remoteTrip.people.enumerated() {
                            // If this person matches the current user's profile but doesn't have a firebaseUID
                            if person.id == currentProfile.id && person.firebaseUID == nil {
                                print("🔄 [Migration] Adding Firebase UID to person \(person.name) in trip \(remoteTrip.code)")
                                remoteTrip.people[index].firebaseUID = currentProfile.firebaseUID
                                needsMigration = true
                            }
                        }
                    }

                    // If we updated any people, save the trip back to Firestore
                    if needsMigration {
                        print("💾 [Migration] Saving migrated trip \(remoteTrip.code) to Firestore...")
                        do {
                            let updatedTrip = try await firebase.saveTrip(remoteTrip)
                            remoteTrip = updatedTrip
                            print("✅ [Migration] Successfully migrated trip \(remoteTrip.code)")
                        } catch {
                            print("⚠️ [Migration] Failed to save migrated trip: \(error)")
                            // Continue with the un-migrated trip
                        }
                    }

                    if let localIndex = mergedTrips.firstIndex(where: { $0.id == remoteTrip.id }) {
                        // Compare modification dates and keep the newer one
                        if remoteTrip.lastModified > mergedTrips[localIndex].lastModified {
                            print("📥 [TripSync] Updating local trip \(remoteTrip.code) with remote version")
                            mergedTrips[localIndex] = remoteTrip
                        } else {
                            print("📥 [TripSync] Keeping local trip \(remoteTrip.code) (newer)")
                        }
                    } else {
                        // Trip doesn't exist locally, add it
                        print("📥 [TripSync] Adding new trip from remote: \(remoteTrip.code)")
                        mergedTrips.append(remoteTrip)
                    }
                }

                trips = mergedTrips
                print("✅ [TripSync] Trip sync complete. Total trips: \(trips.count)")
            } else {
                print("ℹ️ [TripSync] No remote trips found")
            }
        } catch {
            print("❌ [TripSync] Failed to sync trips: \(error)")
        }
    }
    
    deinit {
        notificationObservers.forEach { NotificationCenter.default.removeObserver($0) }
    }
    
    func createTrip(name: String, currency: Currency, flagEmoji: String? = nil) async {
        print("🆕 [CreateTrip] Starting trip creation: \(name)")
        let code = await dataStore.generateUniqueTripCode()
        print("🆕 [CreateTrip] Generated trip code: \(code)")

        var trip = Trip(name: name, code: code, baseCurrency: currency)
        trip.flagEmoji = flagEmoji ?? Trip.defaultFlag

        // Auto-add current user to the group if they have a profile
        if let currentUser = profileManager.createPersonFromProfile() {
            print("🆕 [CreateTrip] Adding current user to trip: \(currentUser.name) (ID: \(currentUser.id))")
            trip.people.append(currentUser)
        } else {
            print("⚠️ [CreateTrip] No current profile found to add to trip")
        }

        // Save to Firebase first
        do {
            print("🆕 [CreateTrip] Saving trip to Firebase...")
            let savedTrip = try await dataStore.saveTrip(trip)
            print("✅ [CreateTrip] Trip saved to Firebase")
            self.trips.append(savedTrip)

            // Link trip to user profile in Firestore
            if let firebase = dataStore as? FirebaseManager {
                print("🆕 [CreateTrip] Linking trip \(savedTrip.code) to user profile...")
                do {
                    try await firebase.addTripToUserProfile(tripCode: savedTrip.code)
                    print("✅ [CreateTrip] Trip linked to user profile successfully")
                } catch {
                    print("❌ [CreateTrip] Failed to link trip to user profile: \(error)")
                }
            }
        } catch {
            print("❌ [CreateTrip] Failed to save trip to Firebase: \(error)")
            self.trips.append(trip)
            await handleError(error, fallback: "We saved your group locally, but syncing to the cloud failed. We'll retry automatically when you're back online.")

            // Try to link trip to profile even if save failed
            if let firebase = dataStore as? FirebaseManager {
                print("🆕 [CreateTrip] Attempting to link trip to profile despite save failure...")
                try? await firebase.addTripToUserProfile(tripCode: trip.code)
            }
        }
    }
    
    func joinTrip(with code: String) async -> (Bool, String?) {
        let sanitizedCode = sanitize(code: code)

        guard sanitizedCode.count == Trip.codeLength else {
            return (false, "Group codes are \(Trip.codeLength) characters. Double-check the code and try again.")
        }

        isLoading = true
        defer { isLoading = false }
        
        do {
            var trip = try await dataStore.fetchTrip(by: sanitizedCode)
            
            if var foundTrip = trip {
                // Auto-add current user to the group if they have a profile and aren't already in it
                if let currentUser = profileManager.createPersonFromProfile() {
                    let userAlreadyExists = foundTrip.people.contains { $0.name.lowercased() == currentUser.name.lowercased() }
                    
                    if !userAlreadyExists {
                        foundTrip.people.append(currentUser)
                        
                        // Save the complete trip with new user to Firebase
                        do {
                            let savedTrip = try await dataStore.saveTrip(foundTrip)
                            foundTrip = savedTrip  // Use the authoritative copy
                        } catch {
                            await handleError(error, fallback: "We couldn't sync the new member yet. We'll keep trying in the background.")
                        }
                        
                        trip = foundTrip
                    }
                }
                
                let tripToAdd = foundTrip
                // Check if already joined
                if !self.trips.contains(where: { $0.id == tripToAdd.id }) {
                    self.trips.append(tripToAdd)
                }
                JoinCodeHistory.shared.add(code: tripToAdd.code)

                // Link trip to user profile in Firestore
                if let firebase = dataStore as? FirebaseManager {
                    try? await firebase.addTripToUserProfile(tripCode: tripToAdd.code)
                }

                return (true, nil)
            }
            
            return (false, "Group not found. Please check the code.")
        } catch {
            let message = FirebaseManager.userFriendlyError(error)
            await handleError(error, fallback: message)
            return (false, message)
        }
    }
    
    func removeTrip(at offsets: IndexSet) {
        let removedTrips = offsets.map { trips[$0] }
        trips.remove(atOffsets: offsets)

        // Remove from user profile in Firestore
        Task {
            if let firebase = dataStore as? FirebaseManager {
                for trip in removedTrips {
                    try? await firebase.removeTripFromUserProfile(tripCode: trip.code)
                }
            }
        }
    }

    func removeTrip(_ trip: Trip) {
        if let index = trips.firstIndex(where: { $0.id == trip.id }) {
            trips.remove(at: index)
        } else {
            trips.removeAll { $0.code == trip.code }
        }

        if let selected = selectedTrip, selected.id == trip.id {
            selectedTrip = nil
        }
    }
    
    func updateTrip(_ trip: Trip) {
        if let index = trips.firstIndex(where: { $0.id == trip.id }) {
            trips[index] = trip
        }
    }

    func syncTrip(_ trip: Trip) async {
        do {
            let updatedTrip = try await dataStore.syncTrip(trip)
            if let index = trips.firstIndex(where: { $0.id == trip.id }) {
                trips[index] = updatedTrip
            }
        } catch {
            print("Failed to sync trip: \(error)")
        }
    }

    private func sanitize(code: String) -> String {
        let allowedCharacters = CharacterSet.alphanumerics
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
        let filtered = trimmed.unicodeScalars.filter { allowedCharacters.contains($0) }
        let normalized = String(String.UnicodeScalarView(filtered)).uppercased()
        if normalized.count > Trip.codeLength {
            return String(normalized.prefix(Trip.codeLength))
        }
        return normalized
    }

    private func handleSignedOut() {
        print("🧹 [TripListViewModel] Cleaning up state after sign out...")

        // Clear all trips
        trips.removeAll()
        print("  ✓ Cleared trips array")

        // Clear persistent storage
        DataManager.shared.clearAllData()
        print("  ✓ Cleared DataManager storage")

        // Reset UI state
        showingAddTrip = false
        showingJoinTrip = false
        selectedTrip = nil
        isLoading = false
        lastError = nil
        print("  ✓ Reset UI state")

        print("✅ [TripListViewModel] Cleanup complete")
    }
}

private extension TripListViewModel {
    func handleError(_ error: Error, fallback: String) async {
        logger.error("\(error.localizedDescription, privacy: .public)")
        await MainActor.run {
            lastError = AppError.make(from: error, fallbackMessage: fallback)
        }
    }
}
