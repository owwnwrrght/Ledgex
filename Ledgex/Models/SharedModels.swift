import SwiftUI
import Foundation

// Helper wrapper for sheet presentation
struct ItemWrapper: Identifiable {
    let id = UUID()
    let value: (UIImage, OCRResult)
}