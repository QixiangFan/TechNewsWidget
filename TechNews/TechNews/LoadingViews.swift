import SwiftUI

/// Gray stand-ins for the hero and the first cards, with a sheen sweeping across while headlines load.
struct MagazineSkeleton: View {
    let columns: [GridItem]

    var body: some View {
        VStack(alignment: .leading, spacing: 26) {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(.quaternary)
                .aspectRatio(2.35, contentMode: .fit)
            LazyVGrid(columns: columns, alignment: .leading, spacing: 22) {
                ForEach(0..<6, id: \.self) { _ in
                    CardSkeleton()
                }
            }
        }
        .shimmering()
        .accessibilityLabel(Text("Loading"))
    }
}

private struct CardSkeleton: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Rectangle()
                .fill(.quaternary)
                .aspectRatio(16 / 9, contentMode: .fit)
            VStack(alignment: .leading, spacing: 9) {
                Capsule().fill(.quaternary).frame(width: 96, height: 9)
                Capsule().fill(.quaternary).frame(height: 12)
                Capsule().fill(.quaternary).frame(width: 170, height: 12)
                Capsule().fill(.quaternary.opacity(0.6)).frame(height: 9).padding(.top, 4)
                Capsule().fill(.quaternary.opacity(0.6)).frame(width: 130, height: 9)
            }
            .padding(15)
        }
        .background(Color.card)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

extension View {
    /// A soft band of light sweeping across the view, left to right, over and over.
    func shimmering() -> some View {
        modifier(Shimmer())
    }
}

private struct Shimmer: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .overlay {
                if !reduceMotion {
                    GeometryReader { proxy in
                        LinearGradient(colors: [.clear, .white.opacity(0.35), .clear], startPoint: .leading,
                                       endPoint: .trailing)
                            .frame(width: proxy.size.width * 0.45)
                            .offset(x: (phase * 1.45 - 0.45) * proxy.size.width)
                    }
                    .mask(content)
                    .allowsHitTesting(false)
                }
            }
            .onAppear {
                withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                    phase = 1
                }
            }
    }
}

/// Fades and lifts a card into place, one after another in reading order.
struct Reveal: ViewModifier {
    let index: Int
    let isShown: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .opacity(isShown ? 1 : 0)
            .offset(y: isShown || reduceMotion ? 0 : 22)
            .scaleEffect(isShown || reduceMotion ? 1 : 0.98, anchor: .top)
            .animation(
                reduceMotion
                    ? .easeOut(duration: 0.2)
                    : .spring(response: 0.6, dampingFraction: 0.85).delay(Double(min(index, 12)) * 0.04),
                value: isShown)
    }
}
