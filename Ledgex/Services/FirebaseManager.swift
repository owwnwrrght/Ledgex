import Foundation
import FirebaseCore
import FirebaseFirestore
import FirebaseAuth
import FirebaseStorage
import SwiftUI
import Combine

// Helper extension for async Firebase operations
extension StorageReference {
    func putDataAsync(_ uploadData: Data, metadata: StorageMetadata?) async throws -> StorageMetadata {
        return try await withCheckedThrowingContinuation { continuation in
            self.putData(uploadData, metadata: metadata) { metadata, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else if let metadata = metadata {
                    continuation.resume(returning: metadata)
                } else {
                    continuation.resume(throwing: NSError(domain: "StorageError", code: -1, userInfo: [NSLocalizedDescriptionKey: "Unknown error"]))
                }
            }
        }
    }
}

// MARK: - Firebase Implementation
class FirebaseManager: ObservableObject, TripDataStore {
    @MainActor static let shared = FirebaseManager()
    private let db = Firestore.firestore()
    private let auth = Auth.auth()
    private let storage = Storage.storage()
    
    @MainActor @Published var isFirebaseAvailable = false
    @MainActor @Published var syncStatus: SyncStatus = .idle
    
    // Firestore listeners
    private var listeners: [ListenerRegistration] = []
    
    enum SyncStatus {
        case idle
        case syncing
        case error(String)
        case success
    }
    
    // Track document references
    private var documentRefs: [String: DocumentReference] = [:]
    
    init() {
        // Initialize Firebase authentication and check availability
        Task { @MainActor in
            await checkFirebaseStatus()
            await setupListeners()
        }
    }
    
    @MainActor func checkFirebaseStatus() async {
        await updateAvailability(for: auth.currentUser)
    }

    @MainActor func updateAvailability(for user: User?) async {
        if let user {
            print("Firebase Status: Signed in as \(user.uid)")
            isFirebaseAvailable = true
            if !schemaInitialized {
                await initializeFirebaseSchema()
            }
        } else {
            print("Firebase Status: No authenticated user")
            isFirebaseAvailable = false
            schemaInitialized = false
        }
    }
    
    
    @MainActor private func setupListeners() async {
        // Firebase listeners will be set up when a trip is loaded
        print("Firebase listeners ready to be configured")
    }
    
    // MARK: - Basic Sync
    func fetchChanges() async throws {
        // Firebase real-time sync is handled by listeners
        print("Firebase sync - handled by real-time listeners")
    }
    
    // MARK: - Real-time Updates
    func setupTripListener(for tripCode: String, onUpdate: @escaping (Trip) -> Void) {
        // Remove existing listeners
        listeners.forEach { $0.remove() }
        listeners.removeAll()
        
        // Get trip ID first
        Task {
            guard let trip = try? await fetchTrip(by: tripCode) else { return }
            let tripID = trip.id
            
            // Listen to trip document changes (includes people and expenses)
            let tripListener = db.collection("trips")
                .document(tripID.uuidString)
                .addSnapshotListener { [weak self] snapshot, error in
                    if let error = error {
                        print("Error listening to trip changes: \(error)")
                        return
                    }
                    
                    guard let document = snapshot, document.exists else { return }
                    
                    Task { @MainActor in
                        if let self = self,
                           let data = document.data(),
                           let updatedTrip = try? self.tripFromDocumentData(data, id: document.documentID) {
                            
                            print("🔄 Group updated from Firebase:")
                            print("   People: \(updatedTrip.people.map { $0.name })")
                            print("   Expenses: \(updatedTrip.expenses.count)")
                            
                            onUpdate(updatedTrip)
                            self.syncStatus = .success
                        }
                    }
                }
            
            listeners.append(tripListener)
        }
    }
    
    // MARK: - Public API
    @MainActor func refreshData() async {
        do {
            try await fetchChanges()
            syncStatus = .success
        } catch {
            print("Failed to refresh data: \(error)")
            syncStatus = .error("Failed to refresh data")
        }
    }
    
    // MARK: - Async Operations (no manual rate limiting needed)
    
    // MARK: - Schema Initialization
    var schemaInitialized = false
    var schemaInitAttempts = 0
    
