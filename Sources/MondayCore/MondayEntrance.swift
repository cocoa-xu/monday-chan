import Foundation

public enum MondayEntrance {
    public static let duration: Double = 0.55

    public static func offset(at time: Double) -> Float {
        let stops: [(Double, Float)] = [(0, -2.05), (0.12, -1.15), (0.17, -1.15),
                                       (0.22, -1.28), (0.42, 0.1), (duration, 0)]
        guard time > 0 else { return stops[0].1 }
        for index in 1..<stops.count where time < stops[index].0 {
            let (start, from) = stops[index - 1]
            let (end, to) = stops[index]
            let phase = Float((time - start) / (end - start))
            let eased = phase * phase * (3 - 2 * phase)
            return from + (to - from) * eased
        }
        return 0
    }
}
