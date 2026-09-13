import Testing
@testable import MondayMetal

@Test func activeMorphsPreserveSourceOrderAndEveryNonzeroWeight() {
    let weights: [String: Float] = ["eye": 0.25, "brow": -0.5, "neutral": 0, "tiny": 0.00000001, "unrelated": 1]
    #expect(MorphInfluence.active(names: ["eye", "neutral", "missing", "brow", "tiny"], weights: weights) == [
        MorphInfluence(index: 0, weight: 0.25),
        MorphInfluence(index: 3, weight: -0.5),
        MorphInfluence(index: 4, weight: 0.00000001)
    ])
    #expect(MorphInfluence.active(names: ["eye"], weights: [:]).isEmpty)
    #expect(MemoryLayout<MorphInfluence>.stride == 8)
}
