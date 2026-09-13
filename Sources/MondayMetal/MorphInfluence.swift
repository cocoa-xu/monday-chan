struct MorphInfluence: Equatable, Sendable {
    let index: UInt32
    let weight: Float

    static func active(names: [String], weights: [String: Float]) -> [MorphInfluence] {
        names.enumerated().compactMap { index, name in
            guard let weight = weights[name], weight != 0 else { return nil }
            return MorphInfluence(index: UInt32(index), weight: weight)
        }
    }
}
