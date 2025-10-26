import SwiftUI

struct ReceiptScannerView: View {
    @ObservedObject var viewModel: ExpenseViewModel
    @Environment(\.dismiss) var dismiss
    
    private let embedInNavigationView: Bool
    private let onCancel: (() -> Void)?
    let onComplete: ((UIImage, OCRResult) -> Void)?
    
    init(viewModel: ExpenseViewModel, embedInNavigationView: Bool = true, onCancel: (() -> Void)? = nil, onComplete: ((UIImage, OCRResult) -> Void)? = nil) {
        self.viewModel = viewModel
        self.embedInNavigationView = embedInNavigationView
        self.onCancel = onCancel
        self.onComplete = onComplete
    }
    
    @State private var receiptImage: UIImage?
    @State private var showingImagePicker = false
    @State private var imagePickerSourceType: UIImagePickerController.SourceType = .camera
    
    @State private var isProcessing = false
    @State private var ocrResult: OCRResult?
    @State private var errorMessage: String?
    @State private var showingError = false
    
    var body: some View {
        Group {
            if embedInNavigationView {
                NavigationView {
                    content
                        .navigationTitle("Scan Receipt")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar { navigationToolbar }
                }
            } else {
                content
                    .toolbar { navigationToolbar }
            }
        }
    }

    private var content: some View {
        VStack {
            if let image = receiptImage {
                VStack {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 320)
                        .cornerRadius(12)
                        .padding(.horizontal)

                    if isProcessing {
                        ProgressView("Processing receipt…")
                            .padding()
                    } else if ocrResult != nil {
                        Button(action: proceedWithItems) {
                            Label("Continue", systemImage: "arrow.right.circle.fill")
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.accentColor)
                                .foregroundColor(.white)
                                .cornerRadius(12)
                        }
                        .padding(.horizontal)
                    } else {
                        Button(action: scanReceipt) {
                            Label("Scan Receipt", systemImage: "doc.text.viewfinder")
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.accentColor)
                                .foregroundColor(.white)
                                .cornerRadius(12)
                        }
                        .padding(.horizontal)
                    }

                    if let result = ocrResult {
                        receiptPreview(result: result)
                    }
                }
                .padding(.top)
            } else {
                VStack(spacing: 24) {
                    Image(systemName: "doc.text.viewfinder")
                        .font(.system(size: 72, weight: .light))
                        .foregroundColor(.accentColor)

                    Text("How would you like to capture the receipt?")
                        .font(.headline)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)

                    VStack(spacing: 12) {
                        Button(action: captureWithCamera) {
                            Label("Take Photo", systemImage: "camera.fill")
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.accentColor)
                                .foregroundColor(.white)
                                .cornerRadius(12)
                        }
                        .padding(.horizontal)
                        .disabled(!UIImagePickerController.isSourceTypeAvailable(.camera))

                        Button(action: chooseFromLibrary) {
                            Label("Choose from Library", systemImage: "photo.on.rectangle")
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.gray.opacity(0.15))
                                .foregroundColor(.primary)
                                .cornerRadius(12)
                        }
                        .padding(.horizontal)
                    }
                }
                .frame(maxHeight: .infinity)
            }
        }
        .padding(.vertical)
        .sheet(isPresented: $showingImagePicker) {
            ImagePicker(images: .constant([]), sourceType: imagePickerSourceType) { selectedImages in
                if let image = selectedImages.first {
                    receiptImage = image
                    ocrResult = nil
                }
            }
        }
        .alert("Scan Failed", isPresented: $showingError) {
            Button("OK") { }
        } message: {
            Text(errorMessage ?? "We couldn't process this receipt. Try another photo with better lighting.")
        }
    }

    @ToolbarContentBuilder
    private var navigationToolbar: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Cancel") {
                if let onCancel {
                    onCancel()
                } else {
                    dismiss()
                }
            }
        }

        ToolbarItem(placement: .primaryAction) {
            if receiptImage != nil {
                Button("Start Over") {
                    receiptImage = nil
                    ocrResult = nil
                }
            }
        }
    }
    
    @ViewBuilder
    private func receiptPreview(result: OCRResult) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if let merchant = result.merchantName {
                HStack {
                    Text("Merchant:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(merchant)
                        .font(.caption)
                        .fontWeight(.medium)
                }
            }
            
            if let language = result.detectedLanguage, language != "en" {
                HStack {
                    Image(systemName: "globe")
                        .font(.caption)
                        .foregroundColor(.blue)
                    Text("Translated from \(languageName(for: language))")
                        .font(.caption)
                        .foregroundColor(.blue)
                }
            }
            
            Divider()
            
            Text("Items Found: \(result.items.count)")
                .font(.headline)
            
            // Show first few items
            ForEach(result.items.prefix(3)) { item in
                HStack {
                    Text(item.name)
                        .font(.caption)
                        .lineLimit(1)
                    Spacer()
                    Text(formatPrice(item.price))
                        .font(.caption)
                        .fontWeight(.medium)
                }
            }
            
            if result.items.count > 3 {
                Text("... and \(result.items.count - 3) more items")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            if let total = result.totalAmount {
                Divider()
                HStack {
                    Text("Total:")
                        .font(.headline)
                    Spacer()
                    Text(formatPrice(total))
                        .font(.headline)
                        .foregroundColor(.green)
                }
            }
        }
        .padding()
        .background(Color.gray.opacity(0.1))
        .cornerRadius(10)
        .padding(.horizontal)
    }
    
    private func captureWithCamera() {
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
            errorMessage = "Camera is not available on this device."
            showingError = true
            return
        }
        presentPicker(for: .camera)
    }

    private func chooseFromLibrary() {
        presentPicker(for: .photoLibrary)
    }

    private func presentPicker(for sourceType: UIImagePickerController.SourceType) {
        imagePickerSourceType = sourceType
        showingImagePicker = true
    }
    
    private func scanReceipt() {
        guard let image = receiptImage else { return }
        
        isProcessing = true
        errorMessage = nil
        
        Task {
            do {
                let result = try await GoogleCloudVisionService.shared.processReceipt(image: image)
                
                await MainActor.run {
                    self.ocrResult = result
                    self.isProcessing = false
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                    self.showingError = true
                    self.isProcessing = false
                }
            }
        }
    }
    
    private func proceedWithItems() {
        guard let result = ocrResult else { return }
        
        dismiss()
        
        // Navigate to itemized expense view
        // This will be passed through the completion handler
        if let onComplete = onComplete {
            onComplete(receiptImage!, result)
        }
    }
    
    private func formatPrice(_ price: Decimal) -> String {
        // Use the trip's base currency for formatting
        return CurrencyAmount(amount: price, currency: viewModel.trip.baseCurrency).formatted()
    }
    
    private func languageName(for code: String) -> String {
        let locale = Locale(identifier: "en")
        return locale.localizedString(forLanguageCode: code) ?? code.uppercased()
    }
}
