import SwiftUI

struct TripDetailView: View {
    let trip: Trip
    let tripListViewModel: TripListViewModel
    @StateObject private var viewModel: ExpenseViewModel
    @State private var selectedTab = 0
    @State private var showingShareSheet = false
    @State private var showingAddExpense = false
    @State private var showingFlagPicker = false
    @State private var showingSettings = false
    
    init(trip: Trip, tripListViewModel: TripListViewModel) {
        self.trip = trip
        self.tripListViewModel = tripListViewModel
        self._viewModel = StateObject(wrappedValue: ExpenseViewModel(trip: trip, dataStore: FirebaseManager.shared, tripListViewModel: tripListViewModel))
    }
    
    private var itemWrapperBinding: Binding<ItemWrapper?> {
        Binding(
            get: { 
                if let pendingExpense = viewModel.pendingItemizedExpense {
                    return ItemWrapper(value: pendingExpense)
                }
                return nil
            },
            set: { _ in 
                viewModel.pendingItemizedExpense = nil 
            }
        )
    }
    
    var body: some View {
        ZStack {
            LinearGradient.ledgexBackground
                .ignoresSafeArea()

            TabView(selection: $selectedTab) {
                PeopleView(viewModel: viewModel)
                    .tabItem {
                        Label("People", systemImage: "person.3")
                    }
                    .tag(0)

                ExpensesView(viewModel: viewModel)
                    .tabItem {
                        Label("Expenses", systemImage: "dollarsign.circle")
                    }
                    .tag(1)

                SettlementsView(viewModel: viewModel)
                    .tabItem {
                        Label("Settle Up", systemImage: viewModel.allParticipantsConfirmed ? "arrow.left.arrow.right" : "clock")
                    }
                    .tag(2)
            }
        }
        .navigationTitle(viewModel.trip.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button {
                    showingFlagPicker = true
                } label: {
                    Text(viewModel.trip.flagEmoji)
                        .font(.title2)
                }
            }
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                if selectedTab == 1 { // Expenses tab
                    Button(action: {
                        showingAddExpense = true
                    }) {
                        Image(systemName: "plus")
                    }
                    .disabled(!viewModel.canAddExpenses)
                }

                Button(action: {
                    showingShareSheet = true
                }) {
                    Label("Invite Friends", systemImage: "person.badge.plus")
                }

                Button(action: {
                    showingSettings = true
                }) {
                    Image(systemName: "gearshape")
                }
            }
        }
        .sheet(isPresented: $showingShareSheet) {
            ShareTripView(trip: viewModel.trip)
        }
        .sheet(isPresented: $showingAddExpense) {
            ExpenseEntryFlowView(viewModel: viewModel)
        }
        .sheet(isPresented: $showingFlagPicker) {
            FlagPickerView(currentSelection: viewModel.trip.flagEmoji) { newFlag in
                Task { await viewModel.updateTripFlag(newFlag) }
            }
        }
        .sheet(isPresented: $showingSettings) {
            TripSettingsView(viewModel: viewModel)
        }
        .sheet(item: itemWrapperBinding) { wrapper in
            ItemizedExpenseView(
                viewModel: viewModel,
                receiptImage: wrapper.value.0,
                ocrResult: wrapper.value.1
            )
        }

        .refreshable {
            await viewModel.refreshFromCloud()
        }
    }

}

struct TripSettingsView: View {
    @ObservedObject var viewModel: ExpenseViewModel
    @EnvironmentObject private var authViewModel: AuthViewModel
    @Environment(\.dismiss) var dismiss
    @State private var inviteURL: URL?
    @State private var isGeneratingLink = true
    @State private var editedName: String
    @State private var editedCurrency: Currency
    @State private var editedFlag: String
    @State private var isSaving = false
    @State private var showingFlagPicker = false
    @State private var showingNameAlert = false
    @State private var showingLeaveConfirmation = false
    @State private var showingDeleteConfirmation = false
    @State private var activeGroupAction: GroupAction?
    @State private var reportTarget: ReportTarget?
    @State private var showingAccountDeletion = false

    private var shareURL: URL {
        inviteURL ?? TripLinkService.fallbackLink(for: viewModel.trip)
    }

    private enum GroupAction: Equatable {
        case leave
        case delete
    }

    init(viewModel: ExpenseViewModel) {
        self._viewModel = ObservedObject(initialValue: viewModel)
        _editedName = State(initialValue: viewModel.trip.name)
        _editedCurrency = State(initialValue: viewModel.trip.baseCurrency)
        _editedFlag = State(initialValue: viewModel.trip.flagEmoji)
    }

