import SwiftUI

extension LinearGradient {
    static var ledgexBackground: LinearGradient {
        LinearGradient(
            colors: [
                Color.blue.opacity(0.22),
                Color.purple.opacity(0.16),
                Color.teal.opacity(0.14)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static var ledgexAccentBorder: LinearGradient {
        LinearGradient(
            colors: [
                Color.blue.opacity(0.55),
                Color.purple.opacity(0.42)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static var ledgexCardFill: LinearGradient {
        LinearGradient(
            colors: [
                Color.white.opacity(0.92),
                Color.blue.opacity(0.12),
                Color.purple.opacity(0.10)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static var ledgexCallToAction: LinearGradient {
        LinearGradient(
            colors: [
                Color(red: 0.30, green: 0.42, blue: 0.95),
                Color(red: 0.52, green: 0.35, blue: 0.94)
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
    }
}

extension View {
    func ledgexBackground() -> some View {
        background(
            LinearGradient.ledgexBackground
                .opacity(0.95)
                .ignoresSafeArea()
        )
    }

    func ledgexCard(cornerRadius: CGFloat = 16) -> some View {
        background(
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(LinearGradient.ledgexCardFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius)
                .strokeBorder(LinearGradient.ledgexAccentBorder.opacity(0.6), lineWidth: 1)
        )
    }

    func ledgexOutlined(cornerRadius: CGFloat = 12) -> some View {
        overlay(
            RoundedRectangle(cornerRadius: cornerRadius)
                .strokeBorder(LinearGradient.ledgexAccentBorder.opacity(0.5), lineWidth: 1)
        )
    }
}
