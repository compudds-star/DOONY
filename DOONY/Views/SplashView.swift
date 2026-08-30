import SwiftUI

/// Launch screen: the app mark, the name, and the exact version and build.
///
/// The version is on screen deliberately. This app's whole job is producing
/// records someone may have to defend years later, so "which build produced
/// this?" is a question worth being able to answer from a screenshot rather
/// than by digging through Settings.
struct SplashView: View {

    /// Matches the app icon so the splash and the home-screen icon read as one
    /// thing. Sampled from Assets.xcassets/AppIcon: ground #0D0D0F, amber #FFC448.
    private static let ground = Color(red: 13/255, green: 13/255, blue: 15/255)
    private static let amber  = Color(red: 255/255, green: 196/255, blue: 72/255)

    /// "1.0 (3)" — reads from the bundle, so it cannot drift from what shipped.
    static var versionString: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "—"
        let build = info?["CFBundleVersion"] as? String ?? "—"
        return "\(short) (\(build))"
    }

    var body: some View {
        ZStack {
            Self.ground.ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                Image("SplashLogo")
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(width: 148, height: 148)
                    .clipShape(RoundedRectangle(cornerRadius: 33, style: .continuous))
                    .shadow(color: .black.opacity(0.5), radius: 24, y: 10)

                Text("DOONY")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .kerning(6)
                    .foregroundStyle(Self.amber)
                    .padding(.top, 28)

                Text("Days out of New York")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.white.opacity(0.55))
                    .padding(.top, 6)

                Spacer()

                Text("Version \(Self.versionString)")
                    .font(.system(size: 13, weight: .regular, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.38))
                    .padding(.bottom, 34)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("DOONY, days out of New York, version \(Self.versionString)")
        }
        // The splash is always dark, regardless of the device's appearance.
        .preferredColorScheme(.dark)
    }
}

#Preview { SplashView() }
