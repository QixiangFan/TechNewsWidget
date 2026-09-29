import NewsKit
import SwiftUI

/// The category tabs. The selected tab's colored capsule slides to the new tab; ⌘1–⌘5 switch tabs.
struct CategoryBar: View {
    @Binding var selection: NewsCategory
    @Namespace private var namespace

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Array(NewsCategory.allCases.enumerated()), id: \.element) { index, category in
                CategoryTab(category: category, isSelected: selection == category, namespace: namespace) {
                    withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
                        selection = category
                    }
                }
                .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: .command)
            }
        }
    }
}

private struct CategoryTab: View {
    let category: NewsCategory
    let isSelected: Bool
    let namespace: Namespace.ID
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: category.symbolName)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(isSelected ? AnyShapeStyle(.white) : AnyShapeStyle(category.accentColor))
                Text(category.localizedTitle)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(isSelected ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 7)
            .background {
                if isSelected {
                    Capsule()
                        .fill(category.accentColor.gradient)
                        .shadow(color: category.accentColor.opacity(0.35), radius: 8, y: 3)
                        .matchedGeometryEffect(id: "selection", in: namespace)
                } else if isHovered {
                    Capsule().fill(.quaternary)
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.15), value: isHovered)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
