import Foundation
import UIKit

// MARK: - Data Store Protocol
protocol TripDataStore {
    func saveTrip(_ trip: Trip) async throws -> Trip
    func fetchTrip(by code: String) async throws -> Trip?
    func syncTrip(_ trip: Trip) async throws -> Trip
    func generateUniqueTripCode() async -> String
    func deleteTrip(_ trip: Trip) async throws
    func leaveTrip(_ trip: Trip, profile: UserProfile) async throws
    
    // New: Receipt image management
    func uploadReceiptImage(_ imageData: Data, for expenseId: String) async throws -> String
    func uploadReceiptImages(_ images: [UIImage], for expenseId: String) async throws -> [String]
    func downloadReceiptImage(_ imageUrl: String) async throws -> Data?
    func deleteReceiptImage(_ imageUrl: String) async throws
}
