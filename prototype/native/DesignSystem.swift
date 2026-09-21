import SwiftUI

struct Hairline: View {
    var body: some View { Rectangle().fill(Palette.line).frame(height: 1) }
}

struct QuietButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(Rectangle())
            .opacity(!enabled ? 0.4 : configuration.isPressed ? 0.6 : 1)
    }
}

struct ActionButtonStyle: ButtonStyle {
    var primary = true
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .semibold))
            .frame(maxWidth: .infinity).padding(.vertical, 12).padding(.horizontal, 14)
            .foregroundStyle(primary && enabled ? Color.white : enabled ? Palette.accent : Palette.secondary)
            .background(enabled ? (primary ? Palette.accent : Palette.surface) : Palette.elevated,
                        in: RoundedRectangle(cornerRadius: 9))
            .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(primary ? Color.clear : Palette.line))
            .opacity(configuration.isPressed ? 0.78 : 1)
            .contentShape(RoundedRectangle(cornerRadius: 9))
    }
}

struct IconButton: View {
    let symbol: String
    let label: String
    let action: () -> Void
    @State private var hovering = false
    var body: some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 14, weight: .medium))
                .foregroundStyle(Palette.secondary).frame(width: 32, height: 32)
                .background(hovering ? Palette.elevated : .clear, in: RoundedRectangle(cornerRadius: 7))
        }.buttonStyle(QuietButtonStyle()).onHover { hovering = $0 }
            .help(label).accessibilityLabel(label)
    }
}

struct SectionHeading: View {
    let title: String
    var trailing = ""
    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.system(size: 14, weight: .semibold)).foregroundStyle(Palette.text)
            Spacer(minLength: 8)
            if !trailing.isEmpty { Text(trailing).font(.system(size: 12)).foregroundStyle(Palette.secondary) }
        }
    }
}

struct PageIntro: View {
    let title: String
    let subtitle: String
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title).font(.system(size: 25, weight: .semibold)).tracking(-0.5)
            Text(subtitle).font(.system(size: 14)).foregroundStyle(Palette.secondary).lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct Tag: View {
    let text: String
    var color = Palette.accent
    var body: some View {
        Text(text).font(.system(size: 11, weight: .medium)).foregroundStyle(color)
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(color.opacity(0.08), in: RoundedRectangle(cornerRadius: 5))
            .fixedSize()
    }
}

struct ProjectMark: View {
    let name: String
    var body: some View {
        Text(String(name.prefix(1)).uppercased()).font(.system(size: 16, weight: .medium, design: .serif))
            .foregroundStyle(Palette.accent).frame(width: 34, height: 34)
            .background(Palette.accentWash, in: RoundedRectangle(cornerRadius: 9))
            .accessibilityHidden(true)
    }
}

struct TabStrip: View {
    let items: [String]
    @Binding var selected: String
    var body: some View {
        HStack(spacing: 24) {
            ForEach(items, id: \.self) { item in
                Button { selected = item } label: {
                    VStack(spacing: 11) {
                        Text(item).font(.system(size: 13, weight: selected == item ? .semibold : .regular))
                            .foregroundStyle(selected == item ? Palette.accent : Palette.secondary)
                        Capsule().fill(selected == item ? Palette.accent : .clear).frame(height: 2)
                    }.fixedSize(horizontal: true, vertical: false).contentShape(Rectangle())
                }.accessibilityAddTraits(selected == item ? .isSelected : [])
            }
            Spacer(minLength: 0)
        }.overlay(alignment: .bottom) { Hairline().offset(y: 1) }
    }
}

struct EmptyState: View {
    let symbol: String
    let title: String
    let detail: String
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: symbol).font(.system(size: 23, weight: .light)).foregroundStyle(Palette.accent)
                .frame(width: 52, height: 52).background(Palette.accentWash, in: RoundedRectangle(cornerRadius: 15))
            Text(title).font(.system(size: 17, weight: .medium))
            Text(detail).font(.system(size: 14)).foregroundStyle(Palette.secondary)
                .multilineTextAlignment(.center).lineSpacing(3).frame(maxWidth: 280)
        }.frame(maxWidth: .infinity).padding(.vertical, 36)
    }
}

struct HoverRow<Content: View>: View {
    @ViewBuilder let content: Content
    @State private var hovering = false
    var body: some View {
        content.padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .background(hovering ? Palette.accentWash.opacity(0.6) : Palette.surface)
            .contentShape(Rectangle()).onHover { hovering = $0 }
    }
}
