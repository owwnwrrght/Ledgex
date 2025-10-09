import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var authViewModel: AuthViewModel
    @StateObject private var tripListViewModel = TripListViewModel()
    @StateObject private var profileManager = ProfileManager.shared
    @StateObject private var notificationService = NotificationService.shared
    @State private var showingProfile = false
    @State private var pendingJoinCode: String?
    @State private var isProcessingIncomingLink = false
    @State private var isShowingLinkAlert = false
    @State private var linkAlertMessage: String?
    
    var body: some View {
        Group {
            if authViewModel.isSignedIn {
                if profileManager.currentProfile != nil {
                    NavigationView {
                        TripListView(viewModel: tripListViewModel)
                            .toolbar {
                                ToolbarItem(placement: .navigationBarLeading) {
                                    Button(action: { showingProfile = true }) {
                                        Image(systemName: "person.circle.fill")
                                    }
                                }
                            }
                    }
                    .sheet(isPresented: $showingProfile) {
                        ProfileView()
                    }
                } else {
                    ProfileSetupView()
                }
            } else {
                SignInView()
            }
        }
        .task(id: authViewModel.isSignedIn) {
            guard authViewModel.isSignedIn else { return }
            await notificationService.requestPermissions()
        }
        .overlay(alignment: .top) {
            if isProcessingIncomingLink {
                progressBanner
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .alert("Group Invite", isPresented: $isShowingLinkAlert, presenting: linkAlertMessage) { _ in
            Button("OK", role: .cancel) { }
        } message: { message in
            Text(message)
        }
        .onOpenURL(perform: handleIncomingURL)
        .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
            if let url = activity.webpageURL {
                handleIncomingURL(url)
            }
        }
        .onChange(of: profileManager.currentProfile?.id) { _ in
            guard let code = pendingJoinCode, profileManager.currentProfile != nil else { return }
            pendingJoinCode = nil
            Task { await processJoin(code: code) }
        }
        .onChange(of: authViewModel.isSignedIn) { signedIn in
            if !signedIn {
                pendingJoinCode = nil
                isProcessingIncomingLink = false
            }
        }
    }
}

// MARK: - Deep Link Handling

private extension ContentView {
    func handleIncomingURL(_ url: URL) {
        guard let deepLink = DeepLinkHandler.parse(url: url) else { return }
        switch deepLink {
        case .joinTrip(let code):
            scheduleJoin(for: code)
        }
    }
    
    func scheduleJoin(for code: String) {
        if profileManager.currentProfile == nil {
            pendingJoinCode = code
            linkAlertMessage = "Finish setting up your profile and we'll join group \(code) automatically."
            isShowingLinkAlert = true
            return
        }
        Task { await processJoin(code: code) }
    }
    
    func processJoin(code: String) async {
        await MainActor.run {
            isProcessingIncomingLink = true
        }
        let (success, error) = await tripListViewModel.joinTrip(with: code)
        await MainActor.run {
            isProcessingIncomingLink = false
            if success {
                linkAlertMessage = "You're now part of group \(code)."
            } else {
                linkAlertMessage = error ?? "We couldn't join group \(code)."
            }
            isShowingLinkAlert = true
        }
    }
    
    var progressBanner: some View {
        HStack(spacing: 8) {
            ProgressView()
                .scaleEffect(0.8)
            Text("Joining group…")
                .font(.footnote)
                .foregroundColor(.primary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.thinMaterial)
        .clipShape(Capsule())
        .padding(.top, 16)
    }
}
