import SwiftUI

struct AccountDeletionView: View {
    @EnvironmentObject private var authViewModel: AuthViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var showingConfirmation = false
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Before You Delete"), footer: Text("This action permanently removes your Ledgex profile, trips you created, and any data you uploaded. Deleted accounts cannot be recovered.")) {
                    Label("You’ll be signed out on all devices", systemImage: "iphone.slash")
                    Label("Trips you own will be deleted for every member", systemImage: "person.3")
                    Label("Receipts and attachments are removed from our servers", systemImage: "doc.on.doc.fill")
                }
                
                Section(footer: Text("If you recently signed in, the deletion will finish right away. Otherwise, sign in again and retry if you see an error.")) {
                    if authViewModel.isProcessing {
                        ProgressView("Processing…")
                            .progressViewStyle(CircularProgressViewStyle())
                    }
                    
                    if let message = authViewModel.errorMessage, !message.isEmpty {
                        Text(message)
                            .font(.footnote)
                            .foregroundColor(.red)
                    }
                    
                    Button("Delete My Account", role: .destructive) {
                        showingConfirmation = true
                    }
                    .disabled(authViewModel.isProcessing)
                }
            }
            .navigationTitle("Delete Account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .alert("Delete Ledgex Account?", isPresented: $showingConfirmation) {
            Button("Delete", role: .destructive) {
                authViewModel.initiateAccountDeletion()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This permanently deletes your account and all associated data.")
        }
        .onChange(of: authViewModel.isSignedIn) { signedIn in
            if !signedIn {
                dismiss()
            }
        }
    }
}
