import SwiftUI

/// Split-flap "departure board" styling used on the summary screen, matching the
/// app icon: amber characters on dark tiles with a center seam and side pivots.
enum Flap {
    static let amber = Color(red: 1.0, green: 0.77, blue: 0.28)
    static let green = Color(red: 0.30, green: 0.82, blue: 0.45)   // out of NY
    static let red = Color(red: 1.0, green: 0.42, blue: 0.42)      // NY days
    static let tileTop = Color(red: 0.15, green: 0.15, blue: 0.17)
    static let tileBottom = Color(red: 0.10, green: 0.10, blue: 0.12)
    static let seam = Color.black.opacity(0.9)
    static let boardBG = Color(red: 0.05, green: 0.05, blue: 0.06)
}

/// A single flap tile showing one character.
struct FlapTile: View {
    let ch: Character
    var size: CGFloat                 // cap-height driver
    var textColor: Color = Flap.amber

    private var tileW: CGFloat { size * 0.86 }
    private var tileH: CGFloat { size * 1.28 }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.13)
                .fill(LinearGradient(colors: [Flap.tileTop, Flap.tileBottom],
                                     startPoint: .top, endPoint: .bottom))
            Text(String(ch))
                .font(.system(size: size, weight: .bold, design: .monospaced))
                .foregroundStyle(textColor)
                .minimumScaleFactor(0.5)
                .lineLimit(1)
            // center seam
            Rectangle()
                .fill(Flap.seam)
                .frame(height: max(1, size * 0.05))
            // side pivots
            HStack {
                Circle().fill(Color.white.opacity(0.22)).frame(width: size*0.10, height: size*0.10)
                Spacer()
                Circle().fill(Color.white.opacity(0.22)).frame(width: size*0.10, height: size*0.10)
            }
        }
        .frame(width: tileW, height: tileH)
    }
}

/// A row of flap tiles rendering a whole string.
struct FlapText: View {
    let text: String
    var size: CGFloat
    var textColor: Color = Flap.amber

    var body: some View {
        HStack(spacing: size * 0.11) {
            ForEach(Array(text.enumerated()), id: \.offset) { _, ch in
                FlapTile(ch: ch, size: size, textColor: textColor)
            }
        }
    }
}

/// A labeled flap number (label above, tiles below) for the secondary counts.
struct FlapStat: View {
    let label: String
    let value: Int
    var size: CGFloat
    var textColor: Color = Flap.amber

    var body: some View {
        VStack(spacing: 6) {
            FlapText(text: String(value), size: size, textColor: textColor)
            Text(label)
                .font(.caption2).bold()
                .tracking(1.5)
                .foregroundStyle(.white.opacity(0.65))
        }
    }
}
