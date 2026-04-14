#if PAPERMASTER_LEGACY_MODE
import SwiftUI

struct ContentUnavailableView<Description: View>: View {
    private let title: String
    private let systemImage: String
    private let description: Description

    init(
        _ title: String,
        systemImage: String,
        description: Description
    ) {
        self.title = title
        self.systemImage = systemImage
        self.description = description
    }

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: systemImage)
                .font(.system(size: 34, weight: .medium))
                .foregroundStyle(.secondary)

            Text(title)
                .font(.title3.weight(.semibold))

            description
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }
}

private struct LegacyOnChangeModifier<Value: Equatable>: ViewModifier {
    let value: Value
    let initial: Bool
    let action: (Value, Value) -> Void

    @State private var previousValue: Value?

    func body(content: Content) -> some View {
        content
            .onAppear {
                guard previousValue == nil else { return }
                previousValue = value

                if initial {
                    action(value, value)
                }
            }
            .onChange(of: value) { newValue in
                let oldValue = previousValue ?? newValue
                previousValue = newValue
                action(oldValue, newValue)
            }
    }
}

extension View {
    func onChange<Value: Equatable>(
        of value: Value,
        initial: Bool = false,
        _ action: @escaping (Value, Value) -> Void
    ) -> some View {
        modifier(
            LegacyOnChangeModifier(
                value: value,
                initial: initial,
                action: action
            )
        )
    }
}
#endif
