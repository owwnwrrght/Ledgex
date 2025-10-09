import Foundation
import UIKit

// MARK: - Mock Data Store for Testing
class MockTripDataStore: TripDataStore {
    private var trips: [String: Trip] = [:]
    
    func saveTrip(_ trip: Trip) async throws -> Trip {
        trips[trip.code] = trip
        return trip
    }
    
    func fetchTrip(by code: String) async throws -> Trip? {
        return trips[code.uppercased()]
    }
    
    func syncTrip(_ trip: Trip) async throws -> Trip {
        return trip
    }
    
    func generateUniqueTripCode() async -> String {
        return "MOCK" + String(Int.random(in: 100000...999999))
    }

    func deleteTrip(_ trip: Trip) async throws {
        trips.removeValue(forKey: trip.code)
    }

    func leaveTrip(_ trip: Trip, profile: UserProfile) async throws {
        guard var storedTrip = trips[trip.code] else {
            return
        }

        storedTrip.people.removeAll { $0.id == profile.id }

        for index in storedTrip.expenses.indices {
            storedTrip.expenses[index].participants.removeAll { $0.id == profile.id }
            storedTrip.expenses[index].customSplits.removeValue(forKey: profile.id)
        }

        storedTrip.settlementReceipts.removeAll { $0.fromPersonId == profile.id || $0.toPersonId == profile.id }
        storedTrip.lastModified = Date()

        if storedTrip.people.isEmpty {
            trips.removeValue(forKey: trip.code)
        } else {
            trips[trip.code] = storedTrip
        }
    }
    
    func uploadReceiptImage(_ imageData: Data, for expenseId: String) async throws -> String {
        // Mock implementation - return a fake URL
        return "mock://receipt/\(expenseId)/\(UUID().uuidString)"
    }
    
    func uploadReceiptImages(_ images: [UIImage], for expenseId: String) async throws -> [String] {
        // Mock implementation - return fake URLs for each image
        return images.map { _ in "mock://receipt/\(expenseId)/\(UUID().uuidString)" }
    }
    
    func downloadReceiptImage(_ imageUrl: String) async throws -> Data? {
        // Mock implementation - return nil (no image data)
        return nil
    }
    
    func deleteReceiptImage(_ imageUrl: String) async throws {
        // Mock implementation - do nothing
    }
}
