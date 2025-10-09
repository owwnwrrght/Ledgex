import Foundation

struct UserProfile: Codable {
    var name: String
    var id: UUID = UUID()
    var firebaseUID: String? = nil  // Firebase Auth UID for cross-device linking
    var dateCreated: Date = Date()
    var preferredCurrency: Currency = .USD
    var tripCodes: [String] = []  // List of trip codes the user is part of
    var lastSynced: Date? = nil

    // Push notification token
    var pushToken: String? = nil
    var notificationsEnabled: Bool = true

    init(name: String, firebaseUID: String? = nil) {
        self.name = name
        self.firebaseUID = firebaseUID
    }
}