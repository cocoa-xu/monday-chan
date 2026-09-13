import Metal
public enum MetalSupport {
    public static var available: Bool { MTLCreateSystemDefaultDevice() != nil }
}
