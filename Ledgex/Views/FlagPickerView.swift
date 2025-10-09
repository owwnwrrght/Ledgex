import SwiftUI

struct FlagPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var customFlag: String = ""
    @State private var searchText: String = ""
    private let currentSelection: String
    private let onSelect: (String) -> Void
    
    private let popularFlags: [FlagOption]
    private let allFlags: [FlagOption]
    
    init(currentSelection: String, onSelect: @escaping (String) -> Void) {
        self.currentSelection = currentSelection
        self.onSelect = onSelect
        self.allFlags = FlagOption.all
        self.popularFlags = FlagOption.popular
    }
    
    var body: some View {
        NavigationView {
            List {
                if !popularFlags.isEmpty {
                    Section("Popular") {
                        flagGrid(for: popularFlags)
                    }
                }
                
                Section("All Flags") {
                    flagGrid(for: filteredFlags)
                }
                
                Section("Custom") {
                    VStack(alignment: .leading, spacing: 8) {
                        TextField("Paste emoji", text: $customFlag)
                            .textInputAutocapitalization(.never)
                            .disableAutocorrection(true)
                        Button("Use Custom Emoji") {
                            let trimmed = customFlag.trimmingCharacters(in: .whitespacesAndNewlines)
                            guard !trimmed.isEmpty else { return }
                            select(trimmed)
                        }
                        .disabled(customFlag.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Choose Icon")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search countries or emojis")
    }
    
    private var filteredFlags: [FlagOption] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return allFlags }
        return allFlags.filter { $0.matches(query: query) }
    }
    
    private func flagGrid(for flags: [FlagOption]) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 12) {
            ForEach(flags) { option in
                Button {
                    select(option.emoji)
                } label: {
                    VStack(spacing: 4) {
                        Text(option.emoji)
                            .font(.system(size: 32))
                        Text(option.name)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(8)
                    .background(option.emoji == currentSelection ? Color.blue.opacity(0.15) : Color.clear)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 4)
    }
    
    private func select(_ flag: String) {
        onSelect(flag)
        dismiss()
    }
}

private struct FlagOption: Identifiable {
    let code: String
    let emoji: String
    let name: String
    var id: String { code + emoji }
    
    static var all: [FlagOption] {
        (customSymbols + regionCodes.compactMap { code in
            guard let emoji = code.flagEmoji else { return nil }
            let localizedName = Locale.current.localizedString(forRegionCode: code) ?? code
            return FlagOption(code: code, emoji: emoji, name: localizedName)
        })
        .sorted { $0.name < $1.name }
    }

    private static var regionCodes: [String] {
        if #available(iOS 16.0, *) {
            return Locale.Region.isoRegions.map { $0.identifier }
        } else {
            return Locale.isoRegionCodes
        }
    }

    private static var customSymbols: [FlagOption] {
        let options: [(code: String, emoji: String, name: String)] = [
            ("ADVENTURE", "⛰️", "Adventure"),
            ("BEACH", "🏖️", "Beach"),
            ("ROADTRIP", "🚗", "Road Trip"),
            ("CELEBRATE", "🥳", "Celebration"),
            ("FOODIE", "🍽️", "Foodie"),
            ("NIGHTOUT", "🍹", "Night Out"),
            ("CAMPING", "🏕️", "Camping"),
            ("SKI", "🎿", "Ski Trip"),
            ("CRUISE", "🛳️", "Cruise"),
            ("FAMILY", "👨‍👩‍👧", "Family Trip"),
            ("MUSIC", "🎵", "Music Trip"),
            ("SPORTS", "🏟️", "Sports Trip")
        ]
        return options.map { FlagOption(code: $0.code, emoji: $0.emoji, name: $0.name) }
    }
    
    static var popular: [FlagOption] {
        let popularCodes = ["TRAVEL", "WORLD", "ADVENTURE", "BEACH", "ROADTRIP", "US", "CA", "GB", "FR", "IT", "JP", "AU", "NZ"]
        return popularCodes.compactMap { code in
            switch code {
            case "TRAVEL":
                return FlagOption(code: code, emoji: "✈️", name: "Travel")
            case "WORLD":
                return FlagOption(code: code, emoji: "🌍", name: "Global")
            case "ADVENTURE":
                return FlagOption(code: code, emoji: "⛰️", name: "Adventure")
            case "BEACH":
                return FlagOption(code: code, emoji: "🏖️", name: "Beach")
            case "ROADTRIP":
                return FlagOption(code: code, emoji: "🚗", name: "Road Trip")
            default:
                guard let emoji = code.flagEmoji else { return nil }
                let name = Locale.current.localizedString(forRegionCode: code) ?? code
                return FlagOption(code: code, emoji: emoji, name: name)
            }
        }
    }
    
    func matches(query: String) -> Bool {
        let lower = query.lowercased()
        return name.lowercased().contains(lower) || emoji.contains(query)
    }
}

private extension String {
    var flagEmoji: String? {
        guard self.count == 2 else { return nil }
        let base: UInt32 = 127397
        var scalars = String.UnicodeScalarView()
        for scalar in self.uppercased().unicodeScalars {
            guard let flagScalar = UnicodeScalar(base + scalar.value) else { return nil }
            scalars.append(flagScalar)
        }
        return String(scalars)
    }
}
