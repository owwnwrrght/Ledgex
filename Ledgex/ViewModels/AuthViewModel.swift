import AuthenticationServices
import CryptoKit
import FirebaseAuth
import FirebaseCore
import FirebaseFirestore
import Foundation
import Security
import UIKit
import Combine
import GoogleSignIn

extension Notification.Name {
    static let ledgexUserDidSignIn = Notification.Name("LedgexUserDidSignIn")
    static let ledgexUserDidSignOut = Notification.Name("LedgexUserDidSignOut")
    static let ledgexUserDidDeleteAccount = Notification.Name("LedgexUserDidDeleteAccount")
}

@MainActor
final class AuthViewModel: NSObject, ObservableObject, ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {
    enum AuthFlow {
        case signInWithApple
        case emailPassword
    }
    enum PendingAction {
        case signIn
        case accountDeletionReauth
    }

    enum AuthErrorStage: String {
        case initialization = "Initialization"
        case appleAuthorization = "Apple Authorization"
        case googleAuthorization = "Google Authorization"
        case credentialExtraction = "Credential Extraction"
        case nonceValidation = "Nonce Validation"
        case tokenExtraction = "Token Extraction"
        case firebaseCredential = "Firebase Credential Creation"
        case firebaseSignIn = "Firebase Sign-In"
        case profileSetup = "Profile Setup"
        case networkConnectivity = "Network Connectivity"
        case systemPermissions = "System Permissions"
    }

    @Published var isSignedIn: Bool
    @Published var currentFlow: AuthFlow = .signInWithApple
    @Published var email: String = ""
    @Published var password: String = ""
    @Published var emailModeIsSignUp = false
    @Published var isProcessing = false
    @Published var errorMessage: String?
    @Published var detailedErrorLog: [String] = []
    @Published var showAccountDeletionReauthSheet = false
    @Published var requiresEmailReauth = false
    @Published var reauthEmail: String = ""
    @Published var reauthPassword: String = ""
    @Published var emailReauthError: String?

    private var currentNonce: String?
    private var authStateHandle: AuthStateDidChangeListenerHandle?
    private var pendingAction: PendingAction = .signIn
    private var authorizationController: ASAuthorizationController?
    private var authStartTime: Date?
    private let maxFirebaseSignInAttempts = 3
    private var cachedPresentationAnchor: ASPresentationAnchor?
    
