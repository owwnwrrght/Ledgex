import SwiftUI

struct ReceiptScannerView: View {
    @ObservedObject var viewModel: ExpenseViewModel
    @Environment(\.dismiss) var dismiss
    
    let onComplete: ((UIImage, OCRResult) -> Void)?
    
    init(viewModel: ExpenseViewModel, onComplete: ((UIImage, OCRResult) -> Void)? = nil) {
        self.viewModel = viewModel
        self.onComplete = onComplete
    }
    
    @State private var receiptImage: UIImage?
    @State private var showingImagePicker = false
    @State private var showingActionSheet = false
    @State private var imagePickerSourceType: UIImagePickerController.SourceType = .camera
    
    @State private var isProcessing = false
    @State private var ocrResult: OCRResult?
    @State private var errorMessage: String?
    @State private var showingError = false
    
    var body: some View {
        NavigationView {
            VStack {
                if let image = receiptImage {
                    // Show captured/selected image
                    VStack {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 300)
                            .cornerRadius(10)
                            .padding()
                        
                        if isProcessing {
                            ProgressView("Processing receipt...")
                                .padding()
                        } else if ocrResult != nil {
                            // OCR completed, show button to proceed
                            Button(action: proceedWithItems) {
                                Label("Continue with Items", systemImage: "arrow.right.circle.fill")
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .background(Color.blue)
                                    .foregroundColor(.white)
                                    .cornerRadius(10)
                            }
                            .padding(.horizontal)
                        } else {
                            // Show scan button
                            Button(action: scanReceipt) {
                                Label("Scan Receipt", systemImage: "doc.text.viewfinder")
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .background(Color.blue)
                                    .foregroundColor(.white)
                                    .cornerRadius(10)
                            }
                            .padding(.horizontal)
                        }
                        
                        // Show detected items preview
                        if let result = ocrResult {
                            receiptPreview(result: result)
                        }
                    }
                } else {
                    // No image selected
                    VStack(spacing: 20) {
                        Image(systemName: "camera.viewfinder")
                            .font(.system(size: 80))
                            .foregroundColor(.gray)
                        
                        Text("Take or select a receipt photo")
                            .font(.title2)
                            .foregroundColor(.secondary)
                        
                        Button(action: selectImage) {
                            Label("Select Receipt", systemImage: "photo.on.rectangle")
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.blue)
                                .foregroundColor(.white)
                                .cornerRadius(10)
                        }
                        .padding(.horizontal)
                    }
                    .frame(maxHeight: .infinity)
                }
            }
            .navigationTitle("Scan Receipt")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden(true)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    if receiptImage != nil {
                        Button("Retake") {
                            receiptImage = nil
                            ocrResult = nil
                        }
                    } else {
                        EmptyView()
                    }
                }
            }
            .actionSheet(isPresented: $showingActionSheet) {
                ActionSheet(
                    title: Text("Select Photo Source"),
                    buttons: [
                        .default(Text("Camera")) {
                            imagePickerSourceType = .camera
                            showingImagePicker = true
                        },
                        .default(Text("Photo Library")) {
                            imagePickerSourceType = .photoLibrary
                            showingImagePicker = true
                        },
                        .cancel()
                    ]
                )
            }
            .sheet(isPresented: $showingImagePicker) {
                ImagePicker(images: .constant([]), sourceType: imagePickerSourceType) { selectedImages in
                    if let image = selectedImages.first {
                        receiptImage = image
                    }
                }
            }
            .alert("Error", isPresented: $showingError) {
                Button("OK") { }
            } message: {
                Text(errorMessage ?? "An error occurred")
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
    
    private func selectImage() {
        if UIImagePickerController.isSourceTypeAvailable(.camera) {
            showingActionSheet = true
        } else {
            imagePickerSourceType = .photoLibrary
            showingImagePicker = true
        }
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

