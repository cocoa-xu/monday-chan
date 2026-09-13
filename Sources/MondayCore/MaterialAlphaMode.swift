public enum MaterialAlphaMode: UInt32, Decodable, Sendable {
    case opaque = 0
    case mask = 1
    case blend = 2

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        switch try container.decode(String.self) {
        case "OPAQUE": self = .opaque
        case "MASK": self = .mask
        case "BLEND": self = .blend
        default: throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported material alpha mode")
        }
    }
}
