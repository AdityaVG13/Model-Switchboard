import SwiftUI

/// Shared Settings chrome. Screens pass labels and bindings; they do not
/// restyle QuietCraft / DashboardTheme per form.
enum SettingsChrome {
    static let rowInsets = EdgeInsets(top: 9, leading: 12, bottom: 9, trailing: 12)

    static func optionalString(_ binding: Binding<String?>) -> Binding<String> {
        Binding(
            get: { binding.wrappedValue ?? "" },
            set: { binding.wrappedValue = $0.isEmpty ? nil : $0 }
        )
    }
}

struct SettingsGroup<Content: View>: View {
    let title: String
    let theme: DashboardTheme
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            DashboardSectionLabel(text: title, theme: theme)
                .padding(.horizontal, 4)
            VStack(alignment: .leading, spacing: 0) {
                content
            }
            .background(theme.cellBg, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }
}

struct SettingsRow<Trailing: View>: View {
    let label: String
    let theme: DashboardTheme
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 12.5))
                .foregroundStyle(theme.label)
            Spacer()
            trailing
        }
        .padding(SettingsChrome.rowInsets)
    }
}

struct SettingsDivider: View {
    let theme: DashboardTheme

    var body: some View {
        theme.line
            .frame(height: 1)
            .padding(.horizontal, 12)
    }
}

struct SettingsLinkButton: View {
    let title: String
    var emphasized: Bool = false
    let theme: DashboardTheme
    let accent: Color
    let action: () -> Void

    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11.5, weight: emphasized ? .semibold : .regular))
                .contentShape(Rectangle())
        }
        .buttonStyle(QuietCraftPressStyle())
        .foregroundStyle(isEnabled ? (emphasized ? accent : theme.btnFg) : theme.faint)
    }
}

struct SettingsTextField: View {
    let label: String
    @Binding var text: String
    var prompt: String
    var monospaced: Bool = false
    let theme: DashboardTheme

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 12.5))
                .foregroundStyle(theme.label)
            TextField(prompt, text: $text)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 11.5, design: monospaced ? .monospaced : .default))
                .foregroundStyle(theme.fieldFg)
        }
    }
}

struct SettingsSecureField: View {
    let label: String
    @Binding var text: String
    var prompt: String
    let theme: DashboardTheme

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 12.5))
                .foregroundStyle(theme.label)
            SecureField(prompt, text: $text)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 11.5, design: .monospaced))
                .foregroundStyle(theme.fieldFg)
        }
    }
}

struct SettingsNumberField: View {
    let label: String
    @Binding var value: Int
    let theme: DashboardTheme

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 12.5))
                .foregroundStyle(theme.label)
            TextField(
                "",
                text: Binding(
                    get: { String(value) },
                    set: { value = Int($0) ?? value }
                )
            )
            .textFieldStyle(.roundedBorder)
            .font(.system(size: 11.5, design: .monospaced))
            .foregroundStyle(theme.fieldFg)
            .frame(width: 90)
        }
    }
}

struct SettingsFootnote: View {
    let text: String
    var color: Color

    var body: some View {
        Text(text)
            .font(.system(size: 10.5))
            .foregroundStyle(color)
            .fixedSize(horizontal: false, vertical: true)
    }
}

struct SettingsToggleRow: View {
    let label: String
    let subtitle: String
    @Binding var isOn: Bool
    var disabled: Bool = false
    let theme: DashboardTheme
    let accent: Color

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                    .font(.system(size: 12.5))
                    .foregroundStyle(theme.label)
                Text(subtitle)
                    .font(.system(size: 10.5))
                    .foregroundStyle(theme.sub)
            }
            Spacer()
            Toggle("", isOn: $isOn)
                .toggleStyle(.switch)
                .controlSize(.small)
                .labelsHidden()
                .tint(accent)
                .disabled(disabled)
                .accessibilityLabel(label)
        }
    }
}

struct SettingsSegmentedControl<Option: Hashable>: View {
    let options: [Option]
    let label: (Option) -> String
    @Binding var selection: Option
    let theme: DashboardTheme

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.self) { option in
                let isOn = selection == option
                Button {
                    selection = option
                } label: {
                    Text(label(option))
                        .font(.system(size: 11, weight: isOn ? .semibold : .regular))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .frame(minHeight: 24)
                        .background(
                            isOn ? theme.tabOnBg : Color.clear,
                            in: RoundedRectangle(cornerRadius: 5, style: .continuous)
                        )
                        .foregroundStyle(isOn ? theme.tabOnFg : theme.tabOffFg)
                        .contentShape(Rectangle())
                }
                .buttonStyle(QuietCraftPressStyle())
                .accessibilityLabel(label(option))
                .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : .isButton)
            }
        }
        .padding(2)
        .background(theme.btnBg, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        .accessibilityElement(children: .contain)
    }
}