    @MainActor func initializeFirebaseSchema() async {
        schemaInitAttempts += 1
        print("Starting Firebase schema initialization (attempt \(schemaInitAttempts))...")
        
        // Firebase doesn't require explicit schema initialization
        // Collections are created automatically when documents are added
        schemaInitialized = true
        syncStatus = .success
        print("Firebase schema initialization completed!")
    }
    
    // MARK: - Trip Code Validation
    func generateUniqueTripCode() async -> String {
        let code = Trip.generateTripCode()
        
        // Check if code already exists
        do {
            let existingTrip = try await fetchTrip(by: code)
            if existingTrip != nil {
                // Code exists, generate a new one
                return await generateUniqueTripCode()
            }
        } catch {
            // Error checking, assume code is unique
        }
        
        return code
    }
    
    // MARK: - Trip Operations
    @MainActor func saveTrip(_ trip: Trip) async throws -> Trip {
        return try await saveTrip(trip, retryAttempt: 0)
    }
    
    @MainActor private func saveTrip(_ trip: Trip, retryAttempt: Int = 0) async throws -> Trip {
        guard isFirebaseAvailable else {
            return trip
        }
        
        syncStatus = .syncing
        
        // Create document data including people and expenses
        let peopleData = trip.people.map { person in
            [
                "id": person.id.uuidString,
                "name": person.name,
                "totalPaid": NSDecimalNumber(decimal: person.totalPaid).doubleValue,
                "totalOwed": NSDecimalNumber(decimal: person.totalOwed).doubleValue,
                "isManuallyAdded": person.isManuallyAdded,
                "hasCompletedExpenses": person.hasCompletedExpenses
            ]
        }
        
        let expensesData = trip.expenses.map { expense in
            var expenseDict: [String: Any] = [
                "id": expense.id.uuidString,
                "description": expense.description,
                "amount": NSDecimalNumber(decimal: expense.amount).doubleValue,
                "originalAmount": NSDecimalNumber(decimal: expense.originalAmount).doubleValue,
                "originalCurrency": expense.originalCurrency.rawValue,
                "baseCurrency": expense.baseCurrency.rawValue,
                "exchangeRate": NSDecimalNumber(decimal: expense.exchangeRate).doubleValue,
                "splitType": expense.splitType.rawValue,
                "date": Timestamp(date: expense.date),
                "paidByID": expense.paidBy.id.uuidString,
                "participantIDs": expense.participants.map { $0.id.uuidString },
                "receiptImageIds": expense.receiptImageIds // New field
            ]
            
            if !expense.customSplits.isEmpty {
                let customSplitsDict = expense.customSplits.mapKeys { $0.uuidString }.mapValues { NSDecimalNumber(decimal: $0).doubleValue }
                expenseDict["customSplits"] = customSplitsDict
            }

            if let creatorId = expense.createdByUserId?.uuidString {
                expenseDict["createdBy"] = creatorId
            }
            
            return expenseDict
        }
        
        let settlementReceiptData = trip.settlementReceipts.map { receipt -> [String: Any] in
            [
                "id": receipt.id.uuidString,
                "fromPersonId": receipt.fromPersonId.uuidString,
                "toPersonId": receipt.toPersonId.uuidString,
                "amount": NSDecimalNumber(decimal: receipt.amount).doubleValue,
                "isReceived": receipt.isReceived,
                "updatedAt": Timestamp(date: receipt.updatedAt)
            ]
        }

        let peopleIDs = trip.people.map { $0.id.uuidString }

        let tripData: [String: Any] = [
            "id": trip.id.uuidString,
            "name": trip.name,
            "code": trip.code,
            "baseCurrency": trip.baseCurrency.rawValue,
            "createdDate": Timestamp(date: trip.createdDate),
            "lastModified": Timestamp(date: Date()),
            "version": trip.version,
            "flagEmoji": trip.flagEmoji,
            "phase": trip.phase.rawValue,
            "people": peopleData,
            "peopleIDs": peopleIDs,
            "expenses": expensesData,
            "notificationsEnabled": trip.notificationsEnabled,
            "lastNotificationCheck": trip.lastNotificationCheck.map { Timestamp(date: $0) } as Any,
            "settlementReceipts": settlementReceiptData
        ]
        
        do {
            // Test basic connectivity first
            print("🔗 Testing Firebase connectivity...")
            let testRef = db.collection("test").document("connectivity")
            try await testRef.setData(["test": true])
            try await testRef.delete()
            print("✅ Firebase connectivity test passed")
            
            // Save to Firebase
            let docRef = db.collection("trips").document(trip.id.uuidString)
            print("📤 Attempting to save trip document to Firebase...")
            print("   Document ID: \(trip.id.uuidString)")
            print("   Group data keys: \(tripData.keys.sorted())")
            
            try await docRef.setData(tripData)
            print("✅ Successfully saved trip document to Firebase!")
            
            // Verify the document was actually saved
            let verifyDoc = try await docRef.getDocument()
            if verifyDoc.exists {
                print("✅ Document verified in Firebase")
            } else {
                print("⚠️ Document save succeeded but verification failed")
            }
            
            documentRefs[trip.id.uuidString] = docRef
            syncStatus = .success
            
            // Don't set up listener here - it will be set up by TripViewModel
            
            return trip
        } catch {
            print("❌ Failed to save trip to Firebase: \(error)")
            print("   Error type: \(type(of: error))")
            print("   Error details: \(error.localizedDescription)")
            
            // Check if it's a network error
            if let nsError = error as NSError? {
                print("   Error domain: \(nsError.domain)")
                print("   Error code: \(nsError.code)")
                print("   User info: \(nsError.userInfo)")
            }
            
            // Retry logic for temporary failures
            if retryAttempt < 2 {
                print("🔄 Retrying save... (attempt \(retryAttempt + 1))")
                try await Task.sleep(nanoseconds: 2_000_000_000) // 2 second delay
                return try await saveTrip(trip, retryAttempt: retryAttempt + 1)
            }
            
            syncStatus = .error("Failed to save trip")
            throw error
        }
    }

