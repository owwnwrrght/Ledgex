import SwiftUI
import FirebaseCore
import FirebaseFirestore
import FirebaseMessaging
import UserNotifications

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        // Configure Firebase (GoogleService-Info.plist must be in bundle)
        if Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist") != nil {
            print("Found GoogleService-Info.plist")
            FirebaseApp.configure()
            
            
            // Pre-warm Firebase to avoid PAC proxy delays
            Firestore.firestore().collection("ping").document("ping").getDocument { _, _ in
                print("Firebase pre-warm completed")
            }

            Task { @MainActor in
                Messaging.messaging().isAutoInitEnabled = true
                _ = NotificationService.shared
                await NotificationService.shared.checkPermissionStatus()
            }
        } else {
            fatalError("GoogleService-Info.plist not found in app bundle. Please add it to your Xcode project.")
        }
        return true
    }
    
    // Handle remote notification registration
    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        // Device token registered successfully
        print("Device token registered: \(deviceToken)")
        Messaging.messaging().apnsToken = deviceToken
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        print("Failed to register for remote notifications: \(error)")
    }
}

@main
struct LedgexApp: App {
    // register app delegate for Firebase setup
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var authViewModel = AuthViewModel()
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(authViewModel)
        }
    }
}
