import Foundation
import PackagePlugin

@main
struct CompileMetalShaders: BuildToolPlugin {
    func createBuildCommands(context: PluginContext, target: Target) throws -> [Command] {
        let shaderDirectory = target.directoryURL.appendingPathComponent("Shaders")
        let sources = try FileManager.default.contentsOfDirectory(at: shaderDirectory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "metal" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        let library = context.pluginWorkDirectoryURL.appendingPathComponent(target.name + ".metallib")
        let arguments = ["-sdk", "macosx", "metal", "-std=metal3.1", "-mmacosx-version-min=14.0"]
            + sources.map(\.path) + ["-o", library.path]
        return [.buildCommand(displayName: "Compile \(target.name) shaders", executable: URL(fileURLWithPath: "/usr/bin/xcrun"),
                              arguments: arguments,
                              inputFiles: sources, outputFiles: [library])]
    }
}
