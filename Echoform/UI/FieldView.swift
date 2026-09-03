import SwiftUI

struct FieldView: View {
    var field: [Float]
    var width: Int
    var height: Int

    var body: some View {
        Canvas { ctx, size in
            guard width > 0, height > 0, field.count >= width * height else { return }
            let cw = size.width / CGFloat(width)
            let ch = size.height / CGFloat(height)
            for y in 0..<height {
                for x in 0..<width {
                    let v = field[y * width + x]
                    let rect = CGRect(x: CGFloat(x) * cw, y: CGFloat(y) * ch, width: cw + 0.5, height: ch + 0.5)
                    ctx.fill(Path(rect), with: .color(color(v)))
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.08)))
    }

    private func color(_ v: Float) -> Color {
        // constructive = cold bright, destructive = void
        Color(red: Double(0.05 + 0.15 * v),
              green: Double(0.25 + 0.55 * v),
              blue: Double(0.35 + 0.65 * v))
    }
}
