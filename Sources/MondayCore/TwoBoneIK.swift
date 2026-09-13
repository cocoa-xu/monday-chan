import simd

public enum TwoBoneIK {
    public static func elbow(root: Vector3, target: Vector3, pole: Vector3, upperLength: Float, lowerLength: Float) -> Vector3 {
        let difference = target - root
        let direction = simd_length(difference) > 0.00001 ? simd_normalize(difference) : Vector3(0, -1, 0)
        let distance = min(max(simd_length(difference), abs(upperLength - lowerLength) + 0.00001), upperLength + lowerLength - 0.00001)
        let along = (upperLength * upperLength + distance * distance - lowerLength * lowerLength) / (2 * distance)
        let height = sqrt(max(0, upperLength * upperLength - along * along))
        var perpendicular = pole - direction * simd_dot(pole, direction)
        if simd_length(perpendicular) < 0.00001 {
            perpendicular = simd_cross(direction, abs(direction.x) < 0.9 ? Vector3(1, 0, 0) : Vector3(0, 0, 1))
        }
        return root + direction * along + simd_normalize(perpendicular) * height
    }
}
