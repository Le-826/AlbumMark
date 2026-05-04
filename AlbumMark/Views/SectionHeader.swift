import SwiftUI

struct SectionHeader: View {
    let title: String
    let systemImage: String

    var body: some View {
        Text(title.uppercased())
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.secondary.opacity(0.82))
            .tracking(0.2)
    }
}

struct ThinProgressBar: View {
    let value: Double

    private var clampedValue: Double {
        min(max(value, 0), 1)
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.primary.opacity(0.12))

                Capsule()
                    .fill(Color(nsColor: .controlAccentColor).opacity(0.82))
                    .frame(width: max(4, proxy.size.width * clampedValue))
            }
        }
        .frame(height: 4)
        .accessibilityLabel("Album progress")
        .accessibilityValue("\(Int((clampedValue * 100).rounded()))%")
    }
}
