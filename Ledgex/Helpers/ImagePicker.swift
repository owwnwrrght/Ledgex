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
        picker.sourceType = sourceType
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
    @State private var showingActionSheet = false
    
    var body: some View {
        Button(action: {
            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                showingActionSheet = true
            } else {
                showingImagePicker = true
            }
        }) {
            Label("Add Receipt Photos", systemImage: "camera.fill")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .actionSheet(isPresented: $showingActionSheet) {
            ActionSheet(
                title: Text("Select Photo Source"),
                buttons: [
                    .default(Text("Camera")) {
                        showingImagePicker = true
                    },
                    .default(Text("Photo Library")) {
                        showingImagePicker = true
                    },
                    .cancel()
                ]
            )
        }
        .sheet(isPresented: $showingImagePicker) {
            ImagePicker(images: $images, sourceType: .photoLibrary)
        }
    }
}