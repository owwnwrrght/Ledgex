import SwiftUI
import UIKit

struct JoinTripView: View {
    @ObservedObject var viewModel: TripListViewModel
    @State private var tripCode = ""
    @State private var showingError = false
    @State private var errorMessage = ""
    @State private var isJoining = false
    @State private var clipboardSuggestion: String?
    @State private var recentCodes: [String] = []
    @FocusState private var codeFieldFocused: Bool

    private let codeLength = Trip.codeLength
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Group Code")) {
                    TextField("Enter \(codeLength)-character code", text: $tripCode)
                        .focused($codeFieldFocused)
                        .textInputAutocapitalization(.characters)
                        .disableAutocorrection(true)
                        .keyboardType(.asciiCapable)
                        .submitLabel(.go)
                        .onSubmit(of: .text) {
                            joinIfPossible()
                        }
                        .onChange(of: tripCode) { newValue in
                            sanitizeInput(newValue)
                        }
                    
                    if tripCode.count < codeLength {
                        Text("Codes are \(codeLength) letters/numbers. You'll get one from the group organizer.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .textCase(nil)
                
                if let suggestion = clipboardSuggestion {
                    Section("Paste From Clipboard") {
                        Button {
                            tripCode = suggestion
                            clipboardSuggestion = nil
                            joinIfPossible()
                        } label: {
                            Label("Use \(suggestion)", systemImage: "doc.on.clipboard")
                        }
                    }
                }
                
                if !recentCodes.isEmpty {
                    Section("Recently Joined") {
                        ForEach(recentCodes, id: \.self) { code in
                            Button(code) {
                                tripCode = code
                                joinIfPossible()
                            }
                        }
                        Button("Clear Recents") {
                            JoinCodeHistory.shared.clear()
                            recentCodes = []
                        }
                        .foregroundColor(.red)
                        .font(.caption)
                    }
                }
                
                Section {
                    Text("Ask the group organizer for the group code to join their group.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                if showingError, !errorMessage.isEmpty {
                    Section {
                        Label(errorMessage, systemImage: "exclamationmark.triangle")
                            .foregroundColor(.red)
                            .font(.footnote)
                    }
                }
            }
            .navigationTitle("Join Group")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        viewModel.showingJoinTrip = false
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button(action: joinIfPossible) {
                        if isJoining {
                            HStack(spacing: 8) {
                                ProgressView()
                                    .scaleEffect(0.7)
                                Text("Joining…")
                            }
                        } else {
                            Text("Join")
                        }
                    }
                    .disabled(joinButtonDisabled)
                }
            }
            .overlay(alignment: .bottom) {
                if isJoining {
                    HStack(spacing: 8) {
                        ProgressView()
                        Text("Joining group…")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }
                    .padding(12)
                    .background(.thinMaterial)
                    .clipShape(Capsule())
                    .padding(.bottom, 24)
                }
            }
            .alert("Error", isPresented: $showingError) {
                Button("OK") { }
            } message: {
                Text(errorMessage)
            }
        }
        .onAppear(perform: prepareView)
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            updateClipboardSuggestion()
        }
    }
    
    private var joinButtonDisabled: Bool {
        tripCode.count != codeLength || isJoining
    }
    
    private func joinIfPossible() {
        guard !joinButtonDisabled else { return }
        joinTrip()
    }
    
    private func joinTrip() {
        Task {
            await MainActor.run {
                isJoining = true
                showingError = false
            }
            let (success, error) = await viewModel.joinTrip(with: tripCode)
            await MainActor.run {
                isJoining = false
                if success {
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    viewModel.showingJoinTrip = false
                } else {
                    errorMessage = error ?? "Group not found. Please check the code and try again."
                    showingError = true
                    UINotificationFeedbackGenerator().notificationOccurred(.error)
                }
            }
        }
    }
    
    private func sanitizeInput(_ newValue: String) {
        let allowed = CharacterSet.alphanumerics
        let filteredScalars = newValue.uppercased().unicodeScalars.filter { allowed.contains($0) }
        var sanitized = String(String.UnicodeScalarView(filteredScalars))
        if sanitized.count > codeLength {
            sanitized = String(sanitized.prefix(codeLength))
        }
        if sanitized != tripCode {
            tripCode = sanitized
        }
    }
    
    private func prepareView() {
        codeFieldFocused = true
        updateClipboardSuggestion()
        recentCodes = JoinCodeHistory.shared.recentCodes()
    }
    
    private func updateClipboardSuggestion() {
        guard let clipboardValue = UIPasteboard.general.string else {
            clipboardSuggestion = nil
            return
        }
        
        let allowed = CharacterSet.alphanumerics
        let filteredScalars = clipboardValue.uppercased().unicodeScalars.filter { allowed.contains($0) }
        let suggestion = String(String.UnicodeScalarView(filteredScalars))
        if suggestion.count == codeLength {
            clipboardSuggestion = suggestion
        } else {
            clipboardSuggestion = nil
        }
    }
}
