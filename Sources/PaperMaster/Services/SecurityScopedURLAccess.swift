import Foundation

enum SecurityScopedURLAccess {
    static func bookmarkData(for url: URL) throws -> Data {
        #if os(iOS)
        return try url.bookmarkData(
            options: [],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        #else
        return try url.bookmarkData(
            options: [],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        #endif
    }

    static func withAccess<T>(to url: URL, perform operation: () throws -> T) rethrows -> T {
        #if os(iOS)
        let startedAccess = url.startAccessingSecurityScopedResource()
        defer {
            if startedAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }
        #endif
        return try operation()
    }
}
