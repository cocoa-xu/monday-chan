import simd

public typealias Vector3 = SIMD3<Float>
public typealias Matrix4 = simd_float4x4
public typealias Quaternion = simd_quatf

public struct Transform: Sendable {
    public var translation = Vector3.zero
    public var rotation = Quaternion(angle: 0, axis: Vector3(0, 1, 0))
    public var scale = Vector3(repeating: 1)

    public init(translation: Vector3 = .zero, rotation: Quaternion = Quaternion(angle: 0, axis: Vector3(0, 1, 0)), scale: Vector3 = Vector3(repeating: 1)) {
        self.translation = translation
        self.rotation = rotation
        self.scale = scale
    }

    public init(matrix: Matrix4) {
        translation = matrix.position
        scale = Vector3(simd_length(matrix.columns.0.xyz), simd_length(matrix.columns.1.xyz), simd_length(matrix.columns.2.xyz))
        if simd_determinant(matrix) < 0 { scale.x = -scale.x }
        rotation = Quaternion(simd_float3x3(columns: (matrix.columns.0.xyz / scale.x, matrix.columns.1.xyz / scale.y, matrix.columns.2.xyz / scale.z)))
    }

    public var matrix: Matrix4 {
        var result = Matrix4(rotation)
        result.columns.0 *= scale.x
        result.columns.1 *= scale.y
        result.columns.2 *= scale.z
        result.columns.3 = SIMD4(translation, 1)
        return result
    }

    public static func blend(_ a: Transform, _ b: Transform, fraction: Float) -> Transform {
        Transform(translation: simd_mix(a.translation, b.translation, Vector3(repeating: fraction)),
                  rotation: simd_slerp(a.rotation, b.rotation, fraction),
                  scale: simd_mix(a.scale, b.scale, Vector3(repeating: fraction)))
    }
}

public extension SIMD4 where Scalar == Float {
    var xyz: Vector3 { Vector3(x, y, z) }
}

public extension simd_float4x4 {
    var position: Vector3 { columns.3.xyz }
    func point(_ value: Vector3) -> Vector3 { (self * SIMD4(value, 1)).xyz }
    func direction(_ value: Vector3) -> Vector3 { (self * SIMD4(value, 0)).xyz }

    static func lookAt(eye: Vector3, target: Vector3, up: Vector3 = Vector3(0, 1, 0)) -> Matrix4 {
        let z = simd_normalize(eye - target)
        let x = simd_normalize(simd_cross(up, z))
        let y = simd_cross(z, x)
        return Matrix4(columns: (SIMD4(x.x, y.x, z.x, 0), SIMD4(x.y, y.y, z.y, 0),
                                 SIMD4(x.z, y.z, z.z, 0), SIMD4(-simd_dot(x, eye), -simd_dot(y, eye), -simd_dot(z, eye), 1)))
    }

    static func orthographic(width: Float, height: Float, near: Float, far: Float) -> Matrix4 {
        Matrix4(columns: (SIMD4(2 / width, 0, 0, 0), SIMD4(0, 2 / height, 0, 0),
                          SIMD4(0, 0, 1 / (near - far), 0), SIMD4(0, 0, near / (near - far), 1)))
    }
}

public struct Bounds3: Sendable {
    public var minimum = Vector3(repeating: .infinity)
    public var maximum = Vector3(repeating: -.infinity)
    public init() {}
    public var center: Vector3 { (minimum + maximum) * 0.5 }
    public var size: Vector3 { maximum - minimum }
    public mutating func include(_ point: Vector3) {
        minimum = simd_min(minimum, point)
        maximum = simd_max(maximum, point)
    }
}
