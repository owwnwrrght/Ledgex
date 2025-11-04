import Foundation
import UserNotifications
import FirebaseAuth
import FirebaseFirestore
import FirebaseMessaging
import SwiftUI
import Combine

// MARK: - Notification Service
class NotificationService: NSObject, ObservableObject {
    @MainActor static let shared = NotificationService()

    @MainActor @Published var hasPermission = false
    @MainActor @Published var fcmToken: String?

    override init() {
        FirebaseBootstrapper.configureIfNeeded()
        super.init()
        setupMessaging()
    }

    private func setupMessaging() {
        UNUserNotificationCenter.current().delegate = self
        Messaging.messaging().delegate = self
        fetchCurrentToken()
    }
    
    // Request notification permissions
    @MainActor func requestPermissions() async {
        do {
            let granted = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound])
            hasPermission = granted
            
            if granted {
                await MainActor.run {
                    UIApplication.shared.registerForRemoteNotifications()
                }
            }
        } catch {
            print("Failed to request notifications permission: \(error)")
        }
    }
    
    // Check current permission status
    @MainActor func checkPermissionStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        hasPermission = settings.authorizationStatus == .authorized
    }
    
    // Handle FCM token updates
    @MainActor func updateFCMToken(_ token: String) {
        fcmToken = token
        ProfileManager.shared.updatePushToken(token)

        // Also update token on the server for each trip the user is part of
        Task {
            await self.updateServerTokens()
        }
    }
    
    private func updateServerTokens() async {
        let profileAndToken = await MainActor.run { () -> (UserProfile?, String?) in
            (ProfileManager.shared.currentProfile, self.fcmToken)
        }
        guard let profile = profileAndToken.0,
              let token = profileAndToken.1,
              let firebaseUID = Auth.auth().currentUser?.uid else { return }
        let db = Firestore.firestore()
        let docRef = db.collection("users").document(firebaseUID)
        do {
            try await docRef.setData([
                "id": profile.id.uuidString,
                "firebaseUID": firebaseUID,
                "name": profile.name,
                "preferredCurrency": profile.preferredCurrency.rawValue,
                "updatedAt": FieldValue.serverTimestamp()
            ], merge: true)
            try await docRef.updateData([
                "tokens": FieldValue.arrayUnion([token])
            ])
        } catch {
            print("Failed to update FCM token in Firestore: \(error)")
        }
    }

    private func fetchCurrentToken() {
        Messaging.messaging().token { [weak self] token, error in
            if let error {
                print("Failed to fetch FCM token: \(error)")
                return
            }
            guard let token, let self else { return }
            Task { @MainActor in
                self.updateFCMToken(token)
            }
        }
    }
    
    // Send local notification (for testing)
    func sendLocalNotification(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("Failed to send local notification: \(error)")
            }
        }
    }
    
    // Trip-specific notification types
    enum NotificationType {
        case newExpense(tripName: String, expenseDescription: String, amount: String)
        case newMember(tripName: String, memberName: String)
        case expenseUpdate(tripName: String, expenseDescription: String)
        case settlementReminder(tripName: String, amount: String)
        case readyToSettle(tripName: String)
        
        var title: String {
            switch self {
            case .newExpense(let tripName, _, _):
                return "New expense in \(tripName)"
            case .newMember(let tripName, _):
                return "New member joined \(tripName)"
            case .expenseUpdate(let tripName, _):
                return "Expense updated in \(tripName)"
            case .settlementReminder(let tripName, _):
                return "Settlement reminder for \(tripName)"
            case .readyToSettle(let tripName):
                return "Settle up time for \(tripName)"
            }
        }
        
        var body: String {
            switch self {
            case .newExpense(_, let description, let amount):
                return "\(description) - \(amount)"
            case .newMember(_, let memberName):
                return "\(memberName) has joined the trip"
            case .expenseUpdate(_, let description):
                return "\(description) was modified"
            case .settlementReminder(_, let amount):
                return "You owe \(amount)"
            case .readyToSettle:
                return "Everyone has finished adding expenses."
            }
        }
    }
    
    // Send trip notification
    @MainActor func sendTripNotification(_ type: NotificationType) {
        guard hasPermission else { return }
        sendLocalNotification(title: type.title, body: type.body)
    }
}

// MARK: - UNUserNotificationCenterDelegate
extension NotificationService: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        // Show notifications even when app is in foreground
        completionHandler([.banner, .sound, .badge])
    }
    
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        // Handle notification tap
        let userInfo = response.notification.request.content.userInfo
        print("Notification tapped with userInfo: \(userInfo)")
        completionHandler()
    }
}

// MARK: - MessagingDelegate
extension NotificationService: MessagingDelegate {
    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        guard let token = fcmToken else { return }
        Task { @MainActor in
            self.updateFCMToken(token)
        }
    }
}
