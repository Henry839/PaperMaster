import Combine
import SwiftUI

@propertyWrapper
struct ObservationIgnored<Value> {
    var wrappedValue: Value

    init(wrappedValue: Value) {
        self.wrappedValue = wrappedValue
    }
}

#if PAPERMASTER_LEGACY_MODE
@propertyWrapper
struct Bindable<ObjectType>: DynamicProperty where ObjectType: ObservableObject {
    @ObservedObject private var object: ObjectType

    init(wrappedValue: ObjectType) {
        _object = ObservedObject(wrappedValue: wrappedValue)
    }

    var wrappedValue: ObjectType {
        object
    }

    var projectedValue: Wrapper {
        Wrapper(object: object)
    }

    @dynamicMemberLookup
    struct Wrapper {
        fileprivate let object: ObjectType

        subscript<Subject>(dynamicMember keyPath: ReferenceWritableKeyPath<ObjectType, Subject>) -> Binding<Subject> {
            Binding(
                get: { object[keyPath: keyPath] },
                set: { object[keyPath: keyPath] = $0 }
            )
        }
    }
}
#endif
