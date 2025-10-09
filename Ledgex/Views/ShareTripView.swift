import SwiftUI
import UIKit
import CoreImage.CIFilterBuiltins

struct ShareTripView: View {
    let trip: Trip
    @Environment(\.dismiss) var dismiss
    
    @State private var inviteURL: URL?
    @State private var isGeneratingLink = true
    @State private var showingMoreOptions = false
    
    private var shareURL: URL {
        inviteURL ?? TripLinkService.fallbackLink(for: trip)
    }
    
    private var shareMessage: String {
        "Join my group '\(trip.name)' on Ledgex: \(shareURL.absoluteString)\nIf you need a backup option, enter code \(trip.code)."
    }
    
    private var shareItems: [Any] {
        [shareMessage, shareURL]
    }
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    header
                    linkCard
                    moreOptions
                    tips
                }
                .padding(.horizontal)
                .padding(.bottom, 32)
            }
            .navigationTitle("Share Group")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .task {
            await generateInviteLink()
        }
    }
    
    private var header: some View {
        VStack(spacing: 12) {
            Text(trip.flagEmoji)
                .font(.system(size: 60))
            Text("Share \(trip.name)")
                .font(.title)
                .fontWeight(.bold)
            Text("Send one link and Ledgex will handle the rest.")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top)
    }

    private var linkCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Group invite link")
                .font(.headline)
            Text(shareURL.absoluteString)
                .font(.footnote.monospaced())
                .foregroundColor(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .contextMenu {
                    Button(action: copyLink) {
                        Label("Copy link", systemImage: "doc.on.doc")
                    }
                }
            HStack(spacing: 12) {
                Button(action: presentShareSheet) {
                    Label("Share", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                Button(action: copyLink) {
                    Label("Copy", systemImage: "doc.on.doc")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Color(.secondarySystemBackground)))
    }

    private var moreOptions: some View {
        DisclosureGroup(isExpanded: $showingMoreOptions) {
            VStack(alignment: .leading, spacing: 16) {
                Divider()
                VStack(alignment: .leading, spacing: 8) {
                    Text("Group code")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    HStack {
                        Text(trip.code)
                            .font(.system(.title3, design: .monospaced))
                        Spacer()
                        Button(action: copyCode) {
                            Label("Copy", systemImage: "number")
                                .labelStyle(.iconOnly)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("QR code")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    if isGeneratingLink {
                        ProgressView()
                    } else {
                        QRCodeView(content: shareURL.absoluteString)
                            .frame(width: 180, height: 180)
                            .padding(12)
                            .background(Color(.systemBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .shadow(color: Color.black.opacity(0.06), radius: 6, x: 0, y: 2)
                            .accessibilityHidden(true)
                    }
                }
            }
            .padding(.top, 12)
        } label: {
            Text("Need another way to join?")
                .font(.subheadline)
                .fontWeight(.semibold)
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Color(.systemGray4)))
    }

    private var tips: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Tips")
                .font(.headline)
            Text(
                "Send the invite link in your group chat. If someone can’t open it, they can scan the QR code or type the backup code."
            )
            .font(.footnote)
            .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
    
    private func copyLink() {
        UIPasteboard.general.string = shareURL.absoluteString
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    private func copyCode() {
        UIPasteboard.general.string = trip.code
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
    
    private func presentShareSheet() {
        let activityVC = UIActivityViewController(activityItems: shareItems, applicationActivities: nil)
        
        if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let root = scene.windows.first?.rootViewController {
            if let presented = root.presentedViewController {
                presented.present(activityVC, animated: true)
            } else {
                root.present(activityVC, animated: true)
            }
        }
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

// MARK: - Helpers

private extension ShareTripView {
    func generateInviteLink() async {
        await MainActor.run {
            isGeneratingLink = true
        }
        let url = await TripLinkService.shared.link(for: trip)
        await MainActor.run {
            inviteURL = url
            isGeneratingLink = false
        }
    }
}
