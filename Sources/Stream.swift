import Foundation

enum Subgenre: String, Codable {
    case lofi
    case jazzhop
    case synthwave
    case ambient
    case brand
    case other

    /// Tolerant decoding — unknown values map to `.other` rather than throwing.
    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = Subgenre(rawValue: raw) ?? .other
    }

    var displayName: String {
        switch self {
        case .lofi: return "Lo-fi"
        case .jazzhop: return "Jazzhop"
        case .synthwave: return "Synthwave"
        case .ambient: return "Ambient"
        case .brand: return "Brand"
        case .other: return "Other"
        }
    }
}

enum StreamType {
    case youtubeLive(videoId: String, channelLiveUrl: URL)
    case directAudio(url: URL)
}

struct Attribution: Codable, Equatable {
    let artist: String
    let website: URL
}

struct Stream: Identifiable, Equatable {
    let id: String
    let displayName: String
    let subgenre: Subgenre
    let type: StreamType
    let attribution: Attribution
    let description: String
    let providerLabel: String

    static func == (lhs: Stream, rhs: Stream) -> Bool { lhs.id == rhs.id }
}

extension Stream: Decodable {
    private enum CodingKeys: String, CodingKey {
        case id, displayName, subgenre, type
        case videoId, channelLiveUrl, url
        case attribution, description, providerLabel
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(String.self, forKey: .id)
        self.displayName = try c.decode(String.self, forKey: .displayName)
        self.subgenre = try c.decode(Subgenre.self, forKey: .subgenre)
        self.attribution = try c.decode(Attribution.self, forKey: .attribution)
        self.description = try c.decode(String.self, forKey: .description)
        self.providerLabel = try c.decode(String.self, forKey: .providerLabel)

        let typeStr = try c.decode(String.self, forKey: .type)
        switch typeStr {
        case "youtube_live":
            let videoId = try c.decode(String.self, forKey: .videoId)
            let channelLiveUrl = try c.decode(URL.self, forKey: .channelLiveUrl)
            self.type = .youtubeLive(videoId: videoId, channelLiveUrl: channelLiveUrl)
        case "direct_audio":
            let url = try c.decode(URL.self, forKey: .url)
            self.type = .directAudio(url: url)
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type, in: c,
                debugDescription: "Unknown stream type '\(typeStr)'"
            )
        }
    }
}
