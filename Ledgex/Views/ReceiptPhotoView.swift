import SwiftUI
import UIKit

struct ReceiptPhotoView: View {
    let expense: Expense
    @State private var receiptImages: [UIImage] = []
    @State private var isLoading = true
    @State private var selectedImage: UIImage?
    @State private var showingImageViewer = false
    
    let dataStore: TripDataStore
    
    var body: some View {
        VStack {
            if isLoading {
                ProgressView("Loading receipts...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if receiptImages.isEmpty {
                VStack {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.system(size: 60))
                        .foregroundColor(.gray)
                    Text("No receipts attached")
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 150))], spacing: 10) {
                        ForEach(Array(receiptImages.enumerated()), id: \.offset) { _, image in
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 150, height: 150)
                                .clipped()
                                .cornerRadius(10)
                                .onTapGesture {
                                    selectedImage = image
                                    showingImageViewer = true
                                }
                        }
                    }
                    .padding()
                }
            }
        }
        .navigationTitle("Receipts")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingImageViewer) {
            if let image = selectedImage {
                ImageViewer(image: image)
            }
        }
        .onAppear {
            Task {
                await loadReceipts()
            }
        }
    }
    
    private func loadReceipts() async {
        guard !expense.receiptImageIds.isEmpty else {
            print("📝 No receipt images to load for expense: \(expense.description)")
            isLoading = false
            return
        }
        
        print("🔄 Loading \(expense.receiptImageIds.count) receipt images for expense: \(expense.description)")
        isLoading = true
        var loadedImages: [UIImage] = []
        
        for (index, imageUrl) in expense.receiptImageIds.enumerated() {
            do {
                print("⬇️ Downloading receipt \(index + 1)/\(expense.receiptImageIds.count)")
                
                if let imageData = try await dataStore.downloadReceiptImage(imageUrl),
                   let image = UIImage(data: imageData) {
                    loadedImages.append(image)
                    print("✅ Successfully loaded receipt \(index + 1)")
                } else {
                    print("⚠️ No data returned for receipt \(index + 1)")
                }
            } catch {
                print("❌ Failed to load receipt \(index + 1): \(error)")
            }
        }
        
        await MainActor.run {
            receiptImages = loadedImages
            isLoading = false
        }
        
        print("🏁 Loaded \(receiptImages.count)/\(expense.receiptImageIds.count) receipt images")
    }
}

struct ImageViewer: View {
    let image: UIImage
    @Environment(\.dismiss) var dismiss
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    
    var body: some View {
        NavigationView {
            GeometryReader { geometry in
                ScrollView([.horizontal, .vertical], showsIndicators: false) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(width: geometry.size.width * scale, height: geometry.size.height * scale)
                        .gesture(
                            MagnificationGesture()
                                .onChanged { value in
                                    let delta = value / lastScale
                                    lastScale = value
                                    scale = min(max(scale * delta, 1), 4)
                                }
                                .onEnded { _ in
                                    lastScale = 1.0
                                }
                        )
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

struct ReceiptAttachmentView: View {
    @Binding var receiptImages: [UIImage]
    @State private var showingImagePicker = false
    @State private var showingActionSheet = false
    @State private var imagePickerSourceType: UIImagePickerController.SourceType = .photoLibrary
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Receipt Photos")
                .font(.headline)
            
            if !receiptImages.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(Array(receiptImages.enumerated()), id: \.offset) { index, image in
                            ZStack(alignment: .topTrailing) {
                                Image(uiImage: image)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 80, height: 80)
                                    .clipped()
                                    .cornerRadius(8)
                                
                                Button(action: {
                                    receiptImages.remove(at: index)
                                }) {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundColor(.white)
                                        .background(Color.black.opacity(0.6))
                                        .clipShape(Circle())
                                }
                                .padding(4)
                            }
                        }
                    }
                }
            }
            
            Button(action: {
                if UIImagePickerController.isSourceTypeAvailable(.camera) {
                    showingActionSheet = true
                } else {
                    imagePickerSourceType = .photoLibrary
                    showingImagePicker = true
                }
            }) {
                Label("Add Receipt Photos", systemImage: "camera.fill")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(8)
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
            ImagePicker(images: $receiptImages, sourceType: imagePickerSourceType)
        }
    }
}