    @MainActor
    func removeUserData(for profile: UserProfile) async throws {
        let userId = profile.id
        let userIdString = userId.uuidString

        do {
            try await db.collection("users").document(userIdString).delete()
            print("🗑️ Deleted user document for \(userIdString)")
        } catch {
            print("⚠️ Failed to delete user document: \(error)")
        }

        var processedTripIDs: Set<UUID> = []

        do {
            let snapshot = try await db.collection("trips").whereField("peopleIDs", arrayContains: userIdString).getDocuments()
            for document in snapshot.documents {
                var trip = try tripFromDocument(document)
                let originalCount = trip.people.count
                trip.people.removeAll { $0.id == userId }
                guard trip.people.count != originalCount else { continue }

                for index in trip.expenses.indices {
                    trip.expenses[index].participants.removeAll { $0.id == userId }
                    trip.expenses[index].customSplits.removeValue(forKey: userId)
                }

                trip.settlementReceipts.removeAll { $0.fromPersonId == userId || $0.toPersonId == userId }
                _ = try await saveTrip(trip)
                print("🧹 Removed user \(userIdString) from trip \(trip.code)")
                processedTripIDs.insert(trip.id)
            }
        } catch {
            print("⚠️ Failed to remove user from trips: \(error)")
        }

        let localTrips = DataManager.shared.loadTrips().filter { trip in
            trip.people.contains(where: { $0.id == userId }) && !processedTripIDs.contains(trip.id)
        }
        for var trip in localTrips {
            let originalCount = trip.people.count
            trip.people.removeAll { $0.id == userId }
            guard trip.people.count != originalCount else { continue }

            for index in trip.expenses.indices {
                trip.expenses[index].participants.removeAll { $0.id == userId }
                trip.expenses[index].customSplits.removeValue(forKey: userId)
            }

            trip.settlementReceipts.removeAll { $0.fromPersonId == userId || $0.toPersonId == userId }
            _ = try await saveTrip(trip)
            print("🧹 (Local fallback) Removed user \(userIdString) from trip \(trip.code)")
        }
    }
    
    @MainActor func fetchTrip(by code: String) async throws -> Trip? {
        return try await fetchTrip(by: code, retryAttempt: 0)
    }
    
