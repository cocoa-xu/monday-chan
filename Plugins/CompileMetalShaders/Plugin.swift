import Foundation
import PackagePlugin

@main
struct CompileMetalShaders: BuildToolPlugin {
    func createBuildCommands(context: PluginContext, target: Target) throws -> [Command] {
        let source = target.directoryURL.appendingPathComponent("Shaders/Character.metal")
        let library = context.pluginWorkDirectoryURL.appendingPathComponent("Character.metallib")
        return [.buildCommand(displayName: "Compile character shaders", executable: URL(fileURLWithPath: "/usr/bin/xcrun"),
                              arguments: ["-sdk", "macosx", "metal", "-std=metal3.1", "-mmacosx-version-min=14.0",
                                          source.path, "-o", library.path], inputFiles: [source], outputFiles: [library])]
    }
}
