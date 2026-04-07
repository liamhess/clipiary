import SwiftUI

/// An `L`-shaped bracket: vertical line with a short horizontal cap only at the bottom.
struct BracketShape: Shape {
    var lineWidth: CGFloat = 2
    var capWidth: CGFloat = 6

    func path(in rect: CGRect) -> Path {
        var p = Path()
        // vertical stroke
        p.addRect(CGRect(x: 0, y: 0, width: lineWidth, height: rect.height))
        // bottom cap only
        p.addRect(CGRect(x: 0, y: rect.height - lineWidth, width: capWidth, height: lineWidth))
        return p
    }
}

/// Wraps child settings that depend on a parent toggle.
/// Always rendered (never hidden), but dimmed and non-interactive when `enabled` is false.
/// An `L`-bracket on the left visually groups the dependent children.
struct DependentGroup<Content: View>: View {
    let enabled: Bool
    var showBracket: Bool = true
    @ViewBuilder let content: Content

    var body: some View {
        if showBracket {
            HStack(alignment: .top, spacing: 6) {
                BracketShape()
                    .fill(Color.secondary.opacity(0.4))
                    .frame(width: 6)
                VStack(alignment: .leading, spacing: 4) {
                    content
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .allowsHitTesting(enabled)
                .opacity(enabled ? 1 : 0.6)
            }
            .fixedSize(horizontal: false, vertical: true)
            .padding(.leading, 14)
        } else {
            VStack(alignment: .leading, spacing: 4) {
                content
            }
            .allowsHitTesting(enabled)
            .opacity(enabled ? 1 : 0.6)
        }
    }
}