    @MainActor private func fetchTrip(by code: String, retryAttempt: Int = 0) async throws -> Trip? {
        guard isFirebaseAvailable else {
            return nil
        }
        
        do {
            // Convert to uppercase for case-insensitive matching
            let upperCode = code.uppercased()
            
            print("📥 Attempting to fetch trip with code: \(upperCode)")
            
            let querySnapshot = try await db.collection("trips")
                .whereField("code", isEqualTo: upperCode)
                .limit(to: 1)
                .getDocuments()
            
            if querySnapshot.documents.isEmpty {
                print("⚠️ No trip found with code: \(upperCode)")
                return nil
            }
            
            let document = querySnapshot.documents[0]
            let trip = try tripFromDocument(document)
            
            print("✅ Successfully fetched trip: \(trip.name)")
            print("   Group ID: \(trip.id)")
            print("   People count: \(trip.people.count)")
            print("   Expenses count: \(trip.expenses.count)")
            
            return trip
        } catch {
            print("❌ Failed to fetch trip: \(error)")
            
            // Retry logic for temporary failures
            if retryAttempt < 2 {
                print("🔄 Retrying fetch... (attempt \(retryAttempt + 1))")
                try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second delay
                return try await fetchTrip(by: code, retryAttempt: retryAttempt + 1)
            }
            
            throw error
        }
    }
    
    // MARK: - Batch Sync Operations
    @MainActor func syncTrip(_ trip: Trip) async throws -> Trip {
        guard isFirebaseAvailable else {
            return trip
        }
        
        syncStatus = .syncing
        
        do {
            // Simply fetch the latest version of the trip from Firebase
            if let remoteTrip = try await fetchTrip(by: trip.code) {
                syncStatus = .success
                return remoteTrip
            } else {
                // Trip not found in Firebase, return local version
                syncStatus = .success
                return trip
            }
        } catch {
            syncStatus = .error("Sync completed with errors")
            throw error
        }
    }
    
    // MARK: - Document Parsing
    private func tripFromDocument(_ document: QueryDocumentSnapshot) throws -> Trip {
        let data = document.data()
        return try tripFromDocumentData(data, id: document.documentID)
    }
    
