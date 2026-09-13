import Foundation

public enum MondayMotionExporter {
    public static func export(bundle: UnityAssetBundle, identifier: String) throws -> Data {
        let clips = bundle.assets.objects.filter { $0.className == "AnimationClip" }
        guard clips.count == 1 else { throw UnityExportError.invalid("Required motion is ambiguous") }
        let clip = try bundle.assets.value(for: clips[0])
        let muscle = try clip.required("m_MuscleClip")
        let start = try muscle.requiredNumber("m_StartTime")
        let stop = try muscle.requiredNumber("m_StopTime")
        let duration = stop - start
        let fps = try clip.requiredNumber("m_SampleRate")
        guard start.isFinite, stop.isFinite, duration > 0, duration <= 3_600, fps > 0, fps <= 1_000 else {
            throw UnityExportError.invalid("motion timing")
        }
        let frameCount = Int((duration * fps).rounded(.toNearestOrEven)) + 1
        guard frameCount >= 2, frameCount <= 100_000 else { throw UnityExportError.invalid("motion frame count") }
        let sampler = try MotionSampler(clip: clip)
        let frames = try (0..<frameCount).map { frame in
            let time = start + duration * Double(frame) / Double(frameCount - 1)
            return try (7...136).map { attribute in
                let value = try sampler.value(attribute: attribute, time: time)
                guard value.isFinite else { throw UnityExportError.invalid("motion sample") }
                return roundedSix(value)
            }
        }
        let short = String(identifier.prefix { $0 != "_" })
        let label = short == "idle01" ? "Idle" : short == "run00" ? "Run" : short
        let loop = muscle["m_LoopTime"] == .bool(true)
        let payload = MotionPayload(id: identifier, name: try clip.requiredString("m_Name"), label: label, short: short,
                                    duration: roundedSix(duration), loop: loop, file: identifier + ".json", fps: fps,
                                    frames: frames)
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return try encoder.encode(payload) + Data("\n".utf8)
    }
}

private struct MotionPayload: Encodable {
    let id: String
    let name: String
    let label: String
    let short: String
    let duration: Double
    let loop: Bool
    let file: String
    let fps: Double
    let frames: [[Double]]
}

private func roundedSix(_ value: Double) -> Double {
    Double(String(format: "%.6f", locale: Locale(identifier: "en_US_POSIX"), value))!
}

private struct MotionSampler {
    let streamed: [Int: [(time: Double, coefficients: [Double])]]
    let denseBegin: Double
    let denseRate: Double
    let denseFrames: Int
    let denseCount: Int
    let denseSamples: [Double]
    let constant: [Double]
    let streamCount: Int
    let slots: [Int: Int]

    init(clip: UnityValue) throws {
        let data = try clip.required("m_MuscleClip").required("m_Clip").required("data")
        let streamedValue = try data.required("m_StreamedClip")
        let dense = try data.required("m_DenseClip")
        let words = try streamedValue.requiredArray("data").map {
            guard let value = $0.unsigned ?? $0.signed.map(UInt64.init(bitPattern:)) else { throw UnityExportError.invalid("stream word") }
            return UInt32(truncatingIfNeeded: value)
        }
        var keys: [Int: [(Double, [Double])]] = [:]
        var offset = 0
        while offset < words.count {
            guard offset + 2 <= words.count else { throw UnityExportError.invalid("stream header") }
            let time = Double(Float(bitPattern: words[offset]))
            let count = Int(words[offset + 1])
            offset += 2
            guard count <= (words.count - offset) / 5 else { throw UnityExportError.invalid("stream keys") }
            for _ in 0..<count {
                let slot = Int(words[offset])
                let coefficients = (1...4).map { Double(Float(bitPattern: words[offset + $0])) }
                guard time.isFinite, coefficients.allSatisfy(\.isFinite) else { throw UnityExportError.invalid("stream sample") }
                keys[slot, default: []].append((time, coefficients))
                offset += 5
            }
        }
        streamCount = try streamedValue.requiredInt("curveCount")
        denseCount = try dense.requiredInt("m_CurveCount")
        denseFrames = try dense.requiredInt("m_FrameCount")
        denseBegin = try dense.requiredNumber("m_BeginTime")
        denseRate = try dense.requiredNumber("m_SampleRate")
        denseSamples = try dense.requiredArray("m_SampleArray").map {
            guard let number = $0.number, number.isFinite else { throw UnityExportError.invalid("dense sample") }
            return number
        }
        constant = try data.required("m_ConstantClip").requiredArray("data").map {
            guard let number = $0.number, number.isFinite else { throw UnityExportError.invalid("constant sample") }
            return number
        }
        guard streamCount >= 0, denseCount >= 0, denseFrames > 0, denseRate > 0,
              denseCount == 0 || denseFrames <= denseSamples.count / denseCount else {
            throw UnityExportError.invalid("dense clip")
        }
        var slots: [Int: Int] = [:]
        var slot = 0
        for binding in try clip.required("m_ClipBindingConstant").requiredArray("genericBindings") {
            let attribute = try binding.requiredInt("attribute")
            let typeID = try binding.requiredInt("typeID")
            if typeID == 95 { slots[attribute] = slot }
            slot += typeID == 4 ? (attribute == 2 ? 4 : 3) : 1
        }
        guard slot == streamCount + denseCount + constant.count else { throw UnityExportError.invalid("motion bindings") }
        self.streamed = keys
        self.slots = slots
    }

    func value(attribute: Int, time: Double) throws -> Double {
        guard let index = slots[attribute] else { return 0 }
        if index < streamCount {
            guard let values = streamed[index], !values.isEmpty else { throw UnityExportError.invalid("stream curve") }
            let key = max(0, values.partitioningIndex { $0.time > time } - 1)
            let entry = values[key]
            let dt = max(0, time - entry.time)
            let c = entry.coefficients
            return ((c[0] * dt + c[1]) * dt + c[2]) * dt + c[3]
        }
        if index < streamCount + denseCount {
            let frame = min(max((time - denseBegin) * denseRate, 0), Double(denseFrames - 1))
            let first = Int(floor(frame))
            let second = min(first + 1, denseFrames - 1)
            let column = index - streamCount
            guard first * denseCount + column < denseSamples.count, second * denseCount + column < denseSamples.count else {
                throw UnityExportError.invalid("dense curve")
            }
            let fraction = frame - Double(first)
            let firstValue = denseSamples[first * denseCount + column]
            let secondValue = denseSamples[second * denseCount + column]
            return firstValue + (secondValue - firstValue) * fraction
        }
        let constantIndex = index - streamCount - denseCount
        guard constant.indices.contains(constantIndex) else { throw UnityExportError.invalid("constant curve") }
        return constant[constantIndex]
    }
}

private extension Array {
    func partitioningIndex(where predicate: (Element) -> Bool) -> Int {
        var lower = 0
        var upper = count
        while lower < upper {
            let middle = (lower + upper) / 2
            if predicate(self[middle]) { upper = middle } else { lower = middle + 1 }
        }
        return lower
    }
}
