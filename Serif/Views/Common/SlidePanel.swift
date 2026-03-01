import SwiftUI

struct SlidePanel<Content: View>: View {
    @Binding var isPresented: Bool
    let title: String
    let scrollable: Bool
    let content: Content
    @Environment(\.theme) private var theme

    init(
        isPresented: Binding<Bool>,
        title: String,
        scrollable: Bool = true,
        @ViewBuilder content: () -> Content
    ) {
        self._isPresented = isPresented
        self.title = title
        self.scrollable = scrollable
        self.content = content()
    }

    var body: some View {
        GeometryReader { geo in
            let panelWidth = geo.size.width * 0.5
            HStack(spacing: 0) {
                // Panel
                VStack(spacing: 0) {
                    // Header
                    HStack {
                        Text(title)
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(theme.textPrimary)
                        Spacer()
                        Button { isPresented = false } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(theme.textSecondary)
                                .frame(width: 24, height: 24)
                                .background(theme.cardBackground)
                                .cornerRadius(6)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(20)

                    Divider().background(theme.divider)

                    if scrollable {
                        ScrollView { content }
                    } else {
                        content
                    }
                }
                .frame(width: panelWidth)
                .frame(maxHeight: .infinity)
                .background(theme.listBackground)
                .shadow(color: .black.opacity(0.12), radius: 20, x: 8, y: 0)
                .offset(x: isPresented ? 0 : -(panelWidth + 60))

                // Tap outside to dismiss
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { isPresented = false }
            }
        }
        .allowsHitTesting(isPresented)
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: isPresented)
    }
}