    private func tripFromDocumentData(_ data: [String: Any], id: String) throws -> Trip {
        let id = UUID(uuidString: data["id"] as? String ?? "") ?? UUID()
        let name = data["name"] as? String ?? "Unknown Group"
        let code = data["code"] as? String ?? "UNKNOWN"
        let version = data["version"] as? Int ?? 1
        let baseCurrencyRaw = data["baseCurrency"] as? String ?? "USD"
        let baseCurrency = Currency(rawValue: baseCurrencyRaw) ?? .USD
        let notificationsEnabled = data["notificationsEnabled"] as? Bool ?? true
        let flagEmoji = data["flagEmoji"] as? String ?? Trip.defaultFlag
        let phaseRaw = data["phase"] as? String ?? "setup"
        let phase = TripPhase(rawValue: phaseRaw) ?? .setup

        let createdTimestamp = data["createdDate"] as? Timestamp ?? Timestamp()
        let lastModifiedTimestamp = data["lastModified"] as? Timestamp ?? Timestamp()
        let lastNotificationTimestamp = data["lastNotificationCheck"] as? Timestamp
        
        // Parse people
        var people: [Person] = []
        if let peopleData = data["people"] as? [[String: Any]] {
            people = peopleData.compactMap { personDict in
                guard let idString = personDict["id"] as? String,
                      let personId = UUID(uuidString: idString),
                      let name = personDict["name"] as? String else { return nil }
                
                var person = Person(name: name)
                person.id = personId
                person.totalPaid = Decimal(personDict["totalPaid"] as? Double ?? 0)
                person.totalOwed = Decimal(personDict["totalOwed"] as? Double ?? 0)
                person.isManuallyAdded = personDict["isManuallyAdded"] as? Bool ?? false
                person.hasCompletedExpenses = personDict["hasCompletedExpenses"] as? Bool ?? false
                return person
            }
        }
        
        // Parse expenses
        var expenses: [Expense] = []
        if let expensesData = data["expenses"] as? [[String: Any]] {
            expenses = expensesData.compactMap { expenseDict in
                guard let expenseId = UUID(uuidString: expenseDict["id"] as? String ?? ""),
                      let description = expenseDict["description"] as? String,
                      let amount = expenseDict["amount"] as? Double,
                      let originalAmount = expenseDict["originalAmount"] as? Double,
                      let originalCurrencyRaw = expenseDict["originalCurrency"] as? String,
                      let originalCurrency = Currency(rawValue: originalCurrencyRaw),
                      let exchangeRate = expenseDict["exchangeRate"] as? Double,
                      let splitTypeRaw = expenseDict["splitType"] as? String,
                      let splitType = SplitType(rawValue: splitTypeRaw),
                      let paidByID = expenseDict["paidByID"] as? String,
                      let paidByUUID = UUID(uuidString: paidByID),
                      let paidBy = people.first(where: { $0.id == paidByUUID }),
                      let participantIDs = expenseDict["participantIDs"] as? [String],
                      let dateTimestamp = expenseDict["date"] as? Timestamp else { return nil }
                
                var expense = Expense(
                    description: description,
                    originalAmount: Decimal(originalAmount),
                    originalCurrency: originalCurrency,
                    baseCurrency: baseCurrency,
                    exchangeRate: Decimal(exchangeRate),
                    paidBy: paidBy,
                    participants: []
                )
                
                expense.id = expenseId
                expense.amount = Decimal(amount)
                expense.splitType = splitType
                expense.date = dateTimestamp.dateValue()
                expense.receiptImageIds = expenseDict["receiptImageIds"] as? [String] ?? []
                if let creator = expenseDict["createdBy"] as? String, let creatorUUID = UUID(uuidString: creator) {
                    expense.createdByUserId = creatorUUID
                }
                
                // Map participant IDs to Person objects
                expense.participants = participantIDs.compactMap { idString in
                    guard let uuid = UUID(uuidString: idString) else { return nil }
                    return people.first(where: { $0.id == uuid })
                }
                
                // Parse custom splits
                if let customSplitsDict = expenseDict["customSplits"] as? [String: Double] {
                    expense.customSplits = customSplitsDict.reduce(into: [:]) { result, pair in
                        if let uuid = UUID(uuidString: pair.key) {
                            result[uuid] = Decimal(pair.value)
                        }
                    }
                }
                
                return expense
            }
        }
        
        var settlementReceipts: [SettlementReceipt] = []
        if let receiptsData = data["settlementReceipts"] as? [[String: Any]] {
            settlementReceipts = receiptsData.compactMap { receiptDict in
                guard let fromString = receiptDict["fromPersonId"] as? String,
                      let toString = receiptDict["toPersonId"] as? String,
                      let amount = receiptDict["amount"] as? Double,
                      let fromId = UUID(uuidString: fromString),
                      let toId = UUID(uuidString: toString) else { return nil }

                let id = UUID(uuidString: receiptDict["id"] as? String ?? "") ?? UUID()
                let isReceived = receiptDict["isReceived"] as? Bool ?? false
                let updatedTimestamp = receiptDict["updatedAt"] as? Timestamp
                let updatedAt = updatedTimestamp?.dateValue() ?? Date()

                return SettlementReceipt(id: id,
                                          fromPersonId: fromId,
                                          toPersonId: toId,
                                          amount: Decimal(amount),
                                          isReceived: isReceived,
                                          updatedAt: updatedAt)
            }
        }

        var trip = Trip(id: id,
                        name: name,
                        code: code,
                        people: people,
                        expenses: expenses,
                        createdDate: createdTimestamp.dateValue(),
                        lastModified: lastModifiedTimestamp.dateValue(),
                        baseCurrency: baseCurrency,
                        version: version,
                        flagEmoji: flagEmoji,
                        phase: phase,
                        notificationsEnabled: notificationsEnabled,
                        lastNotificationCheck: lastNotificationTimestamp?.dateValue(),
                        settlementReceipts: settlementReceipts)

        return trip
    }
    
