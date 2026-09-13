import Foundation
import AppKit
import MondayCore
import MondayMetal
import simd
import Testing

@Test(.enabled(if: localAssetsAvailable)) @MainActor func boardIsAbsentUntilAttachedAndCanBeHidden() throws {
    let library = try AssetLibrary(root: URL(fileURLWithPath: "data"))
    let model = try CharacterModel(url: library.url(for: "models/06002.glb"))
    let renderer = try CharacterRenderer(model: model)
    #expect(renderer.boardAttachment == nil)
    let baseline = try renderer.snapshot(width: 240, height: 320)
    let skinJoints = Set(model.skins.flatMap(\.joints))
    let locator = try #require(model.nodes.enumerated().first {
        $0.element.name.hasPrefix("loc_") && $0.element.children.isEmpty && !skinJoints.contains($0.offset)
    })
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 2, pixelsHigh: 2, bitsPerSample: 8, samplesPerPixel: 4,
                                  hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 8, bitsPerPixel: 32)!
    bitmap.bitmapData?.initialize(repeating: 255, count: 16)
    let png = try #require(bitmap.representation(using: .png, properties: [:]))
    let attachment = BoardAttachment(anchorNode: locator.element.name, size: SIMD2(0.65, 0.325), offset: SIMD3(0, 0.8, 0.22))
    try renderer.attachBoard(textureData: png, attachment: attachment)
    #expect(renderer.boardAttachment == attachment)
    let visible = try renderer.snapshot(width: 240, height: 320)
    renderer.boardAttachment = nil
    #expect(renderer.boardAttachment?.isVisible == false)
    let hidden = try renderer.snapshot(width: 240, height: 320)
    #expect(visible != hidden)
    #expect(hidden == baseline)
    renderer.boardAttachment = attachment
    let anchor = try #require(renderer.rig.node(attachment.anchorNode))
    let parent = renderer.rig.parents[anchor].map { renderer.rig.world[$0] } ?? matrix_identity_float4x4
    renderer.rig.pose[anchor].translation += simd_inverse(parent).direction(Vector3(0.15, 0, 0))
    let moved = try renderer.snapshot(width: 240, height: 320)
    #expect(moved != visible)
}

@Test(.enabled(if: localAssetsAvailable)) @MainActor func attachmentPlacementDoesNotDependOnPoseAtLoadTime() throws {
    let library = try AssetLibrary(root: URL(fileURLWithPath: "data"))
    let model = try CharacterModel(url: library.url(for: "models/06002.glb"))
    let early = try CharacterRenderer(model: model)
    let late = try CharacterRenderer(model: model)
    let anchorName = "jnt_C_spine00_01"
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 2, pixelsHigh: 2, bitsPerSample: 8, samplesPerPixel: 4,
                                  hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 8, bitsPerPixel: 32)!
    bitmap.bitmapData?.initialize(repeating: 255, count: 16)
    let png = try #require(bitmap.representation(using: .png, properties: [:]))
    let attachment = BoardAttachment(anchorNode: anchorName, size: SIMD2(0.65, 0.325), offset: SIMD3(0, 0.8, 0.22))
    try early.attachBoard(textureData: png, attachment: attachment)
    let anchor = try #require(early.rig.node(anchorName))
    early.rig.pose[anchor].rotation = simd_mul(early.rig.pose[anchor].rotation, Quaternion(angle: 0.35, axis: SIMD3(0, 1, 0)))
    late.rig.pose[anchor] = early.rig.pose[anchor]
    try late.attachBoard(textureData: png, attachment: attachment)
    let earlyPixels = try early.snapshot(width: 240, height: 320)
    let latePixels = try late.snapshot(width: 240, height: 320)
    #expect(earlyPixels == latePixels)
}
