import SwiftUI

/// Green capsule toast that slides in from top and auto-dismisses
struct ToastView: View {
    let message: String

    var body: some View {
        Text(message)
            .font(.subheadline)
            .fontWeight(.medium)
            .foregroundStyle(.white)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(.green.gradient, in: Capsule())
            .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
    }
}