    var body: some View {
        NavigationView {
            List {
                groupDetailsSection
                inviteOptionsSection
                safetySection
                groupActionsSection
                accountManagementSection
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Group Settings")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        saveChanges()
                    } label: {
                        if isSaving {
                            ProgressView()
                        } else {
                            Text("Save")
                        }
                    }
                    .disabled(isSaving || activeGroupAction != nil)
                }
            }
        }
        .task {
            await generateInviteLink()
        }
        .onChange(of: viewModel.trip.id) { _ in
            editedName = viewModel.trip.name
            editedCurrency = viewModel.trip.baseCurrency
            editedFlag = viewModel.trip.flagEmoji
        }
        .sheet(isPresented: $showingFlagPicker) {
            FlagPickerView(currentSelection: editedFlag) { selection in
                editedFlag = selection
            }
        }
        .alert("Group name required", isPresented: $showingNameAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Please provide a group name before saving.")
        }
        .confirmationDialog("Leave Group?", isPresented: $showingLeaveConfirmation, titleVisibility: .visible) {
            Button("Leave Group", role: .destructive) {
                performGroupAction(.leave)
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("You’ll lose access to this group on all of your devices. Other members will keep the group.")
        }
        .confirmationDialog("Delete Group for Everyone?", isPresented: $showingDeleteConfirmation, titleVisibility: .visible) {
            Button("Delete Group", role: .destructive) {
                performGroupAction(.delete)
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This permanently removes the group and its data for every member. This action cannot be undone.")
        }
        .alert(item: errorBinding) { alert in
            Alert(title: Text(alert.title), message: Text(alert.message), dismissButton: .default(Text("OK")) {
                viewModel.lastError = nil
            })
        }
        .sheet(item: $reportTarget) { target in
            ReportContentSheet(target: target)
        }
        .sheet(isPresented: $showingAccountDeletion) {
            AccountDeletionView()
                .environmentObject(authViewModel)
        }
    }
    
    private var groupDetailsSection: some View {
        Section {
            TextField("Group name", text: $editedName)

            Button {
                showingFlagPicker = true
            } label: {
                HStack {
                    Text(editedFlag)
                        .font(.title2)
                    Text("Change Icon")
                    Spacer()
                    Image(systemName: "chevron.right")
                        .foregroundColor(.secondary)
                }
            }

            Picker("Base Currency", selection: $editedCurrency) {
                ForEach(Currency.allCases, id: \.self) { currency in
                    Text(currency.displayName).tag(currency)
                }
            }
        } header: {
            Text("Group Details")
        }
    }

    private var inviteOptionsSection: some View {
        Section {
            inviteLinkSection
            groupCodeSection
            qrCodeSection
        } header: {
            Text("Invite Options")
        } footer: {
            Text("Share the invite link in your group chat. Friends can also scan the QR code or manually enter the group code.")
        }
    }

    private var safetySection: some View {
        Section {
            Button {
                reportTarget = ReportTarget(trip: viewModel.trip, contentType: .tripName, contentText: viewModel.trip.name)
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "flag")
                        .foregroundColor(.red)
                    Text("Report Group Name")
                    Spacer()
                    Image(systemName: "chevron.right")
                        .foregroundColor(Color(.tertiaryLabel))
                }
            }
            .disabled(activeGroupAction != nil)
        } header: {
            Text("Safety & Reporting")
        } footer: {
            Text("Flag names that contain spam, hate speech, or sensitive info.")
        }
    }

    private var groupActionsSection: some View {
        Section {
            Button(role: .destructive) {
                showingLeaveConfirmation = true
            } label: {
                groupActionLabel(title: "Leave Group", systemImage: "person.crop.circle.fill.badge.minus", action: .leave)
            }
            .disabled(activeGroupAction != nil)

            Button(role: .destructive) {
                showingDeleteConfirmation = true
            } label: {
                groupActionLabel(title: "Delete Group For Everyone", systemImage: "trash", action: .delete)
            }
            .disabled(activeGroupAction != nil)
        } header: {
            Text("Group Actions")
        } footer: {
            Text("Leaving removes you from the group on every device. Deleting permanently removes the group and all data for everyone.")
        }
    }

    private var accountManagementSection: some View {
        Section {
            Button {
                showingAccountDeletion = true
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "person.crop.circle.badge.xmark")
                        .foregroundColor(.red)
                    Text("Delete My Account")
                        .foregroundColor(.primary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .foregroundColor(Color(.tertiaryLabel))
                }
            }
            .disabled(activeGroupAction != nil)
        } header: {
            Text("Account Management")
        } footer: {
            Text("Delete your Ledgex account even if you created this group. You'll be signed out everywhere.")
        }
    }

    private var inviteLinkSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color(.systemBlue).opacity(0.12))
                        .frame(width: 44, height: 44)
                    Image(systemName: "link")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.blue)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Invite Link")
                        .font(.headline)
                    Text("Send this link to invite new members.")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
            }

            if isGeneratingLink {
                HStack {
                    ProgressView()
                    Text("Generating link…")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    Text(shareURL.absoluteString)
                        .font(.system(.footnote, design: .monospaced))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contextMenu {
                            Button(action: copyInviteLink) {
                                Label("Copy link", systemImage: "doc.on.doc")
                            }
                        }

                    Divider()

                    HStack(spacing: 12) {
                        Button(action: presentShareSheet) {
                            Label("Share", systemImage: "square.and.arrow.up")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .labelStyle(.titleAndIcon)

                        Button(action: copyInviteLink) {
                            Label("Copy", systemImage: "doc.on.doc")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .labelStyle(.titleAndIcon)
                    }
                }
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color(.systemGray4), lineWidth: 0.5)
        )
        .padding(.vertical, 4)
    }

    private var groupCodeSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: "number.circle.fill")
                    .font(.title2)
                    .foregroundColor(.purple)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Group Code")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    Text("Friends can enter this code manually")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            HStack {
                Text(viewModel.trip.code)
                    .font(.system(.title3, design: .monospaced))
                    .fontWeight(.bold)
                Spacer()
                Button(action: {
                    UIPasteboard.general.string = viewModel.trip.code
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                }) {
                    Label("Copy", systemImage: "doc.on.doc")
                        .labelStyle(.iconOnly)
                }
            }
        }
        .padding(.vertical, 8)
    }

    private var qrCodeSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: "qrcode")
                    .font(.title2)
                    .foregroundColor(.green)
                VStack(alignment: .leading, spacing: 2) {
                    Text("QR Code")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    Text("Friends can scan this to join")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            if isGeneratingLink {
                ProgressView()
            } else {
                QRCodeView(content: shareURL.absoluteString)
                    .frame(width: 200, height: 200)
                    .padding(16)
                    .background(Color(.systemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .shadow(color: Color.black.opacity(0.1), radius: 8, x: 0, y: 4)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.vertical, 8)
    }

    private func generateInviteLink() async {
        await MainActor.run {
            isGeneratingLink = true
        }
        let url = await TripLinkService.shared.link(for: viewModel.trip)
        await MainActor.run {
            inviteURL = url
            isGeneratingLink = false
        }
    }

    private func copyInviteLink() {
        UIPasteboard.general.string = shareURL.absoluteString
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    private func presentShareSheet() {
        let message = "Join my group '\(viewModel.trip.name)' on Ledgex: \(shareURL.absoluteString)"
        let activityItems: [Any] = [message, shareURL]

        if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let viewController = scene.windows.first?.rootViewController {
            let activityVC = UIActivityViewController(activityItems: activityItems, applicationActivities: nil)

            if let presented = viewController.presentedViewController {
                presented.present(activityVC, animated: true)
            } else {
                viewController.present(activityVC, animated: true)
            }
        }
    }

    private func saveChanges() {
        let trimmedName = editedName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            showingNameAlert = true
            return
        }

        isSaving = true
        Task {
            let success = await viewModel.updateGroupDetails(name: trimmedName, baseCurrency: editedCurrency, flagEmoji: editedFlag)
            await MainActor.run {
                isSaving = false
                if success {
                    dismiss()
                }
            }
        }
    }

    private func performGroupAction(_ action: GroupAction) {
        guard activeGroupAction == nil else { return }
        activeGroupAction = action

        Task {
            let success: Bool
            switch action {
            case .leave:
                success = await viewModel.leaveGroup()
            case .delete:
                success = await viewModel.deleteGroupForEveryone()
            }

            await MainActor.run {
                activeGroupAction = nil
                if success {
                    dismiss()
                }
            }
        }
    }

    @ViewBuilder
    private func groupActionLabel(title: String, systemImage: String, action: GroupAction) -> some View {
        HStack(spacing: 12) {
            if activeGroupAction == action {
                ProgressView()
                    .progressViewStyle(.circular)
                    .frame(width: 20, height: 20)
            } else {
                Image(systemName: systemImage)
                    .frame(width: 20)
            }
            Text(title)
            Spacer()
        }
    }

    private var errorBinding: Binding<AppError?> {
        Binding(get: { viewModel.lastError }, set: { viewModel.lastError = $0 })
    }
}

private struct QRCodeView: View {
    let content: String
    private let context = CIContext()

    var body: some View {
        if let image = generateQRCode(from: content) {
            Image(uiImage: image)
                .resizable()
                .interpolation(.none)
                .antialiased(false)
                .scaledToFit()
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(.systemGray5))
                Image(systemName: "xmark.octagon")
                    .foregroundColor(.secondary)
            }
        }
    }

    private func generateQRCode(from value: String) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.setValue(Data(value.utf8), forKey: "inputMessage")
        filter.setValue("Q", forKey: "inputCorrectionLevel")
        guard let outputImage = filter.outputImage else { return nil }
        let scaledImage = outputImage.transformed(by: CGAffineTransform(scaleX: 12, y: 12))
        guard let cgImage = context.createCGImage(scaledImage, from: scaledImage.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}
