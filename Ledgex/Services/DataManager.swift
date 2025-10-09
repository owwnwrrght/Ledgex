import Foundation

// MARK: - Local Data Manager
class DataManager {
    static let shared = DataManager()
    private let userDefaults = UserDefaults.standard
    private let tripsKey = "SavedTrips"
    
    private init() {}
    
    func saveTrips(_ trips: [Trip]) {
        do {
            let encoder = JSONEncoder()
            let data = try encoder.encode(trips)
            userDefaults.set(data, forKey: tripsKey)
            print("Saved \(trips.count) trips to local storage")
        } catch {
            print("Failed to save trips: \(error)")
        }
    }
    
    func loadTrips() -> [Trip] {
        guard let data = userDefaults.data(forKey: tripsKey) else {
            return []
        }
        
        do {
            let decoder = JSONDecoder()
            let trips = try decoder.decode([Trip].self, from: data)
            print("Loaded \(trips.count) trips from local storage")
            return trips
        } catch {
            print("Failed to load trips: \(error)")
            return []
        }
    }
    
    func clearAllData() {
        userDefaults.removeObject(forKey: tripsKey)
        print("Cleared all local trip data")
    }
}