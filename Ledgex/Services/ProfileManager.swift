import Foundation
import SwiftUI
import Combine

// MARK: - Profile Manager
class ProfileManager: ObservableObject {
    @MainActor static let shared = ProfileManager()
    private let userDefaults = UserDefaults.standard
    private let profileKey = "UserProfile"
    
    @MainActor @Published var currentProfile: UserProfile? {
        didSet {
            saveProfile()
        }
    }
    
    init() {
        Task { @MainActor in
            loadProfile()
        }
    }
    
    @MainActor private func loadProfile() {
        if let data = userDefaults.data(forKey: profileKey),
           let profile = try? JSONDecoder().decode(UserProfile.self, from: data) {
            currentProfile = profile
        }
    }
    
    @MainActor private func saveProfile() {
        if let profile = currentProfile,
           let data = try? JSONEncoder().encode(profile) {
            userDefaults.set(data, forKey: profileKey)
        } else {
            userDefaults.removeObject(forKey: profileKey)
        }
    }
    
    @MainActor func createProfile(name: String) {
        let profile = UserProfile(name: name)
        currentProfile = profile
        Task {
            try? await FirebaseManager.shared.saveUserProfile(profile)
        }
    }

    @MainActor func setProfile(_ profile: UserProfile) {
        currentProfile = profile
    }
    
    @MainActor func updateProfile(name: String? = nil, preferredCurrency: Currency? = nil) {
        guard var profile = currentProfile else { return }

        if let name = name {
            profile.name = name
        }
        if let currency = preferredCurrency {
            profile.preferredCurrency = currency
        }

        currentProfile = profile

        // Sync to Firestore
        Task {
            try? await FirebaseManager.shared.saveUserProfile(profile)
        }
    }

    @MainActor func updateProfile(profile: UserProfile) {
        print("👤 [ProfileManager] Updating profile: \(profile.name)")
        print("👤 [ProfileManager] Trip codes: \(profile.tripCodes)")
        currentProfile = profile

        // Don't auto-sync to Firestore here - only sync explicitly when needed
        // This prevents sync loops and race conditions
    }

    @MainActor func updateProfileWithFirebaseUID(_ firebaseUID: String) {
        guard var profile = currentProfile else { return }
        profile.firebaseUID = firebaseUID
        currentProfile = profile
    }

    @MainActor func syncProfileFromFirebase() async {
        do {
            if let remoteProfile = try await FirebaseManager.shared.fetchUserProfile() {
                // Merge remote profile with local
                if let localProfile = currentProfile {
                    // If local profile was updated more recently, keep local data
                    let localLastModified = localProfile.lastSynced ?? localProfile.dateCreated
                    let remoteLastModified = remoteProfile.lastSynced ?? remoteProfile.dateCreated

                    if remoteLastModified > localLastModified {
                        print("📥 Using remote profile (newer)")
                        currentProfile = remoteProfile
                    } else {
                        print("📤 Keeping local profile (newer), syncing to Firestore")
                        try await FirebaseManager.shared.saveUserProfile(localProfile)
                    }
                } else {
                    // No local profile, use remote
                    print("📥 Using remote profile (no local profile)")
                    currentProfile = remoteProfile
                }
            } else if let localProfile = currentProfile {
                // No remote profile, sync local to Firestore
                print("📤 Syncing local profile to Firestore (no remote profile)")
                try await FirebaseManager.shared.saveUserProfile(localProfile)
            }
        } catch {
            print("❌ Failed to sync profile: \(error)")
        }
    }
    
    @MainActor func deleteProfile() {
        currentProfile = nil
    }
    
    @MainActor func createPersonFromProfile() -> Person? {
        guard let profile = currentProfile else { return nil }
        var person = Person(name: profile.name)
        person.id = profile.id
        return person
    }
    
    // New: Push notification token management
    @MainActor func updatePushToken(_ token: String) {
        guard var profile = currentProfile else { return }
        profile.pushToken = token
        currentProfile = profile
    }
    
    @MainActor func setNotificationsEnabled(_ enabled: Bool) {
        guard var profile = currentProfile else { return }
        profile.notificationsEnabled = enabled
        currentProfile = profile
    }
}
