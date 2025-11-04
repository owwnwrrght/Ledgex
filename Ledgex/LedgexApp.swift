import SwiftUI
import FirebaseCore
import FirebaseFirestore
import FirebaseMessaging
import UserNotifications
import GoogleSignIn

enum FirebaseBootstrapper {
    static func configureIfNeeded() {
        guard FirebaseApp.app() == nil else { return }

        guard Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist") != nil else {
            fatalError("GoogleService-Info.plist not found in app bundle. Please add it to your Xcode project.")
        }

        FirebaseApp.configure()
        print("FirebaseBootstrapper: Firebase configured successfully")
    }
}

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        // Ensure Firebase is configured before any SDK usage
        FirebaseBootstrapper.configureIfNeeded()

        // Pre-warm Firebase to avoid PAC proxy delays
        Firestore.firestore().collection("ping").document("ping").getDocument { _, _ in
            print("Firebase pre-warm completed")
        }

        Task { @MainActor in
            Messaging.messaging().isAutoInitEnabled = true
            _ = NotificationService.shared
            await NotificationService.shared.checkPermissionStatus()
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

    func application(_ app: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey : Any] = [:]) -> Bool {
        if GIDSignIn.sharedInstance.handle(url) {
            return true
        }
        return false
    }
}

@main
struct LedgexApp: App {
    // register app delegate for Firebase setup
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var authViewModel: AuthViewModel

    init() {
        FirebaseBootstrapper.configureIfNeeded()
        _authViewModel = StateObject(wrappedValue: AuthViewModel())

        // Verify URL scheme configuration at startup
        if let urlTypes = Bundle.main.infoDictionary?["CFBundleURLTypes"] as? [[String: Any]] {
            print("📋 Registered URL Schemes:")
            for urlType in urlTypes {
                if let schemes = urlType["CFBundleURLSchemes"] as? [String] {
                    print("   - \(schemes.joined(separator: ", "))")
                }
            }
        } else {
            print("⚠️  WARNING: No URL schemes registered!")
        }

        // Verify associated domains
        print("📋 Bundle ID: \(Bundle.main.bundleIdentifier ?? "unknown")")
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(authViewModel)
                .onOpenURL { url in
                    print("🌐 LedgexApp: onOpenURL called with: \(url.absoluteString)")
                }
        }
    }
}
