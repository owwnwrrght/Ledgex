import SwiftUI

struct TripDetailView: View {
    let trip: Trip
    let tripListViewModel: TripListViewModel
    @StateObject private var viewModel: ExpenseViewModel
    @State private var selectedTab = 0
    @State private var showingShareSheet = false
    @State private var showingAddExpenseOptions = false
    @State private var expenseEntryMode: ExpenseEntryMode?
    @State private var showingReceiptScanner = false
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
                        showingAddExpenseOptions = true
                    }) {
                        Image(systemName: "plus")
                    }
                    .disabled(!viewModel.canAddExpenses)
                }

                Button(action: {
                    presentNativeShareSheet()
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
        .sheet(item: $expenseEntryMode) { mode in
            AddExpenseView(viewModel: viewModel, mode: mode)
        }
        .sheet(isPresented: $showingFlagPicker) {
            FlagPickerView(currentSelection: viewModel.trip.flagEmoji) { newFlag in
                Task { await viewModel.updateTripFlag(newFlag) }
            }
        }
        .sheet(isPresented: $showingSettings) {
            TripSettingsView(viewModel: viewModel)
        }
        .fullScreenCover(isPresented: $showingReceiptScanner) {
            ReceiptScannerView(viewModel: viewModel) { image, ocrResult in
                showingReceiptScanner = false
                viewModel.pendingItemizedExpense = (image, ocrResult)
            }
        }
        .sheet(item: itemWrapperBinding) { wrapper in
            ItemizedExpenseView(
                viewModel: viewModel,
                receiptImage: wrapper.value.0,
                ocrResult: wrapper.value.1
            )
        }
        .confirmationDialog("Add Expense", isPresented: $showingAddExpenseOptions, titleVisibility: .visible) {
            Button("Add manually") {
                showingAddExpenseOptions = false
                expenseEntryMode = .manual
            }
            Button("Quick add") {
                showingAddExpenseOptions = false
                expenseEntryMode = .quick
            }
            Button("Add from receipt") {
                showingAddExpenseOptions = false
                showingReceiptScanner = true
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Choose how you’d like to capture this expense.")
        }
        .refreshable {
            await viewModel.refreshFromCloud()
        }
    }

    private func presentNativeShareSheet() {
        Task {
            let link = await TripLinkService.shared.link(for: viewModel.trip)
            let message = "Join my group '\(viewModel.trip.name)' on Ledgex: \(link.absoluteString)"
            let activityItems: [Any] = [message, link]

            await MainActor.run {
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
        }
    }
}

struct TripSettingsView: View {
    @ObservedObject var viewModel: ExpenseViewModel
    @Environment(\.dismiss) var dismiss
    @State private var inviteURL: URL?
    @State private var isGeneratingLink = true
    @State private var editedName: String
    @State private var editedCurrency: Currency
    @State private var editedFlag: String
    @State private var isSaving = false
    @State private var showingFlagPicker = false
    @State private var showingNameAlert = false

    private var shareURL: URL {
        inviteURL ?? TripLinkService.fallbackLink(for: viewModel.trip)
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
                Section("Group Details") {
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
                }

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
                    .disabled(isSaving)
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
        .alert(item: errorBinding) { alert in
            Alert(title: Text(alert.title), message: Text(alert.message), dismissButton: .default(Text("OK")) {
                viewModel.lastError = nil
            })
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