    override init() {
        let user = Auth.auth().currentUser
        self.isSignedIn = user != nil
        super.init()
        
        authStateHandle = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.isSignedIn = user != nil
                await FirebaseManager.shared.updateAvailability(for: user)
            }
        }
        
        Task {
            await FirebaseManager.shared.checkFirebaseStatus()
        }
    }
    
    deinit {
        if let handle = authStateHandle {
            Auth.auth().removeStateDidChangeListener(handle)
        }
    }
    
    func prepareSignInRequest(_ request: ASAuthorizationAppleIDRequest) {
        print("🔐 [Auth] prepareSignInRequest called")
        detailedErrorLog = []
        authStartTime = Date()
        logError(stage: .initialization, message: "Sign-in initiated at \(Date())")

        // System environment checks
        logError(stage: .systemPermissions, message: "iOS Version: \(UIDevice.current.systemVersion)")
        logError(stage: .systemPermissions, message: "Device Model: \(UIDevice.current.model)")
        logError(stage: .systemPermissions, message: "Simulator: \(isSimulator ? "YES" : "NO")")

        // Check Sign in with Apple availability
        let _ = ASAuthorizationAppleIDProvider()
        logError(stage: .systemPermissions, message: "ASAuthorizationAppleIDProvider initialized")

        // Check network connectivity
        logError(stage: .networkConnectivity, message: "Checking network connectivity...")
        checkNetworkConnectivity()

        // Check Firebase status
        if Auth.auth().currentUser != nil {
            logError(stage: .initialization, message: "Warning: User already signed in")
        } else {
            logError(stage: .initialization, message: "No existing Firebase session")
        }

        pendingAction = .signIn
        configure(request: request, requestFullName: true)
        print("🔐 [Auth] Request configured with nonce: \(currentNonce?.prefix(8) ?? "nil")...")
        logError(stage: .initialization, message: "Request configured successfully with nonce")
    }

    func prepareAccountDeletionReauthRequest(_ request: ASAuthorizationAppleIDRequest) {
        print("🔐 [Auth] prepareAccountDeletionReauthRequest called")
        detailedErrorLog = []
        authStartTime = Date()
        pendingAction = .accountDeletionReauth
        configure(request: request, requestFullName: false)
        print("🔐 [Auth] Reauth request configured")
    }

    func cancelAccountDeletionReauth() {
        print("🔐 [Auth] Canceling account deletion reauth sheet")
        showAccountDeletionReauthSheet = false
        pendingAction = .signIn
        isProcessing = false
    }

    @MainActor
    func updatePresentationAnchor(_ anchor: ASPresentationAnchor?) {
        cachedPresentationAnchor = anchor
        if let anchor {
            logError(stage: .systemPermissions, message: "Presentation anchor resolved: \(anchor)")
        } else {
            logError(stage: .systemPermissions, message: "Presentation anchor cleared")
        }
    }
    
    func switchToEmailFlow() {
        currentFlow = .emailPassword
        errorMessage = nil
    }

    func signInWithEmail() {
        Task { @MainActor in await performEmailSignIn() }
    }

    func signUpWithEmail() {
        Task { @MainActor in await performEmailSignUp() }
    }

    func signInWithGoogle() {
        Task { await startGoogleSignInFlow() }
    }

    func cancelEmailReauth() {
        requiresEmailReauth = false
        reauthPassword = ""
        emailReauthError = nil
        isProcessing = false
    }

    func confirmEmailAccountDeletion() {
        Task { await performEmailReauthAndDelete() }
    }

    private var isSimulator: Bool {
        #if targetEnvironment(simulator)
        return true
        #else
        return false
        #endif
    }

    private func checkNetworkConnectivity() {
        // Simple network check using a Firebase ping
        let db = Firestore.firestore()
        db.collection("ping").document("check").getDocument { [weak self] (_, error: Error?) in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let error = error {
                    self.logError(stage: .networkConnectivity, message: "❌ Network check failed: \(error.localizedDescription)")
                } else {
                    self.logError(stage: .networkConnectivity, message: "✅ Network connectivity confirmed")
                }
            }
        }
    }
    
    func handleSignInCompletion(_ result: Result<ASAuthorization, Error>) {
        print("🔐 [Auth] handleSignInCompletion called")
        let elapsed = authStartTime.map { String(format: "%.2f", Date().timeIntervalSince($0)) } ?? "?"
        logError(stage: .appleAuthorization, message: "Authorization callback received after \(elapsed)s")

        switch result {
        case .success(let authorization):
            print("🔐 [Auth] ✅ Authorization successful")
            logError(stage: .appleAuthorization, message: "✅ Authorization successful")

            print("🔐 [Auth] Credential type: \(type(of: authorization.credential))")
            logError(stage: .credentialExtraction, message: "Credential type: \(type(of: authorization.credential))")

            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
                print("🔐 [Auth] ❌ Failed to cast credential to ASAuthorizationAppleIDCredential")
                let errorMsg = "❌ Failed to cast credential. Received type: \(type(of: authorization.credential))"
                logError(stage: .credentialExtraction, message: errorMsg)
                errorMessage = "Unable to obtain Apple ID credential. Wrong credential type received."
                return
            }

            print("🔐 [Auth] User ID: \(credential.user)")
            print("🔐 [Auth] Email: \(credential.email ?? "nil")")
            print("🔐 [Auth] Full name: \(credential.fullName?.givenName ?? "nil") \(credential.fullName?.familyName ?? "nil")")

            logError(stage: .credentialExtraction, message: "✅ Credential extracted successfully")
            logError(stage: .credentialExtraction, message: "User ID: \(credential.user)")
            logError(stage: .credentialExtraction, message: "Email: \(credential.email ?? "not provided")")
            logError(stage: .credentialExtraction, message: "Real user status: \(credential.realUserStatus.rawValue)")

            processAppleCredential(credential)

        case .failure(let error):
            print("🔐 [Auth] ❌ Authorization failed")
            print("🔐 [Auth] Error: \(error)")
            print("🔐 [Auth] Error localized: \(error.localizedDescription)")

            logError(stage: .appleAuthorization, message: "❌ Authorization failed after \(elapsed)s")
            logError(stage: .appleAuthorization, message: "Error: \(error)")
            logError(stage: .appleAuthorization, message: "Localized: \(error.localizedDescription)")

            if let authError = error as? ASAuthorizationError {
                print("🔐 [Auth] ASAuthorizationError code: \(authError.code.rawValue)")
                logError(stage: .appleAuthorization, message: "ASAuthorizationError code: \(authError.code.rawValue)")

                let (userMessage, debugMessage) = messages(for: authError)
                logError(stage: .appleAuthorization, message: debugMessage)
                errorMessage = userMessage
                isProcessing = false

                // Check for underlying errors
                if let underlyingError = (error as NSError).userInfo[NSUnderlyingErrorKey] as? NSError {
                    logError(stage: .appleAuthorization, message: "Underlying error domain: \(underlyingError.domain)")
                    logError(stage: .appleAuthorization, message: "Underlying error code: \(underlyingError.code)")
                    logError(stage: .appleAuthorization, message: "Underlying error: \(underlyingError.localizedDescription)")
                }
            } else if let nsError = error as NSError? {
                logError(stage: .appleAuthorization, message: "NSError domain: \(nsError.domain)")
                logError(stage: .appleAuthorization, message: "NSError code: \(nsError.code)")
                logError(stage: .appleAuthorization, message: "UserInfo: \(nsError.userInfo)")
                let userMessage = userFacingMessage(for: nsError)
                if userMessage == nil && nsError.domain == ASAuthorizationError.errorDomain {
                    errorMessage = nil
                } else {
                    errorMessage = userMessage ?? error.localizedDescription
                }
                isProcessing = false
            } else {
                errorMessage = "Sign in with Apple is unavailable right now. Please try again."
                isProcessing = false
            }
        }
    }
    
    func signOut() {
        print("🔐 [Auth] Starting sign-out process...")
        Task { [weak self] in
            await self?.performSignOut()
        }
    }

    @MainActor
    private func performSignOut() async {
        do {
            try Auth.auth().signOut()
            print("✅ Signed out from Firebase Auth")

            await cleanupUserData()

            NotificationCenter.default.post(name: .ledgexUserDidSignOut, object: nil)

            isSignedIn = false
            errorMessage = nil
            detailedErrorLog = []
            pendingAction = .signIn
            showAccountDeletionReauthSheet = false
            requiresEmailReauth = false
            reauthPassword = ""
            emailReauthError = nil

            print("✅ Sign-out complete")
        } catch {
            print("❌ Sign-out error: \(error.localizedDescription)")
            errorMessage = "Failed to sign out: \(error.localizedDescription)"
        }
    }

    @MainActor
    private func cleanupUserData() async {
        print("🧹 Cleaning up user data...")

        // Clear profile
        ProfileManager.shared.deleteProfile()
        print("  ✓ Profile cleared")

        // Clear trip data
        DataManager.shared.clearAllData()
        print("  ✓ Trip data cleared")

        // Clear join code history
        JoinCodeHistory.shared.clear()
        print("  ✓ Join code history cleared")

        // Clear Firebase manager state
        await FirebaseManager.shared.clearLocalState()
        print("  ✓ Firebase state cleared")

        print("✅ All user data cleaned up")
    }

    func initiateAccountDeletion() {
        guard let user = Auth.auth().currentUser else {
            errorMessage = "No signed in user."
            return
        }
        errorMessage = nil
        emailReauthError = nil
        requiresEmailReauth = false
        showAccountDeletionReauthSheet = false
        reauthPassword = ""
        isProcessing = false

        let providerIDs = Set(user.providerData.map { $0.providerID })

        if providerIDs.contains("password") {
            reauthEmail = user.email ?? email
            requiresEmailReauth = true
            return
        }

        if providerIDs.contains("apple.com") {
            pendingAction = .accountDeletionReauth
            showAccountDeletionReauthSheet = true
            return
        }

        isProcessing = true
        Task { await deleteAccountWithoutReauth() }
    }

    private func deleteAccountWithoutReauth() async {
        guard let user = Auth.auth().currentUser else {
            await MainActor.run {
                self.isProcessing = false
                self.errorMessage = "No signed in user."
            }
            return
        }

        print("🔐 [Auth] Starting direct account deletion (no reauth)...")

        // Remove user data in Firestore before deleting the auth record
        if let profile = ProfileManager.shared.currentProfile {
            do {
                try await FirebaseManager.shared.removeUserData(for: profile)
                print("✅ User data removed from Firestore")
            } catch {
                print("⚠️ Error removing user data from Firestore: \(error.localizedDescription)")
                // Continue even if cleanup fails so users aren't blocked
            }
        }

        do {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                user.delete { error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume(returning: ())
                    }
                }
            }

            print("✅ Firebase Auth account deleted without reauth")
            try? Auth.auth().signOut()

            await cleanupUserData()
            NotificationCenter.default.post(name: .ledgexUserDidDeleteAccount, object: nil)

            await MainActor.run {
                self.isSignedIn = false
                self.errorMessage = nil
                self.detailedErrorLog = []
                self.pendingAction = .signIn
                self.isProcessing = false
            }

            print("✅ Account deletion flow completed")
        } catch {
            print("❌ Account deletion failed without reauth: \(error.localizedDescription)")

            if let nsError = error as NSError?,
               let code = AuthErrorCode(rawValue: nsError.code),
               code == .requiresRecentLogin {
                print("⚠️ Account deletion requires recent login. Prompting reauthentication.")
                let providerIDs = user.providerData.map { $0.providerID }

                await MainActor.run {
                    self.isProcessing = false
                }

                if providerIDs.contains("password") {
                    await MainActor.run {
                        self.reauthEmail = user.email ?? self.email
                        self.reauthPassword = ""
                        self.emailReauthError = nil
                        self.requiresEmailReauth = true
                    }
                } else {
                    await MainActor.run {
                        self.pendingAction = .accountDeletionReauth
                        self.showAccountDeletionReauthSheet = true
                    }
                }
                return
            } else {
                await MainActor.run {
                    self.isProcessing = false
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }
    
    // MARK: - ASAuthorizationControllerDelegate
    nonisolated func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        print("🔐 [Auth-Delegate] didCompleteWithAuthorization called")
        Task { @MainActor [weak self] in
            guard let self else { return }
            let elapsed = authStartTime.map { String(format: "%.2f", Date().timeIntervalSince($0)) } ?? "?"
            logError(stage: .appleAuthorization, message: "[Delegate] Authorization success after \(elapsed)s")

            print("🔐 [Auth-Delegate] Processing on MainActor")
            print("🔐 [Auth-Delegate] Credential type: \(type(of: authorization.credential))")

            logError(stage: .credentialExtraction, message: "[Delegate] Credential type: \(type(of: authorization.credential))")

            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
                print("🔐 [Auth-Delegate] ❌ Failed to cast credential")
                logError(stage: .credentialExtraction, message: "[Delegate] ❌ Failed to cast credential")
                self.errorMessage = "Unable to obtain Apple ID credential."
                self.isProcessing = false
                return
            }

            print("🔐 [Auth-Delegate] ✅ Credential obtained, processing...")
            logError(stage: .credentialExtraction, message: "[Delegate] ✅ Credential obtained")
            logError(stage: .credentialExtraction, message: "[Delegate] User ID: \(credential.user)")

            self.processAppleCredential(credential)
        }
    }

    nonisolated func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        print("🔐 [Auth-Delegate] ❌ didCompleteWithError called")
        print("🔐 [Auth-Delegate] Error: \(error)")
        print("🔐 [Auth-Delegate] Error localized: \(error.localizedDescription)")

        Task { @MainActor [weak self] in
            guard let self else { return }
            let elapsed = authStartTime.map { String(format: "%.2f", Date().timeIntervalSince($0)) } ?? "?"
            logError(stage: .appleAuthorization, message: "[Delegate] ❌ Authorization error after \(elapsed)s")
            logError(stage: .appleAuthorization, message: "[Delegate] Error: \(error)")
            logError(stage: .appleAuthorization, message: "[Delegate] Localized: \(error.localizedDescription)")

            if let authError = error as? ASAuthorizationError {
                print("🔐 [Auth-Delegate] ASAuthorizationError code: \(authError.code.rawValue)")
                logError(stage: .appleAuthorization, message: "[Delegate] ASAuthorizationError code: \(authError.code.rawValue)")

                let (userMessage, debugMessage) = messages(for: authError, prefix: "[Delegate]")
                logError(stage: .appleAuthorization, message: debugMessage)
                self.errorMessage = userMessage
            } else if let nsError = error as NSError? {
                logError(stage: .appleAuthorization, message: "[Delegate] NSError domain: \(nsError.domain)")
                logError(stage: .appleAuthorization, message: "[Delegate] NSError code: \(nsError.code)")
                let userMessage = userFacingMessage(for: nsError)
                if userMessage == nil && nsError.domain == ASAuthorizationError.errorDomain {
                    self.errorMessage = nil
                } else {
                    self.errorMessage = userMessage ?? "Sign in with Apple is unavailable right now. Please try again."
                }
            } else {
                self.errorMessage = "Sign in with Apple is unavailable right now. Please try again."
            }

            self.isProcessing = false
        }
    }
    
    // MARK: - ASAuthorizationControllerPresentationContextProviding
    nonisolated func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            if let anchor = cachedPresentationAnchor, anchor.windowScene != nil {
                return anchor
            } else {
                cachedPresentationAnchor = nil
            }

            let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            let prioritizedStates: [UIScene.ActivationState] = [.foregroundActive, .foregroundInactive, .background, .unattached]

            for state in prioritizedStates {
                for scene in scenes where scene.activationState == state {
                    if let keyWindow = scene.windows.first(where: { $0.isKeyWindow }) {
                        cachedPresentationAnchor = keyWindow
                        return keyWindow
                    }
                }
            }

            for state in prioritizedStates {
                for scene in scenes where scene.activationState == state {
                    if let visibleWindow = scene.windows.first(where: { !$0.isHidden && $0.alpha > 0 }) {
                        cachedPresentationAnchor = visibleWindow
                        return visibleWindow
                    }
                }
            }

            if let fallback = scenes.first?.windows.first {
                cachedPresentationAnchor = fallback
                return fallback
            }

            return UIWindow(frame: UIScreen.main.bounds)
        }
    }
    
    // MARK: - Private helpers
    private func configure(request: ASAuthorizationAppleIDRequest, requestFullName: Bool) {
        print("🔐 [Auth] configure() called")
        print("🔐 [Auth] requestFullName: \(requestFullName)")
        errorMessage = nil
        let nonce = randomNonceString()
        currentNonce = nonce
        request.requestedScopes = requestFullName ? [.fullName, .email] : []
        request.nonce = sha256(nonce)
        print("🔐 [Auth] Generated nonce: \(nonce.prefix(8))...")
        print("🔐 [Auth] SHA256 nonce: \(sha256(nonce).prefix(16))...")
        print("🔐 [Auth] Requested scopes: \(request.requestedScopes ?? [])")
    }
    
    private func processAppleCredential(_ credential: ASAuthorizationAppleIDCredential) {
        print("🔐 [Auth] processAppleCredential() called")
        logError(stage: .credentialExtraction, message: "Processing Apple credential...")

        print("🔐 [Auth] User: \(credential.user)")
        print("🔐 [Auth] Email: \(credential.email ?? "nil")")
        print("🔐 [Auth] Identity token exists: \(credential.identityToken != nil)")
        print("🔐 [Auth] Authorization code exists: \(credential.authorizationCode != nil)")

        logError(stage: .credentialExtraction, message: "Identity token present: \(credential.identityToken != nil)")
        logError(stage: .credentialExtraction, message: "Authorization code present: \(credential.authorizationCode != nil)")

        guard let nonce = currentNonce else {
            print("🔐 [Auth] ❌ No current nonce!")
            logError(stage: .nonceValidation, message: "❌ CRITICAL: No nonce available - state was lost")
            errorMessage = "Invalid login state. Please try again."
            isProcessing = false
            return
        }
        print("🔐 [Auth] ✅ Nonce verified: \(nonce.prefix(8))...")
        logError(stage: .nonceValidation, message: "✅ Nonce validated: \(nonce.prefix(8))...")

        guard let appleIDToken = credential.identityToken else {
            print("🔐 [Auth] ❌ No identity token in credential")
            logError(stage: .tokenExtraction, message: "❌ No identity token in credential")
            errorMessage = "Unable to fetch identity token from Apple."
            isProcessing = false
            return
        }

        logError(stage: .tokenExtraction, message: "Identity token data received (bytes: \(appleIDToken.count))")

        guard let idTokenString = String(data: appleIDToken, encoding: .utf8) else {
            print("🔐 [Auth] ❌ Failed to decode identity token as UTF-8")
            logError(stage: .tokenExtraction, message: "❌ Failed to decode token as UTF-8")
            errorMessage = "Unable to decode identity token."
            isProcessing = false
            return
        }

        print("🔐 [Auth] ✅ Identity token obtained (length: \(idTokenString.count))")
        logError(stage: .tokenExtraction, message: "✅ Token string decoded (length: \(idTokenString.count))")

        let firebaseCredential = OAuthProvider.credential(
            providerID: AuthProviderID.apple,
            idToken: idTokenString,
            rawNonce: nonce
        )
        print("🔐 [Auth] ✅ Firebase credential created")
        logError(stage: .firebaseCredential, message: "✅ Firebase OAuthCredential created successfully")
        logError(stage: .firebaseCredential, message: "Provider ID: apple.com")
        print("🔐 [Auth] Pending action: \(pendingAction)")

        isProcessing = true
        Task {
            do {
                print("🔐 [Auth] Starting async authentication task...")
                logError(stage: .firebaseSignIn, message: "Starting Firebase authentication...")

                switch self.pendingAction {
                case .signIn:
                    print("🔐 [Auth] Executing sign-in flow...")
                    logError(stage: .firebaseSignIn, message: "Flow: New sign-in")
                    try await self.authenticateWithFirebase(credential: firebaseCredential, appleCredential: credential)
                    print("🔐 [Auth] ✅ Sign-in completed successfully")
                    logError(stage: .firebaseSignIn, message: "✅ Firebase sign-in successful")

                    let totalElapsed = authStartTime.map { String(format: "%.2f", Date().timeIntervalSince($0)) } ?? "?"
                    logError(stage: .profileSetup, message: "✅ COMPLETE - Total time: \(totalElapsed)s")

                    await MainActor.run {
                        print("🔐 [Auth] Cleaning up after successful auth")
                        self.currentNonce = nil
                        self.authorizationController = nil
                        self.errorMessage = nil
                        self.isProcessing = false
                        self.showAccountDeletionReauthSheet = false
                        self.pendingAction = .signIn
                    }

                case .accountDeletionReauth:
                    print("🔐 [Auth] Executing reauthenticate-delete flow...")
                    logError(stage: .firebaseSignIn, message: "Flow: Reauthenticate for deletion")
                    try await self.reauthenticateAndDelete(credential: firebaseCredential)

                    await MainActor.run {
                        self.currentNonce = nil
                        self.authorizationController = nil
                        self.errorMessage = nil
                        self.showAccountDeletionReauthSheet = false
                        self.pendingAction = .signIn
                        self.isProcessing = false
                    }
                    return
                }
            } catch {
                print("🔐 [Auth] ❌ Authentication error: \(error)")
                print("🔐 [Auth] Error type: \(type(of: error))")

                logError(stage: .firebaseSignIn, message: "❌ Firebase authentication failed")
                logError(stage: .firebaseSignIn, message: "Error type: \(type(of: error))")
                logError(stage: .firebaseSignIn, message: "Error: \(error.localizedDescription)")

                let nsError = error as NSError?
                if let nsError {
                    print("🔐 [Auth] NSError domain: \(nsError.domain), code: \(nsError.code)")
                    print("🔐 [Auth] NSError userInfo: \(nsError.userInfo)")

                    logError(stage: .firebaseSignIn, message: "Domain: \(nsError.domain)")
                    logError(stage: .firebaseSignIn, message: "Code: \(nsError.code)")
                    logError(stage: .firebaseSignIn, message: "UserInfo: \(nsError.userInfo)")

                    // Check for specific Firebase error codes
                    if nsError.domain == "FIRAuthErrorDomain" {
                        logError(stage: .firebaseSignIn, message: "Firebase Auth Error Code: \(nsError.code)")
                        switch nsError.code {
                        case 17999:
                            logError(stage: .networkConnectivity, message: "Network error - check internet connection")
                        case 17011:
                            logError(stage: .firebaseSignIn, message: "User not found")
                        case 17009:
                            logError(stage: .firebaseSignIn, message: "Invalid credential")
                        default:
                            logError(stage: .firebaseSignIn, message: "Other Firebase auth error")
                        }
                    }
                }

                await MainActor.run {
                    if let nsError {
                        let userMessage = self.userFacingMessage(for: nsError) ?? error.localizedDescription
                        self.errorMessage = userMessage
                    } else {
                        self.errorMessage = error.localizedDescription
                    }
                    self.isProcessing = false
                    self.pendingAction = .signIn
                }
            }
        }
    }
    
    @MainActor
    private func authenticateWithFirebase(credential: AuthCredential, appleCredential: ASAuthorizationAppleIDCredential) async throws {
        print("🔐 [Auth] authenticateWithFirebase() called")
        print("🔐 [Auth] Signing in to Firebase...")
        let authResult = try await signInWithFirebase(credential: credential)
        print("🔐 [Auth] ✅ Firebase sign-in successful")
        print("🔐 [Auth] User ID: \(authResult.user.uid)")
        print("🔐 [Auth] User email: \(authResult.user.email ?? "nil")")

        await FirebaseManager.shared.updateAvailability(for: authResult.user)
        print("🔐 [Auth] Firebase availability updated")

        // Get the name BEFORE syncing from Firestore (because sync might not have a profile yet)
        let appleProvidedName = formattedName(from: appleCredential)
        let resolvedName = resolvedDisplayName(
            from: appleCredential,
            fallbackUser: authResult.user,
            appleProvidedName: appleProvidedName
        )
        print("🔐 [Auth] Resolved display name: \(resolvedName)")

        // Try to sync profile from Firestore
        print("🔐 [Auth] Attempting to sync profile from Firestore...")
        await ProfileManager.shared.syncProfileFromFirebase()
        print("🔐 [Auth] Profile sync complete. Current profile: \(ProfileManager.shared.currentProfile?.name ?? "nil")")

        // ALWAYS ensure we have a profile after sign-in
        if ProfileManager.shared.currentProfile == nil {
            let shouldCaptureName = (appleProvidedName?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)

            if shouldCaptureName {
                print("🔐 [Auth] Full name not provided by Apple. Prompting user to enter name manually.")
                ProfileManager.shared.deleteProfile()
                return
            }

            print("🔐 [Auth] No profile after sync, creating new profile with name: \(resolvedName)")
            let newProfile = UserProfile(name: resolvedName, firebaseUID: authResult.user.uid)
            ProfileManager.shared.setProfile(newProfile)
            print("🔐 [Auth] New profile set locally with ID: \(newProfile.id)")

            // Save new profile to Firestore synchronously
            do {
                try await FirebaseManager.shared.saveUserProfile(newProfile)
                print("🔐 [Auth] ✅ New profile saved to Firestore")
            } catch {
                print("🔐 [Auth] ❌ Failed to save new profile to Firestore: \(error)")
            }
        } else {
            print("🔐 [Auth] Profile exists after sync: \(ProfileManager.shared.currentProfile?.name ?? "unknown")")
            if let profile = ProfileManager.shared.currentProfile {
                print("🔐 [Auth] Profile details - ID: \(profile.id), Firebase UID: \(profile.firebaseUID ?? "nil"), Trip codes: \(profile.tripCodes)")
            }
            if let appleProvidedName,
               !appleProvidedName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               let profile = ProfileManager.shared.currentProfile,
               profile.name != appleProvidedName {
                print("🔐 [Auth] Updating profile name to Apple-provided name: \(appleProvidedName)")
                ProfileManager.shared.updateProfile(name: appleProvidedName)
            } else if let profile = ProfileManager.shared.currentProfile,
                      profile.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                print("🔐 [Auth] Updating empty profile name to: \(resolvedName)")
                ProfileManager.shared.updateProfile(name: resolvedName)
            }
        }

        if let appleProvidedName,
           !appleProvidedName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            await updateFirebaseDisplayName(for: authResult.user, to: appleProvidedName)
        }

        // Post notification to trigger trip sync and other post-signin tasks
        print("🔐 [Auth] ✅ Sign-in completed successfully")
        NotificationCenter.default.post(name: .ledgexUserDidSignIn, object: nil)
    }
    
    @MainActor
    private func reauthenticateAndDelete(credential: AuthCredential) async throws {
        guard let user = Auth.auth().currentUser else {
            throw NSError(domain: "LedgexAuth", code: -2, userInfo: [NSLocalizedDescriptionKey: "No authenticated user."])
        }

        print("🔐 [Auth] Starting account deletion process...")

        // Step 1: Reauthenticate
        print("🔐 [Auth] Reauthenticating user...")
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            user.reauthenticate(with: credential) { _, error in
                if let error {
                    print("❌ Reauthentication failed: \(error.localizedDescription)")
                    continuation.resume(throwing: error)
                } else {
                    print("✅ Reauthentication successful")
                    continuation.resume(returning: ())
                }
            }
        }

        // Step 2: Remove user data from Firestore (trips, profile, etc.)
        print("🗑️ Removing user data from Firestore...")
        if let profile = ProfileManager.shared.currentProfile {
            do {
                try await FirebaseManager.shared.removeUserData(for: profile)
                print("✅ User data removed from Firestore")
            } catch {
                print("⚠️ Error removing user data from Firestore: \(error.localizedDescription)")
                // Continue with deletion even if this fails
            }
        }

        // Step 3: Delete Firebase Auth account
        print("🗑️ Deleting Firebase Auth account...")
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            user.delete { error in
                if let error {
                    print("❌ Account deletion failed: \(error.localizedDescription)")
                    continuation.resume(throwing: error)
                } else {
                    print("✅ Firebase Auth account deleted")
                    continuation.resume(returning: ())
                }
            }
        }

        // Step 4: Clean up all local data
        print("🧹 Cleaning up local data...")
        await cleanupUserData()

        // Step 5: Post notification to trigger app-wide cleanup
        NotificationCenter.default.post(name: .ledgexUserDidDeleteAccount, object: nil)

        // Step 6: Reset UI state
        isSignedIn = false
        errorMessage = nil
        detailedErrorLog = []
        pendingAction = .signIn
        isProcessing = false

        print("✅ Account deletion complete")
    }
    
    private func resolvedDisplayName(
        from credential: ASAuthorizationAppleIDCredential,
        fallbackUser user: User,
        appleProvidedName: String? = nil
    ) -> String {
        if let formatted = appleProvidedName ?? formattedName(from: credential) {
            return formatted
        }
        if let displayName = user.displayName, !displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return displayName
        }
        if let email = credential.email, let prefix = email.split(separator: "@").first {
            return String(prefix)
        }
        if let email = user.email, let prefix = email.split(separator: "@").first {
            return String(prefix)
        }
        return "Ledgex Member"
    }
    
    private func formattedName(from credential: ASAuthorizationAppleIDCredential) -> String? {
        guard let components = credential.fullName else { return nil }
        let formatter = PersonNameComponentsFormatter()
        let name = formatter.string(from: components).trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? nil : name
    }

    private func updateFirebaseDisplayName(for user: User, to name: String) async {
        guard user.displayName != name else {
            print("🔐 [Auth] Firebase Auth display name already up to date")
            return
        }

        print("🔐 [Auth] Updating Firebase Auth display name to: \(name)")
        do {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                let changeRequest = user.createProfileChangeRequest()
                changeRequest.displayName = name
                changeRequest.commitChanges { error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume(returning: ())
                    }
                }
            }
            print("🔐 [Auth] ✅ Firebase Auth display name updated")
        } catch {
            print("🔐 [Auth] ❌ Failed to update Firebase Auth display name: \(error)")
        }
    }
    
    private func signInWithFirebase(credential: AuthCredential, attempt: Int = 1) async throws -> AuthDataResult {
        print("🔐 [Auth] signInWithFirebase() called (attempt \(attempt))")
        logError(stage: .firebaseSignIn, message: "Calling Firebase Auth.signIn()... (attempt \(attempt))")

        do {
            let result = try await performFirebaseSignIn(credential: credential)
            if attempt > 1 {
                logError(stage: .firebaseSignIn, message: "✅ Firebase sign-in succeeded on retry attempt \(attempt)")
            }
            return result
        } catch {
            let retryPlan = firebaseRetryPlan(for: error, attempt: attempt)
            if let retryPlan, attempt < maxFirebaseSignInAttempts {
                logError(stage: .firebaseSignIn, message: "⚠️ Firebase sign-in attempt \(attempt) failed with retryable error: \(error.localizedDescription)")
                if let code = retryPlan.code {
                    logError(stage: .firebaseSignIn, message: "Will retry for Firebase Auth error code \(code.rawValue)")
                }
                logError(stage: .firebaseSignIn, message: "Retrying in \(String(format: "%.2f", retryPlan.delay))s (attempt \(attempt + 1)/\(maxFirebaseSignInAttempts))")
                try await Task.sleep(nanoseconds: UInt64(retryPlan.delay * 1_000_000_000))
                return try await signInWithFirebase(credential: credential, attempt: attempt + 1)
            }

            logError(stage: .firebaseSignIn, message: "❌ Firebase sign-in giving up after \(attempt) attempt(s)")
            throw error
        }
    }

    private func performFirebaseSignIn(credential: AuthCredential) async throws -> AuthDataResult {
        print("🔐 [Auth] performFirebaseSignIn() called")

        let startTime = Date()
        return try await withCheckedThrowingContinuation { continuation in
            print("🔐 [Auth] Calling Firebase Auth.signIn()...")
            Auth.auth().signIn(with: credential) { result, error in
                let elapsed = String(format: "%.2f", Date().timeIntervalSince(startTime))

                if let error {
                    print("🔐 [Auth] ❌ Firebase sign-in error: \(error)")
                    Task { @MainActor [weak self] in
                        guard let self else { return }
                        self.logError(stage: .firebaseSignIn, message: "❌ Firebase sign-in failed after \(elapsed)s")
                        self.logError(stage: .firebaseSignIn, message: "Error: \(error)")
                    }
                    continuation.resume(throwing: error)
                } else if let result {
                    print("🔐 [Auth] ✅ Firebase sign-in result received")
                    Task { @MainActor [weak self] in
                        guard let self else { return }
                        self.logError(stage: .firebaseSignIn, message: "✅ Firebase sign-in succeeded after \(elapsed)s")
                        self.logError(stage: .firebaseSignIn, message: "User UID: \(result.user.uid)")
                    }
                    continuation.resume(returning: result)
                } else {
                    print("🔐 [Auth] ❌ No result and no error from Firebase")
                    Task { @MainActor [weak self] in
                        guard let self else { return }
                        self.logError(stage: .firebaseSignIn, message: "❌ No result and no error - unexpected state")
                    }
                    let error = NSError(domain: "LedgexAuth", code: -1, userInfo: [NSLocalizedDescriptionKey: "Unknown authentication error."])
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func firebaseRetryPlan(for error: Error, attempt: Int) -> (delay: TimeInterval, code: AuthErrorCode?)? {
        guard let nsError = error as NSError? else { return nil }

        if nsError.domain == NSURLErrorDomain {
            return (delay: min(2.5, pow(2.0, Double(attempt - 1)) * 0.75), code: nil)
        }

        if nsError.domain == "FIRAuthErrorDomain",
           let code = AuthErrorCode(rawValue: nsError.code) {
            switch code {
            case .networkError, .webNetworkRequestFailed, .internalError, .webInternalError, .tooManyRequests:
                return (delay: min(2.5, pow(2.0, Double(attempt - 1)) * 0.75), code: code)
            default:
                return nil
            }
        }

        return nil
    }

    private func logError(stage: AuthErrorStage, message: String) {
        let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        let logEntry = "[\(timestamp)] [\(stage.rawValue)] \(message)"
        print("🔐 [ErrorLog] \(logEntry)")
        detailedErrorLog.append(logEntry)
    }

    private func performEmailSignIn() async {
        errorMessage = nil
        guard validateEmailPasswordInputs() else { return }
        isProcessing = true
        do {
            let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
            let providers = try await fetchSignInMethods(for: trimmedEmail)

            if let redirectMessage = providerRedirectMessage(from: providers), !providers.contains("password") {
                await MainActor.run {
                    self.isProcessing = false
                    self.errorMessage = redirectMessage
                    self.emailModeIsSignUp = false
                }
                return
            }

            let result = try await Auth.auth().signIn(withEmail: trimmedEmail, password: password)
            try await postAuthenticationSetup(with: result)
            await MainActor.run {
                isProcessing = false
                currentFlow = .signInWithApple
                email = ""
                password = ""
            }
        } catch {
            await handleEmailAuthError(error)
        }
    }

    private func performEmailSignUp() async {
        errorMessage = nil
        guard validateEmailPasswordInputs(isSignUp: true) else { return }
        isProcessing = true
        do {
            let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
            let providers = try await fetchSignInMethods(for: trimmedEmail)

            if let redirectMessage = providerRedirectMessage(from: providers) {
                await MainActor.run {
                    self.isProcessing = false
                    self.errorMessage = redirectMessage
                    self.emailModeIsSignUp = false
                }
                return
            }

            let result = try await Auth.auth().createUser(withEmail: trimmedEmail, password: password)
            try await postAuthenticationSetup(with: result, requiresNameCapture: true)
            await MainActor.run {
                isProcessing = false
                currentFlow = .signInWithApple
                email = ""
                password = ""
            }
        } catch {
            await handleEmailAuthError(error)
        }
    }

    private func performEmailReauthAndDelete() async {
        let trimmedEmail = reauthEmail.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedEmail.isEmpty else {
            await MainActor.run { self.emailReauthError = "Enter your email." }
            return
        }

        guard reauthPassword.count >= 6 else {
            await MainActor.run { self.emailReauthError = "Password must be at least 6 characters." }
            return
        }

        await MainActor.run {
            self.emailReauthError = nil
            self.isProcessing = true
        }

        do {
            let credential = EmailAuthProvider.credential(withEmail: trimmedEmail, password: reauthPassword)
            try await reauthenticateAndDelete(credential: credential)
            await MainActor.run {
                requiresEmailReauth = false
                reauthPassword = ""
                emailReauthError = nil
            }
        } catch {
            await MainActor.run {
                self.isProcessing = false
                if let nsError = error as NSError?, let code = AuthErrorCode(rawValue: nsError.code) {
                    switch code {
                    case .wrongPassword:
                        self.emailReauthError = "Incorrect password."
                    case .userNotFound:
                        self.emailReauthError = "Account not found."
                    default:
                        self.emailReauthError = nsError.localizedDescription
                    }
                } else {
                    self.emailReauthError = error.localizedDescription
                }
            }
        }
    }

    private func validateEmailPasswordInputs(isSignUp: Bool = false) -> Bool {
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedEmail.isEmpty, trimmedEmail.contains("@"), trimmedEmail.contains(".") else {
            errorMessage = "Enter a valid email address."
            return false
        }

        guard password.count >= 6 else {
            errorMessage = "Password must be at least 6 characters."
            return false
        }

        if isSignUp {
            emailModeIsSignUp = true
        }

        return true
    }

    private func handleEmailAuthError(_ error: Error) async {
        await MainActor.run {
            isProcessing = false
            if let err = error as NSError? {
                switch AuthErrorCode(rawValue: err.code) {
                case .emailAlreadyInUse:
                    self.errorMessage = "An account already exists for that email. Try signing in instead."
                    self.emailModeIsSignUp = false
                case .weakPassword:
                    self.errorMessage = "Choose a stronger password."
                case .invalidEmail:
                    self.errorMessage = "That email doesn't look right."
                case .wrongPassword:
                    self.errorMessage = "Incorrect password."
                case .userNotFound:
                    self.errorMessage = "We couldn't find an account for that email."
                    self.emailModeIsSignUp = true
                default:
                    self.errorMessage = err.localizedDescription
                }
            } else {
                self.errorMessage = error.localizedDescription
            }
        }
    }

    private func postAuthenticationSetup(with authResult: AuthDataResult, requiresNameCapture: Bool = false) async throws {
        await FirebaseManager.shared.updateAvailability(for: authResult.user)
        await ProfileManager.shared.syncProfileFromFirebase()

        if requiresNameCapture {
            ProfileManager.shared.deleteProfile()
            return
        }

        if ProfileManager.shared.currentProfile == nil {
            let initialName = authResult.user.displayName ?? authResult.user.email ?? "Ledgex Member"
            let newProfile = UserProfile(name: initialName, firebaseUID: authResult.user.uid)
            ProfileManager.shared.setProfile(newProfile)
            try await FirebaseManager.shared.saveUserProfile(newProfile)
        }

        // Post notification to trigger trip sync and other post-signin tasks
        print("🔐 [Auth] ✅ Sign-in completed successfully")
        NotificationCenter.default.post(name: .ledgexUserDidSignIn, object: nil)
    }

    private func messages(for authError: ASAuthorizationError, prefix: String = "") -> (userFacing: String?, debug: String) {
        let debugPrefix = prefix.isEmpty ? "" : "\(prefix) "
        let code = authError.code
        
        if code == .canceled {
            logError(stage: .systemPermissions, message: "\(debugPrefix)Sign in with Apple canceled by user (1001)")
            logError(stage: .systemPermissions, message: "\(debugPrefix)Verify device is signed into iCloud and allows Apple ID sign-in")
            return (nil, "\(debugPrefix)User canceled Sign in with Apple (1001)")
        } else if code == .failed {
            return ("Sign in with Apple couldn’t finish. Please try again in a moment.", "\(debugPrefix)Authorization failed (1004) - System authentication error")
        } else if code == .invalidResponse {
            return ("We couldn’t verify Apple’s response. Please try again.", "\(debugPrefix)Invalid response (1003) - Received invalid data from Apple")
        } else if code == .notHandled {
            return ("Sign in with Apple wasn’t completed. Please try again.", "\(debugPrefix)Not handled (1002) - Authorization request not processed")
        } else if code == .notInteractive {
            logError(stage: .systemPermissions, message: "\(debugPrefix)Sign in with Apple UI could not be presented. Check foreground window scene.")
            return ("Sign in with Apple needs the app in the foreground. Please bring Ledgex forward and try again.", "\(debugPrefix)Not interactive - Cannot present authentication UI")
        } else if #available(iOS 18.0, *), code == .matchedExcludedCredential {
            return ("Sign in with Apple isn’t available for this Apple ID. You can sign in with email instead.", "\(debugPrefix)Matched excluded credential")
        } else if code == .unknown {
            return ("Sign in with Apple hit an unexpected issue. Please try again.", "\(debugPrefix)Unknown authorization error")
        }
        
        return ("Sign in with Apple hit an unexpected issue. Please try again.", "\(debugPrefix)Unhandled authorization error (code \(authError.code.rawValue))")
    }

    private func userFacingMessage(for nsError: NSError) -> String? {
        if nsError.domain == NSURLErrorDomain {
            switch nsError.code {
            case NSURLErrorNotConnectedToInternet, NSURLErrorNetworkConnectionLost:
                return "We couldn’t reach the internet. Check your connection and try again."
            case NSURLErrorTimedOut:
                return "The connection timed out. Please try again."
            default:
                return "We ran into a network issue. Please try again."
            }
        }

        if nsError.domain == ASAuthorizationError.errorDomain,
           let authCode = ASAuthorizationError.Code(rawValue: nsError.code) {
            if authCode == .canceled {
                return nil
            } else if authCode == .failed {
                return "Sign in with Apple couldn’t finish. Please try again in a moment."
            } else if authCode == .invalidResponse {
                return "We couldn’t verify Apple’s response. Please try again."
            } else if authCode == .notHandled {
                return "Sign in with Apple wasn’t completed. Please try again."
            } else if authCode == .notInteractive {
                return "Sign in with Apple needs the app in the foreground. Please bring Ledgex forward and try again."
            } else if #available(iOS 18.0, *), authCode == .matchedExcludedCredential {
                return "Sign in with Apple isn’t available for this Apple ID. You can sign in with email instead."
            } else if authCode == .unknown {
                return "Sign in with Apple hit an unexpected issue. Please try again."
            }
            
            return "Sign in with Apple hit an unexpected issue. Please try again."
        }

        if nsError.domain == AuthErrorDomain,
           let authCode = AuthErrorCode(rawValue: nsError.code) {
            switch authCode {
            case .accountExistsWithDifferentCredential:
                return "An account already exists with a different sign-in method. Try email instead."
            case .credentialAlreadyInUse:
                return "This Apple ID is already linked to a Ledgex account. Try signing in instead."
            case .networkError, .webNetworkRequestFailed:
                return "We couldn’t reach Apple’s servers. Check your connection and try again."
            case .tooManyRequests:
                return "Apple temporarily rate-limited sign-ins. Please wait a moment and try again."
            case .appNotAuthorized:
                return "This build isn’t authorized for Sign in with Apple. Please use the App Store version."
            case .invalidCredential, .invalidUserToken, .sessionExpired:
                return "Apple couldn’t verify the sign-in request. Please try again."
            case .internalError, .webInternalError:
                return "Apple’s sign-in service hit an unexpected issue. Please try again."
            case .userDisabled:
                return "This account has been disabled. Contact Ledgex support if you believe this is a mistake."
            case .webContextAlreadyPresented, .webContextCancelled:
                return nil
            default:
                return "Sign in with Apple hit an unexpected issue. Please try again."
            }
        }

        return nil
    }

    @MainActor
    private func startGoogleSignInFlow() async {
        guard !isProcessing else { return }

        detailedErrorLog = []
        errorMessage = nil
        authStartTime = Date()
        logError(stage: .initialization, message: "Google sign-in initiated at \(Date())")

        isProcessing = true

        do {
            let result = try await beginGoogleSignIn()
            let user = result.user
            logError(stage: .googleAuthorization, message: "Google sign-in succeeded")
            logError(stage: .credentialExtraction, message: "Google user ID: \(user.userID ?? "nil")")
            logError(stage: .credentialExtraction, message: "Google email: \(user.profile?.email ?? "nil")")

            guard let idToken = user.idToken?.tokenString else {
                logError(stage: .tokenExtraction, message: "❌ Missing Google ID token")
                throw NSError(domain: "LedgexAuth", code: -101, userInfo: [NSLocalizedDescriptionKey: "We couldn't fetch your Google ID token."])
            }

            let accessToken = user.accessToken.tokenString
            logError(stage: .tokenExtraction, message: "✅ Received Google ID token (\(idToken.count) chars)")
            logError(stage: .tokenExtraction, message: "✅ Received Google access token (\(accessToken.count) chars)")

            let credential = GoogleAuthProvider.credential(withIDToken: idToken, accessToken: accessToken)
            logError(stage: .firebaseCredential, message: "✅ Firebase credential created for google.com")

            let authResult = try await signInWithFirebase(credential: credential)
            logError(stage: .firebaseSignIn, message: "✅ Firebase sign-in completed for \(authResult.user.uid)")

            try await postAuthenticationSetup(with: authResult)
            let totalElapsed = authStartTime.map { String(format: "%.2f", Date().timeIntervalSince($0)) } ?? "?"
            logError(stage: .profileSetup, message: "✅ COMPLETE (Google) - Total time: \(totalElapsed)s")

            isProcessing = false
            errorMessage = nil
            currentFlow = .signInWithApple
        } catch {
            await handleGoogleSignInError(error)
        }
    }

    @MainActor
    private func beginGoogleSignIn() async throws -> GIDSignInResult {
        guard let clientID = FirebaseApp.app()?.options.clientID else {
            logError(stage: .googleAuthorization, message: "❌ Missing Firebase clientID for Google configuration")
            throw NSError(domain: "LedgexAuth", code: -100, userInfo: [NSLocalizedDescriptionKey: "Google Sign-In is not configured."])
        }

        let configuration = GIDConfiguration(clientID: clientID)
        GIDSignIn.sharedInstance.configuration = configuration
        logError(stage: .googleAuthorization, message: "Configured Google Sign-In with client ID \(clientID)")

        guard let presenter = resolvePresentingViewController() else {
            logError(stage: .googleAuthorization, message: "❌ Unable to locate presenting view controller for Google Sign-In")
            throw NSError(domain: "LedgexAuth", code: -103, userInfo: [NSLocalizedDescriptionKey: "Unable to start Google Sign-In from this screen."])
        }

        return try await withCheckedThrowingContinuation { continuation in
            let signIn = GIDSignIn.sharedInstance
            signIn.signOut()
            signIn.signIn(withPresenting: presenter) { result, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let result {
                    continuation.resume(returning: result)
                } else {
                    continuation.resume(throwing: NSError(domain: "LedgexAuth", code: -102, userInfo: [NSLocalizedDescriptionKey: "Google Sign-In returned no result."]))
                }
            }
        }
    }

    @MainActor
    private func handleGoogleSignInError(_ error: Error) async {
        isProcessing = false

        let nsError = error as NSError
        logError(stage: .googleAuthorization, message: "❌ Google Sign-In error: \(nsError.domain) (\(nsError.code)) - \(nsError.localizedDescription)")

        if nsError.domain == kGIDSignInErrorDomain {
            switch nsError.code {
            case -5: // User canceled
                logError(stage: .googleAuthorization, message: "User canceled Google Sign-In")
                errorMessage = nil
                return
            case -2, -4: // Keychain issues / no auth in keychain
                errorMessage = "Google Sign-In couldn't restore your session. Please try again."
                return
            default:
                errorMessage = "Google Sign-In hit an unexpected issue. Please try again."
                return
            }
        }

        if let userMessage = userFacingMessage(for: nsError) {
            errorMessage = userMessage
        } else {
            errorMessage = "Google Sign-In is unavailable right now. Please try again."
        }
    }

    @MainActor
    private func resolvePresentingViewController() -> UIViewController? {
        if let anchor = cachedPresentationAnchor,
           anchor.windowScene != nil,
           let root = anchor.rootViewController {
            return topViewController(from: root)
        }

        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let prioritizedStates: [UIScene.ActivationState] = [.foregroundActive, .foregroundInactive, .background, .unattached]

        for state in prioritizedStates {
            for scene in scenes where scene.activationState == state {
                if let root = scene.windows.first(where: { $0.isKeyWindow })?.rootViewController {
                    return topViewController(from: root)
                }
            }
        }

        for state in prioritizedStates {
            for scene in scenes where scene.activationState == state {
                if let root = scene.windows.first?.rootViewController {
                    return topViewController(from: root)
                }
            }
        }

        return nil
    }

    private func topViewController(from controller: UIViewController?) -> UIViewController? {
        if let navigation = controller as? UINavigationController {
            return topViewController(from: navigation.visibleViewController)
        }
        if let tab = controller as? UITabBarController, let selected = tab.selectedViewController {
            return topViewController(from: selected)
        }
        if let presented = controller?.presentedViewController {
            return topViewController(from: presented)
        }
        return controller
    }
    
    private func fetchSignInMethods(for email: String) async throws -> [String] {
        try await withCheckedThrowingContinuation { continuation in
            Auth.auth().fetchSignInMethods(forEmail: email) { methods, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: methods ?? [])
                }
            }
        }
    }

    private func providerRedirectMessage(from providers: [String]) -> String? {
        var options: [String] = []
        if providers.contains("apple.com") {
            options.append("Sign in with Apple")
        }
        if providers.contains("google.com") {
            options.append("Sign in with Google")
        }
        guard !options.isEmpty else { return nil }
        let message: String
        if options.count == 1 {
            message = options[0]
        } else {
            let firstOptions = options.dropLast().joined(separator: ", ")
            message = "\(firstOptions) or \(options.last!)"
        }
        return "This email is already linked to \(message). Please use that option instead."
    }

    private func randomNonceString(length: Int = 32) -> String {
        precondition(length > 0)
        let charset: [Character] = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var result = ""
        var remainingLength = length
        
        while remainingLength > 0 {
            var randoms = [UInt8](repeating: 0, count: 16)
            let status = SecRandomCopyBytes(kSecRandomDefault, randoms.count, &randoms)
            if status != errSecSuccess {
                fatalError("Unable to generate nonce. SecRandomCopyBytes failed with code \(status)")
            }
            randoms.forEach { random in
                if remainingLength == 0 { return }
                let index = Int(random) % charset.count
                result.append(charset[index])
                remainingLength -= 1
            }
        }
        
        return result
    }
    
    private func sha256(_ input: String) -> String {
        let inputData = Data(input.utf8)
        let hashed = SHA256.hash(data: inputData)
        return hashed.map { String(format: "%02x", $0) }.joined()
    }
}
