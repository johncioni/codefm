import Foundation

enum RandomPicker {
    /// Uniformly picks a stream from the catalog.
    /// Precondition: `catalog.streams` is non-empty (enforced — empty catalogs are a hard build error per spec).
    static func pick(from catalog: StreamCatalog) -> Stream {
        precondition(!catalog.streams.isEmpty, "Catalog must contain at least one stream")
        return catalog.streams.randomElement()!
    }
}

enum DefaultStreamResolver {
    static let randomSentinel = "random"

    /// Decide which stream should play on launch / when the player needs a default.
    /// Precedence: user override (if present and valid) → catalog's `defaultStreamId` → first stream.
    /// The sentinel string `"random"` triggers a random pick.
    static func resolve(catalog: StreamCatalog, userDefaultId: String?) -> Stream {
        if let userDefaultId {
            if userDefaultId == randomSentinel {
                return RandomPicker.pick(from: catalog)
            }
            if let match = catalog.stream(withId: userDefaultId) {
                return match
            }
        }
        if let catalogDefault = catalog.stream(withId: catalog.defaultStreamId) {
            return catalogDefault
        }
        return catalog.streams.first!  // precondition: catalog is non-empty
    }
}
