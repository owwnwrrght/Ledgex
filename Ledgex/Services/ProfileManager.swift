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
            print("👤 [ProfileManager] Loaded profile from UserDefaults: \(profile.name)")
            print("👤 [ProfileManager] Profile ID: \(profile.id)")
            print("👤 [ProfileManager] Firebase UID: \(profile.firebaseUID ?? "nil")")
            print("👤 [ProfileManager] Trip codes: \(profile.tripCodes)")
            currentProfile = profile
        } else {
            print("👤 [ProfileManager] No profile found in UserDefaults")
        }
    }

    @MainActor private func saveProfile() {
        if let profile = currentProfile,
           let data = try? JSONEncoder().encode(profile) {
            userDefaults.set(data, forKey: profileKey)
            print("💾 [ProfileManager] Saved profile to UserDefaults: \(profile.name)")
        } else {
            userDefaults.removeObject(forKey: profileKey)
            print("💾 [ProfileManager] Removed profile from UserDefaults")
        }
    }
    
    @MainActor func createProfile(name: String) {
        print("👤 [ProfileManager] Creating new profile: \(name)")
        let profile = UserProfile(name: name)
        currentProfile = profile
        Task {
            do {
                try await FirebaseManager.shared.saveUserProfile(profile)
                print("✅ [ProfileManager] Profile saved to Firestore")
            } catch {
                print("❌ [ProfileManager] Failed to save profile to Firestore: \(error)")
            }
        }
    }

    @MainActor func setProfile(_ profile: UserProfile) {
        print("👤 [ProfileManager] Setting profile: \(profile.name)")
        print("👤 [ProfileManager] Profile ID: \(profile.id)")
        print("👤 [ProfileManager] Firebase UID: \(profile.firebaseUID ?? "nil")")
        print("👤 [ProfileManager] Trip codes: \(profile.tripCodes)")
        currentProfile = profile

        // Immediately sync to Firestore to ensure persistence
        Task {
            do {
                try await FirebaseManager.shared.saveUserProfile(profile)
                print("✅ [ProfileManager] Profile synced to Firestore after setProfile")
            } catch {
                print("❌ [ProfileManager] Failed to sync profile to Firestore after setProfile: \(error)")
            }
        }
    }
    
    @MainActor func updateProfile(name: String? = nil, preferredCurrency: Currency? = nil) {
        guard var profile = currentProfile else {
            print("⚠️ [ProfileManager] Cannot update profile - no current profile")
            return
        }

        if let name = name {
            print("👤 [ProfileManager] Updating profile name to: \(name)")
            profile.name = name
        }
        if let currency = preferredCurrency {
            print("👤 [ProfileManager] Updating preferred currency to: \(currency.rawValue)")
            profile.preferredCurrency = currency
        }

        currentProfile = profile

        // Sync to Firestore
        Task {
            do {
                try await FirebaseManager.shared.saveUserProfile(profile)
                print("✅ [ProfileManager] Profile changes synced to Firestore")
            } catch {
                print("❌ [ProfileManager] Failed to sync profile to Firestore: \(error)")
            }
        }
    }

    @MainActor func updateProfile(_ profile: UserProfile) {
        print("👤 [ProfileManager] Updating profile: \(profile.name)")
        print("👤 [ProfileManager] Trip codes: \(profile.tripCodes)")
        print("👤 [ProfileManager] Linked payment accounts: \(profile.linkedPaymentAccounts.count)")
        currentProfile = profile

        // Sync to Firestore to persist changes
        Task {
            do {
                try await FirebaseManager.shared.saveUserProfile(profile)
                print("✅ [ProfileManager] Profile changes synced to Firestore")
            } catch {
                print("❌ [ProfileManager] Failed to sync profile to Firestore: \(error)")
            }
        }
    }

    @MainActor func updateProfileWithFirebaseUID(_ firebaseUID: String) {
        guard var profile = currentProfile else { return }
        profile.firebaseUID = firebaseUID
        currentProfile = profile
    }

    @MainActor func syncProfileFromFirebase() async {
        print("🔄 [ProfileManager] Starting profile sync from Firestore...")
        do {
            if let remoteProfile = try await FirebaseManager.shared.fetchUserProfile() {
                print("📥 [ProfileManager] Found remote profile: \(remoteProfile.name)")
                print("📥 [ProfileManager] Remote profile ID: \(remoteProfile.id)")
                print("📥 [ProfileManager] Remote Firebase UID: \(remoteProfile.firebaseUID ?? "nil")")
                print("📥 [ProfileManager] Remote trip codes: \(remoteProfile.tripCodes)")

                // Merge remote profile with local
                if let localProfile = currentProfile {
                    print("📥 [ProfileManager] Local profile exists: \(localProfile.name)")
                    // If local profile was updated more recently, keep local data
                    let localLastModified = localProfile.lastSynced ?? localProfile.dateCreated
                    let remoteLastModified = remoteProfile.lastSynced ?? remoteProfile.dateCreated

                    if remoteLastModified > localLastModified {
                        print("📥 [ProfileManager] Using remote profile (newer: \(remoteLastModified) vs local: \(localLastModified))")
                        currentProfile = remoteProfile
                    } else {
                        print("📤 [ProfileManager] Keeping local profile (newer: \(localLastModified) vs remote: \(remoteLastModified)), syncing to Firestore")
                        try await FirebaseManager.shared.saveUserProfile(localProfile)
                    }
                } else {
                    // No local profile, use remote
                    print("📥 [ProfileManager] No local profile, using remote")
                    currentProfile = remoteProfile
                }
            } else {
                print("⚠️ [ProfileManager] No remote profile found in Firestore")
                if let localProfile = currentProfile {
                    // No remote profile, sync local to Firestore
                    print("📤 [ProfileManager] Syncing local profile to Firestore: \(localProfile.name)")
                    print("📤 [ProfileManager] Local profile ID: \(localProfile.id)")
                    print("📤 [ProfileManager] Local Firebase UID: \(localProfile.firebaseUID ?? "nil")")
                    try await FirebaseManager.shared.saveUserProfile(localProfile)
                    print("✅ [ProfileManager] Successfully synced local profile to Firestore")
                } else {
                    print("⚠️ [ProfileManager] No local or remote profile available")
                }
            }
        } catch {
            print("❌ [ProfileManager] Failed to sync profile: \(error)")
            if let nsError = error as NSError? {
                print("❌ [ProfileManager] Error domain: \(nsError.domain)")
                print("❌ [ProfileManager] Error code: \(nsError.code)")
                print("❌ [ProfileManager] Error details: \(nsError.localizedDescription)")
            }
        }
    }
    
    @MainActor func deleteProfile() {
        currentProfile = nil
    }
    
    @MainActor func createPersonFromProfile() -> Person? {
        guard let profile = currentProfile else { return nil }
        var person = Person(name: profile.name)
        person.id = profile.id
        person.firebaseUID = profile.firebaseUID
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
