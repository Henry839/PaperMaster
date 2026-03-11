import SwiftUI

struct TagChipPalette: Equatable {
    let hue: Double
    let saturation: Double
    let brightness: Double
}

struct TagChip: View {
    let name: String

    var body: some View {
        let normalizedName = Tag.normalize(name)
        let palette = TagChipStyle.palette(for: normalizedName)

        Text(Tag.displayName(for: normalizedName))
            .font(.caption.weight(.semibold))
            .foregroundStyle(TagChipStyle.foregroundColor(for: palette))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(TagChipStyle.backgroundColor(for: palette))
            .overlay(
                Capsule()
                    .stroke(TagChipStyle.borderColor(for: palette), lineWidth: 1)
            )
            .clipShape(Capsule())
    }
}

enum TagChipStyle {
    static func palette(for name: String) -> TagChipPalette {
        let normalizedName = Tag.normalize(name)
        let hash = stableHash(for: normalizedName)
        let hue = Double(hash % 360) / 360.0
        return TagChipPalette(hue: hue, saturation: 0.60, brightness: 0.84)
    }

    static func foregroundColor(for palette: TagChipPalette) -> Color {
        Color(hue: palette.hue, saturation: min(1.0, palette.saturation + 0.18), brightness: 0.34)
    }

    static func backgroundColor(for palette: TagChipPalette) -> Color {
        Color(hue: palette.hue, saturation: 0.26, brightness: 0.98).opacity(0.95)
    }

    static func borderColor(for palette: TagChipPalette) -> Color {
        Color(hue: palette.hue, saturation: 0.42, brightness: 0.76).opacity(0.70)
    }

    private static func stableHash(for value: String) -> UInt64 {
        value.unicodeScalars.reduce(5_381) { partialResult, scalar in
            ((partialResult << 5) &+ partialResult) &+ UInt64(scalar.value)
        }
    }
}
