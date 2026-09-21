import SwiftUI
import ModelSwitchboardCore

/// Kind-scoped form bindings: read/write only the active connection payload.
/// A text field can never write into the other kind's (nonexistent) fields.
enum GatewayConnectionField {
    static func bind<Payload, Value>(
        _ editing: Binding<GatewayConfig>,
        extract: @escaping (GatewayConfig.Connection) -> Payload?,
        embed: @escaping (Payload) -> GatewayConfig.Connection,
        _ keyPath: WritableKeyPath<Payload, Value>,
        fallback: Value
    ) -> Binding<Value> {
        Binding(
            get: {
                guard let payload = extract(editing.wrappedValue.connection) else {
                    return fallback
                }
                return payload[keyPath: keyPath]
            },
            set: { newValue in
                var value = editing.wrappedValue
                guard var payload = extract(value.connection) else { return }
                payload[keyPath: keyPath] = newValue
                value.connection = embed(payload)
                editing.wrappedValue = value
            }
        )
    }
}
