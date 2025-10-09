import SwiftUI

struct ReportContentSheet: View {
    let target: ReportTarget

    @Environment(\.dismiss) private var dismiss
    @State private var selectedReason: ReportReason = .inappropriate
    @State private var additionalDetails: String = ""
    @State private var isSubmitting = false
    @State private var showingSuccessAlert = false
    @State private var error: AppError?

    private var trimmedDetails: String {
        additionalDetails.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSubmit: Bool {
        if isSubmitting { return false }
        if selectedReason.requiresDetails {
            return trimmedDetails.count >= 5
        }
        return true
    }

    var body: some View {
        NavigationView {
            Form {
                Section("Content") {
                    LabeledContent("Group") {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(target.tripName)
                            Text(target.tripCode)
                                .font(.footnote)
                                .foregroundColor(.secondary)
                                .textSelection(.enabled)
                        }
                    }

                    LabeledContent(target.contentType == .tripName ? "Group name" : "Expense name") {
                        Text(target.contentText)
                            .foregroundColor(.primary)
                    }

                    if let description = target.expenseDescription {
                        LabeledContent("Expense details") {
                            Text(description)
                                .foregroundColor(.secondary)
                        }
                    }

                    if let expenseId = target.expenseId {
                        LabeledContent("Expense ID") {
                            Text(expenseId.uuidString)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .textSelection(.enabled)
                        }
                    }
                }

                Section("Reason") {
                    ForEach(ReportReason.allCases) { reason in
                        Button {
                            selectedReason = reason
                        } label: {
                            HStack {
                                Text(reason.title)
                                    .foregroundColor(.primary)
                                Spacer()
                                if selectedReason == reason {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(.blue)
                                }
                            }
                        }
                    }
                }

                Section("Additional details") {
                    ZStack(alignment: .topLeading) {
                        if additionalDetails.isEmpty {
                            Text(selectedReason.requiresDetails ? "Tell us what feels off…" : "Optional context")
                                .foregroundColor(.secondary)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 14)
                        }

                        TextEditor(text: $additionalDetails)
                            .frame(minHeight: 120)
                            .padding(4)
                            .disabled(isSubmitting)
                    }
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color(.separator), lineWidth: 1)
                    )
                    .padding(.vertical, 4)

                    Text("Reports are reviewed by the Ledgex team. Misuse may lead to account restrictions.")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                        .padding(.vertical, 4)
                }
            }
            .navigationTitle("Report Content")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isSubmitting)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(action: submitReport) {
                        if isSubmitting {
                            ProgressView()
                        } else {
                            Text("Submit")
                        }
                    }
                    .disabled(!canSubmit)
                }
            }
        }
        .alert("Report Submitted", isPresented: $showingSuccessAlert) {
            Button("OK") { dismiss() }
        } message: {
            Text("Thanks for letting us know. We’ll review this item shortly.")
        }
        .alert(item: $error) { error in
            Alert(
                title: Text(error.title),
                message: Text(error.message),
                dismissButton: .default(Text("OK"))
            )
        }
    }

    private func submitReport() {
        guard !isSubmitting else { return }
        isSubmitting = true

        Task {
            do {
                let profile = await MainActor.run { ProfileManager.shared.currentProfile }
                var report = ContentReport(
                    tripId: target.tripId,
                    tripCode: target.tripCode,
                    tripName: target.tripName,
                    contentType: target.contentType,
                    contentText: target.contentText,
                    expenseId: target.expenseId,
                    expenseDescription: target.expenseDescription,
                    reporterProfileId: profile?.id,
                    reporterFirebaseUID: profile?.firebaseUID,
                    reporterName: profile?.name,
                    reason: selectedReason,
                    additionalDetails: trimmedDetails.isEmpty ? nil : trimmedDetails
                )

                if report.appVersion == nil {
                    report.appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
                }

                try await FirebaseManager.shared.submitContentReport(report)

                await MainActor.run {
                    isSubmitting = false
                    showingSuccessAlert = true
                }
            } catch {
                await MainActor.run {
                    isSubmitting = false
                    self.error = AppError.make(from: error, fallbackTitle: "Unable to Submit", fallbackMessage: "We couldn't send your report. Please try again.")
                }
            }
        }
    }
}
