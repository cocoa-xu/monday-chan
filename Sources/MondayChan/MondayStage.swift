import MondayCore
import MondayMetal

enum MondayStage {
    private static let exitTimelineDuration: Double = 1.9
    static let exitDuration: Double = 0.5

    static func camera(bounds: Bounds3, aspect: Float, time: Double) -> RenderCamera {
        var camera = RenderCamera(bounds: bounds)
        camera.fit(aspect: aspect)
        let closeup = pulse(time, start: 2.5, hold: 3.1, release: 3.8, end: 4.5)
            + pulse(time, start: 7.5, hold: 8.0, release: 8.6, end: 9.3) * 0.8
        let horizontal = MondayHopTimeline.sample(at: Float(time)).horizontal
        let focus = Vector3(horizontal, bounds.minimum.y + bounds.size.y * 0.6, bounds.center.z)
        let shift = (focus - bounds.center) * closeup
        camera.bounds.minimum += shift
        camera.bounds.maximum += shift
        camera.zoom *= 1 + closeup
        return camera
    }

    static func exitCamera(bounds: Bounds3, exitBounds: Bounds3, aspect: Float, time: Double) -> RenderCamera {
        let timelineTime = time / exitDuration * exitTimelineDuration
        var camera = camera(bounds: bounds, aspect: aspect, time: 0)
        camera.yaw = -.pi / 2
        let projection = camera.matrix(aspect: aspect)
        var leftmost = Float.infinity
        for x in [exitBounds.minimum.x, exitBounds.maximum.x] {
            for y in [exitBounds.minimum.y, exitBounds.maximum.y] {
                for z in [exitBounds.minimum.z, exitBounds.maximum.z] {
                    leftmost = min(leftmost, projection.point(Vector3(x, y, z)).x)
                }
            }
        }
        camera.yaw *= smooth(Float(timelineTime / 0.3))
        let progress = min(max(Float((timelineTime - 0.15) / (exitTimelineDuration - 0.15)), 0), 1)
        let travel = (progress < 0.15 ? progress * progress / 0.3 : progress - 0.075) / 0.925
        camera.presentationOffset.x = (1.1 - leftmost) * travel
        return camera
    }

    static func exitPose(performance: MondayPerformance, time: Double) -> [Transform] {
        let running = performance.exitMotion.pose(at: Float(time))
        let blend = smooth(Float(time / 0.25))
        guard blend < 1 else { return running }
        let final = performance.motion.pose(at: performance.motion.duration)
        return zip(final, running).map { Transform.blend($0, $1, fraction: blend) }
    }

    private static func pulse(_ time: Double, start: Double, hold: Double, release: Double, end: Double) -> Float {
        smooth(Float((time - start) / (hold - start))) * (1 - smooth(Float((time - release) / (end - release))))
    }

    private static func smooth(_ value: Float) -> Float {
        let value = min(max(value, 0), 1)
        return value * value * (3 - 2 * value)
    }
}
