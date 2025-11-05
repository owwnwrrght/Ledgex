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

    // Venmo payment integration
    var venmoUsername: String? = nil

    init(name: String, firebaseUID: String? = nil) {
        self.name = name
        self.firebaseUID = firebaseUID
    }

    var hasVenmoLinked: Bool {
        return venmoUsername != nil && !venmoUsername!.isEmpty
    }

    var formattedVenmoUsername: String? {
        guard let username = venmoUsername, !username.isEmpty else { return nil }
        // Ensure it starts with @
        return username.hasPrefix("@") ? username : "@\(username)"
    }
}