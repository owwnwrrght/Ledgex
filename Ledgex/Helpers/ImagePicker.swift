import SwiftUI
import UIKit

struct ImagePicker: UIViewControllerRepresentable {
    @Binding var images: [UIImage]
    @Environment(\.presentationMode) var presentationMode
    let sourceType: UIImagePickerController.SourceType
    var onSelection: (([UIImage]) -> Void)?
    
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.delegate = context.coordinator
        if UIImagePickerController.isSourceTypeAvailable(sourceType) {
            picker.sourceType = sourceType
        } else {
            print("[ImagePicker] Requested source \(sourceType.rawValue) unavailable. Falling back to photo library.")
            picker.sourceType = .photoLibrary
        }
        if picker.sourceType == .camera {
            if UIImagePickerController.isCameraDeviceAvailable(.rear) {
                picker.cameraDevice = .rear
            }
            picker.cameraCaptureMode = .photo
            picker.modalPresentationStyle = .fullScreen
        } else {
            picker.modalPresentationStyle = .automatic
        }
        picker.allowsEditing = false
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: ImagePicker
        
        init(_ parent: ImagePicker) {
            self.parent = parent
        }
        
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            if let image = info[.originalImage] as? UIImage {
                parent.images.append(image)
                // Call the selection callback if provided
                parent.onSelection?([image])
            }
            parent.presentationMode.wrappedValue.dismiss()
        }
        
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.presentationMode.wrappedValue.dismiss()
        }
    }
}

struct MultiImagePicker: View {
    @Binding var images: [UIImage]
    @State private var showingImagePicker = false
    @State private var showingSourceOptions = false
    @State private var imagePickerSourceType: UIImagePickerController.SourceType = .photoLibrary
    
    var body: some View {
        Button(action: {
            let cameraAvailable = UIImagePickerController.isSourceTypeAvailable(.camera)
            let libraryAvailable = UIImagePickerController.isSourceTypeAvailable(.photoLibrary)

            if cameraAvailable {
                showingSourceOptions = true
            } else if libraryAvailable {
                imagePickerSourceType = .photoLibrary
                showingImagePicker = true
            } else {
                print("[MultiImagePicker] No available image sources on this device.")
            }
        }) {
            Label("Add Receipt Photos", systemImage: "camera.fill")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .confirmationDialog(
            "Select Photo Source",
            isPresented: $showingSourceOptions,
            titleVisibility: .visible
        ) {
            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                Button("Camera") {
                    imagePickerSourceType = .camera
                    showingImagePicker = true
                }
            }
            if UIImagePickerController.isSourceTypeAvailable(.photoLibrary) {
                Button("Photo Library") {
                    imagePickerSourceType = .photoLibrary
                    showingImagePicker = true
                }
            }
            Button("Cancel", role: .cancel) {}
        }
        .sheet(
            isPresented: Binding(
                get: { showingImagePicker && imagePickerSourceType != .camera },
                set: { showingImagePicker = $0 }
            )
        ) {
            ImagePicker(
                images: $images,
                sourceType: imagePickerSourceType == .camera ? .photoLibrary : imagePickerSourceType
            )
        }
        .fullScreenCover(
            isPresented: Binding(
                get: { showingImagePicker && imagePickerSourceType == .camera },
                set: { showingImagePicker = $0 }
            )
        ) {
            ImagePicker(images: $images, sourceType: .camera)
                .ignoresSafeArea()
        }
    }
}
