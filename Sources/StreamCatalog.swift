import Foundation
import os

struct StreamCatalog: Equatable {
    let schemaVersion: Int
    let defaultStreamId: String
    let streams: [Stream]

    func stream(withId id: String) -> Stream? {
        streams.first(where: { $0.id == id })
    }
}

extension StreamCatalog {
    private static let logger = Logger(subsystem: "com.johncioni.codefm", category: "StreamCatalog")
    static let bundledResourceName = "streams"
    static let bundledResourceExtension = "json"

    private static let remoteURL = URL(string:
        "https://raw.githubusercontent.com/apparelmagic-johnc/codefm/main/Resources/streams.json"
    )!

    static func loadBundled() throws -> StreamCatalog {
        // In the .app, streams.json is shipped flat in Contents/Resources/ — see
        // build-app.sh. In SwiftPM (tests / `swift run`), it lives in the package
        // resource bundle. Try Bundle.main first so the .app codesign layout
        // doesn't need a nested loose bundle.
        let url = Bundle.main.url(
            forResource: bundledResourceName,
            withExtension: bundledResourceExtension
        ) ?? Bundle.module.url(
            forResource: bundledResourceName,
            withExtension: bundledResourceExtension
        )
        guard let url else {
            throw NSError(
                domain: "CodeFM.StreamCatalog", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Bundled streams.json missing"]
            )
        }
        let data = try Data(contentsOf: url)
        return try decode(from: data)
    }

    /// Tolerant top-level decode. Top-level fields and `streams` array are required;
    /// individual stream entries that fail to decode are logged and dropped.
    static func decode(from data: Data) throws -> StreamCatalog {
        let raw = try JSONDecoder().decode(RawCatalog.self, from: data)
        let parsedStreams: [Stream] = raw.streams.compactMap { rawValue in
            do {
                return try JSONDecoder().decode(Stream.self, from: rawValue)
            } catch {
                logger.warning("Skipping malformed stream entry: \(error.localizedDescription)")
                return nil
            }
        }
        return StreamCatalog(
            schemaVersion: raw.schemaVersion,
            defaultStreamId: raw.defaultStreamId,
            streams: parsedStreams
        )
    }

    /// Cache location: ~/Library/Application Support/Code FM/streams.json
    static var cacheURL: URL {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first!
        let dir = appSupport.appendingPathComponent("Code FM", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("streams.json")
    }

    /// Load with the bundled→cache→remote precedence described in the spec.
    /// - Synchronous: returns the best available catalog right now (cache if present, else bundled).
    /// - Triggers a background remote refresh; on success, writes to cache and posts `catalogDidUpdate`.
    static func loadAtLaunch(completion: ((StreamCatalog) -> Void)? = nil) -> StreamCatalog {
        let current: StreamCatalog
        let cached = try? loadFromCache()
        let bundled = try? loadBundled()

        // Prefer the cache only when it's at least as fresh as the bundled file.
        // Without this check, an app-update that brings a fresher streams.json
        // is masked by yesterday's cache until the background remote refresh
        // wins the race.
        if let cached, isCacheFresherThanBundle() {
            current = cached
        } else if let bundled {
            current = bundled
        } else if let cached {
            current = cached
        } else {
            preconditionFailure("Code FM is missing its bundled stream catalog")
        }

        refreshRemoteInBackground { updated in
            completion?(updated ?? current)
        }

        return current
    }

    private static func isCacheFresherThanBundle() -> Bool {
        guard
            let bundleURL = Bundle.main.url(
                forResource: bundledResourceName,
                withExtension: bundledResourceExtension
            ) ?? Bundle.module.url(
                forResource: bundledResourceName,
                withExtension: bundledResourceExtension
            ),
            let cacheAttrs = try? FileManager.default.attributesOfItem(atPath: cacheURL.path),
            let bundleAttrs = try? FileManager.default.attributesOfItem(atPath: bundleURL.path),
            let cacheDate = cacheAttrs[.modificationDate] as? Date,
            let bundleDate = bundleAttrs[.modificationDate] as? Date
        else {
            // Conservative: if we can't compare, fall through to bundled.
            return false
        }
        return cacheDate >= bundleDate
    }

    private static func loadFromCache() throws -> StreamCatalog {
        let data = try Data(contentsOf: cacheURL)
        return try decode(from: data)
    }

    private static func refreshRemoteInBackground(_ done: @escaping (StreamCatalog?) -> Void) {
        var request = URLRequest(url: remoteURL)
        request.timeoutInterval = 5
        // GitHub raw sets cache-control: max-age=300 — without bypassing the
        // local URLCache, the second launch of a session can replay a stale
        // body and silently drop catalog changes that just shipped.
        request.cachePolicy = .reloadIgnoringLocalCacheData
        URLSession.shared.dataTask(with: request) { data, response, _ in
            guard
                let data,
                let http = response as? HTTPURLResponse, http.statusCode == 200,
                let catalog = try? decode(from: data)
            else {
                done(nil)
                return
            }
            try? data.write(to: cacheURL)
            DispatchQueue.main.async { done(catalog) }
        }.resume()
    }

    private struct RawCatalog: Decodable {
        let schemaVersion: Int
        let defaultStreamId: String
        let streams: [Data]

        private enum CodingKeys: String, CodingKey {
            case schemaVersion, defaultStreamId, streams
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            self.schemaVersion = try c.decode(Int.self, forKey: .schemaVersion)
            self.defaultStreamId = try c.decode(String.self, forKey: .defaultStreamId)

            // Re-serialize each stream object as Data so individual decode failures
            // throw locally inside decode(from:) and can be skipped without losing
            // the rest of the catalog.
            var arrayContainer = try c.nestedUnkeyedContainer(forKey: .streams)
            var rawStreams: [Data] = []
            while !arrayContainer.isAtEnd {
                let dict = try arrayContainer.decode(AnyDecodableDict.self)
                let data = try JSONSerialization.data(withJSONObject: dict.value, options: [])
                rawStreams.append(data)
            }
            self.streams = rawStreams
        }
    }

    /// Helper that captures a JSON object as a `[String: Any]` so it can be re-serialized
    /// and decoded independently per entry (enables per-entry tolerance).
    private struct AnyDecodableDict: Decodable {
        let value: [String: Any]
        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let dict = try? container.decode([String: AnyCodable].self) {
                self.value = dict.mapValues(\.value)
            } else {
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "Expected JSON object for stream entry"
                )
            }
        }
    }

    private struct AnyCodable: Decodable {
        let value: Any
        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if container.decodeNil() {
                self.value = NSNull()
            } else if let b = try? container.decode(Bool.self) {
                self.value = b
            } else if let i = try? container.decode(Int.self) {
                self.value = i
            } else if let d = try? container.decode(Double.self) {
                self.value = d
            } else if let s = try? container.decode(String.self) {
                self.value = s
            } else if let a = try? container.decode([AnyCodable].self) {
                self.value = a.map(\.value)
            } else if let o = try? container.decode([String: AnyCodable].self) {
                self.value = o.mapValues(\.value)
            } else {
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "Unsupported JSON value"
                )
            }
        }
    }
}