    // MARK: - Receipt Image Management
    @MainActor func uploadReceiptImage(_ imageData: Data, for expenseId: String) async throws -> String {
        guard isFirebaseAvailable else {
            throw NSError(domain: "FirebaseManager", code: 1, userInfo: [NSLocalizedDescriptionKey: "Firebase not available"])
        }
        
        let imageId = UUID().uuidString
        let imagePath = "receipts/\(expenseId)/\(imageId).jpg"
        let storageRef = storage.reference().child(imagePath)
        
        let metadata = StorageMetadata()
        metadata.contentType = "image/jpeg"
        
        do {
            print("📤 Uploading receipt image to path: \(imagePath)")
            let uploadResult = try await storageRef.putDataAsync(imageData, metadata: metadata)
            print("✅ Upload successful, size: \(uploadResult.size) bytes")
            
            let downloadURL = try await storageRef.downloadURL()
            print("🔗 Download URL generated: \(downloadURL.absoluteString)")
            return downloadURL.absoluteString
        } catch {
            print("❌ Failed to upload receipt image: \(error)")
            throw error
        }
    }
    
    @MainActor func downloadReceiptImage(_ imageUrl: String) async throws -> Data? {
        guard isFirebaseAvailable else {
            print("⚠️ Firebase not available for image download")
            return nil
        }
        
        guard let url = URL(string: imageUrl) else {
            print("❌ Invalid image URL: \(imageUrl)")
            return nil
        }
        
        do {
            print("📥 Downloading receipt image from: \(imageUrl)")
            let (data, response) = try await URLSession.shared.data(from: url)
            
            if let httpResponse = response as? HTTPURLResponse {
                print("📊 Download response: \(httpResponse.statusCode), size: \(data.count) bytes")
                guard httpResponse.statusCode == 200 else {
                    throw NSError(domain: "NetworkError", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "HTTP \(httpResponse.statusCode)"])
                }
            }
            
            return data
        } catch {
            print("❌ Failed to download receipt image: \(error)")
            throw error
        }
    }
    
    @MainActor func deleteReceiptImage(_ imageUrl: String) async throws {
        guard isFirebaseAvailable else {
            print("⚠️ Firebase not available for image deletion")
            return
        }
        
        do {
            // Extract path from Firebase Storage URL
            if let url = URL(string: imageUrl),
               let pathComponent = url.path.components(separatedBy: "/o/").last {
                let decodedPath = pathComponent.removingPercentEncoding ?? pathComponent
                let cleanPath = decodedPath.components(separatedBy: "?").first ?? decodedPath
                
                print("🗑️ Deleting receipt image at path: \(cleanPath)")
                let storageRef = storage.reference().child(cleanPath)
                try await storageRef.delete()
                print("✅ Receipt image deleted successfully")
            } else {
                print("❌ Could not extract path from URL: \(imageUrl)")
                throw NSError(domain: "FirebaseManager", code: 2, userInfo: [NSLocalizedDescriptionKey: "Invalid storage URL"])
            }
        } catch {
            print("❌ Failed to delete receipt image: \(error)")
            throw error
        }
    }
    
    // MARK: - Batch Receipt Operations
    @MainActor func uploadReceiptImages(_ images: [UIImage], for expenseId: String) async throws -> [String] {
        guard isFirebaseAvailable else {
            throw NSError(domain: "FirebaseManager", code: 1, userInfo: [NSLocalizedDescriptionKey: "Firebase not available"])
        }
        
        print("📤 Starting batch upload of \(images.count) images for expense \(expenseId)")
        var uploadedUrls: [String] = []
        
        for (index, image) in images.enumerated() {
            guard let imageData = image.jpegData(compressionQuality: 0.8) else {
                print("⚠️ Could not convert image \(index) to JPEG data")
                continue
            }
            
            do {
                let url = try await uploadReceiptImage(imageData, for: expenseId)
                uploadedUrls.append(url)
                print("✅ Uploaded image \(index + 1)/\(images.count)")
            } catch {
                print("❌ Failed to upload image \(index + 1): \(error)")
                // Continue with other images rather than failing completely
            }
        }
        
        print("🎉 Batch upload complete: \(uploadedUrls.count)/\(images.count) images uploaded")
        return uploadedUrls
    }
    
    // MARK: - User Profile Management
    @MainActor func saveUserProfile(_ profile: UserProfile) async throws {
        guard isFirebaseAvailable, let firebaseUID = auth.currentUser?.uid else {
            print("⚠️ Cannot save user profile - Firebase not available or no auth user")
            return
        }

        var updatedProfile = profile
        updatedProfile.firebaseUID = firebaseUID
        updatedProfile.lastSynced = Date()

        let profileData: [String: Any] = [
            "id": profile.id.uuidString,
            "firebaseUID": firebaseUID,
            "name": profile.name,
            "dateCreated": Timestamp(date: profile.dateCreated),
            "preferredCurrency": profile.preferredCurrency.rawValue,
            "tripCodes": profile.tripCodes,
            "lastSynced": Timestamp(date: Date()),
            "pushToken": profile.pushToken as Any,
            "notificationsEnabled": profile.notificationsEnabled
        ]

        do {
            let docRef = db.collection("users").document(firebaseUID)
            try await docRef.setData(profileData, merge: true)
            print("✅ User profile saved to Firestore")

            // Update local profile with Firebase UID
            await ProfileManager.shared.updateProfileWithFirebaseUID(firebaseUID)
        } catch {
            print("❌ Failed to save user profile: \(error)")
            throw error
        }
    }

    @MainActor func fetchUserProfile() async throws -> UserProfile? {
        guard isFirebaseAvailable, let firebaseUID = auth.currentUser?.uid else {
            print("⚠️ Cannot fetch user profile - Firebase not available or no auth user")
            return nil
        }

        do {
            let docRef = db.collection("users").document(firebaseUID)
            let document = try await docRef.getDocument()

            guard document.exists, let data = document.data() else {
                print("⚠️ No user profile found in Firestore")
                return nil
            }

            let id = UUID(uuidString: data["id"] as? String ?? "") ?? UUID()
            let name = data["name"] as? String ?? "Ledgex Member"
            let dateCreated = (data["dateCreated"] as? Timestamp)?.dateValue() ?? Date()
            let currencyRaw = data["preferredCurrency"] as? String ?? "USD"
            let preferredCurrency = Currency(rawValue: currencyRaw) ?? .USD
            let tripCodes = data["tripCodes"] as? [String] ?? []
            let lastSynced = (data["lastSynced"] as? Timestamp)?.dateValue()
            let pushToken = data["pushToken"] as? String
            let notificationsEnabled = data["notificationsEnabled"] as? Bool ?? true

            var profile = UserProfile(name: name, firebaseUID: firebaseUID)
            profile.id = id
            profile.dateCreated = dateCreated
            profile.preferredCurrency = preferredCurrency
            profile.tripCodes = tripCodes
            profile.lastSynced = lastSynced
            profile.pushToken = pushToken
            profile.notificationsEnabled = notificationsEnabled

            print("✅ User profile fetched from Firestore")
            return profile
        } catch {
            print("❌ Failed to fetch user profile: \(error)")
            throw error
        }
    }

    @MainActor func fetchUserTrips() async throws -> [Trip] {
        guard isFirebaseAvailable, let firebaseUID = auth.currentUser?.uid else {
            print("⚠️ Cannot fetch user trips - Firebase not available or no auth user")
            return []
        }

        do {
            // First, get the user's profile to get their trip codes
            let userDoc = try await db.collection("users").document(firebaseUID).getDocument()
            guard let userData = userDoc.data(),
                  let tripCodes = userData["tripCodes"] as? [String], !tripCodes.isEmpty else {
                print("ℹ️ User has no trips")
                return []
            }

            // Fetch all trips the user is part of
            var trips: [Trip] = []
            for code in tripCodes {
                if let trip = try await fetchTrip(by: code) {
                    trips.append(trip)
                }
            }

            print("✅ Fetched \(trips.count) trips for user")
            return trips
        } catch {
            print("❌ Failed to fetch user trips: \(error)")
            throw error
        }
    }

    @MainActor func addTripToUserProfile(tripCode: String) async throws {
        guard isFirebaseAvailable else {
            print("⚠️ [LinkTrip] Cannot add trip - Firebase not available")
            return
        }

        guard let firebaseUID = auth.currentUser?.uid else {
            print("⚠️ [LinkTrip] Cannot add trip - No authenticated user")
            return
        }

        print("🔗 [LinkTrip] Linking trip \(tripCode) to user \(firebaseUID)")

        do {
            let docRef = db.collection("users").document(firebaseUID)

            // First check if the document exists
            let doc = try await docRef.getDocument()
            if !doc.exists {
                print("⚠️ [LinkTrip] User document doesn't exist, creating it first...")
                // Create the document if it doesn't exist
                if let profile = await ProfileManager.shared.currentProfile {
                    try await saveUserProfile(profile)
                    print("✅ [LinkTrip] Created user document")
                } else {
                    print("❌ [LinkTrip] Cannot create user document - no profile")
                    throw NSError(domain: "FirebaseManager", code: 1, userInfo: [NSLocalizedDescriptionKey: "No user profile available"])
                }
            }

            // Now add the trip code
            try await docRef.updateData([
                "tripCodes": FieldValue.arrayUnion([tripCode]),
                "lastSynced": Timestamp(date: Date())
            ])
            print("✅ [LinkTrip] Added trip \(tripCode) to user profile in Firestore")

            // Update local profile
            if var profile = await ProfileManager.shared.currentProfile {
                if !profile.tripCodes.contains(tripCode) {
                    profile.tripCodes.append(tripCode)
                    profile.lastSynced = Date()
                    await ProfileManager.shared.updateProfile(profile: profile)
                    print("✅ [LinkTrip] Updated local profile with trip code")
                } else {
                    print("ℹ️ [LinkTrip] Trip code already exists in local profile")
                }
            } else {
                print("⚠️ [LinkTrip] No local profile to update")
            }
        } catch {
            print("❌ [LinkTrip] Failed to add trip to user profile: \(error)")
            if let nsError = error as NSError? {
                print("   Error domain: \(nsError.domain)")
                print("   Error code: \(nsError.code)")
            }
            throw error
        }
    }

    @MainActor func removeTripFromUserProfile(tripCode: String) async throws {
        guard isFirebaseAvailable, let firebaseUID = auth.currentUser?.uid else {
            print("⚠️ Cannot remove trip from user profile - Firebase not available or no auth user")
            return
        }

        do {
            let docRef = db.collection("users").document(firebaseUID)
            try await docRef.updateData([
                "tripCodes": FieldValue.arrayRemove([tripCode]),
                "lastSynced": Timestamp(date: Date())
            ])
            print("✅ Removed trip \(tripCode) from user profile")

            // Update local profile
            if var profile = await ProfileManager.shared.currentProfile {
                profile.tripCodes.removeAll { $0 == tripCode }
                profile.lastSynced = Date()
                await ProfileManager.shared.updateProfile(profile: profile)
            }
        } catch {
            print("❌ Failed to remove trip from user profile: \(error)")
            throw error
        }
    }

    // MARK: - State Management
    @MainActor func clearLocalState() async {
        print("🧹 Clearing Firebase manager state...")

        // Remove all listeners
        listeners.forEach { $0.remove() }
        listeners.removeAll()
        print("  ✓ Removed \(listeners.count) active listeners")

        // Clear document references
        documentRefs.removeAll()
        print("  ✓ Cleared document references")

        // Reset sync status
        syncStatus = .idle
        print("  ✓ Reset sync status")

        // Reset availability flag
        isFirebaseAvailable = false
        schemaInitialized = false
        print("  ✓ Reset Firebase availability")

        print("✅ Firebase manager state cleared")
    }

    // MARK: - User Friendly Error Messages
    static func userFriendlyError(_ error: Error) -> String {
        if let nsError = error as NSError? {
            switch nsError.code {
            case -1009, -1001:
                return "No internet connection. Please check your network and try again."
            case 403:
                return "Access denied. Please try again later."
            case 404:
                return "Group not found. Please check the code and try again."
            default:
                if nsError.domain == NSURLErrorDomain {
                    return "No internet connection. Please check your network and try again."
                }
            }
        }
        return "An error occurred. Please try again."
    }
}

// MARK: - Extensions
extension Dictionary {
    func mapKeys<NewKey: Hashable>(_ transform: (Key) -> NewKey) -> [NewKey: Value] {
        var newDict = [NewKey: Value]()
        for (key, value) in self {
            newDict[transform(key)] = value
        }
        return newDict
    }
}
