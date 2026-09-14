import AVFoundation
import AVFAudio

enum MondayAudioImporter {
    private static let originalVideoRange = CMTimeRange(
        start: CMTime(value: 300_696, timescale: 48_000),
        duration: CMTime(value: 517_440, timescale: 48_000)
    )

    static func extractMonday(from source: URL, to destination: URL) async throws {
        let duration = try await AVURLAsset(url: source).load(.duration).seconds
        switch duration {
        case 9.5...12:
            try await extract(from: source, to: destination)
        case 20...22:
            try await extract(from: source, to: destination, timeRange: originalVideoRange, gain: 1.25)
        default:
            throw MondayImportError.unexpectedAudioDuration
        }
    }

    static func extract(from source: URL, to destination: URL,
                        timeRange: CMTimeRange? = nil, gain: Float = 1) async throws {
        let asset = AVURLAsset(url: source)
        let duration = try await asset.load(.duration).seconds
        guard duration.isFinite, duration > 0, duration <= 60,
              let track = try await asset.loadTracks(withMediaType: .audio).first,
              let description = try await track.load(.formatDescriptions).first else {
            throw MondayImportError.invalidMedia
        }
        let format = AVAudioFormat(cmAudioFormatDescription: description)
        let rate = format.sampleRate
        let channels = format.channelCount
        guard rate > 0, rate <= 192_000, channels > 0, channels <= 2,
              let pcm = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: rate,
                                      channels: channels, interleaved: true) else {
            throw MondayImportError.invalidMedia
        }
        let reader = try AVAssetReader(asset: asset)
        let trackOutput = AVAssetReaderTrackOutput(track: track, outputSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: rate, AVNumberOfChannelsKey: channels,
            AVLinearPCMIsFloatKey: true, AVLinearPCMBitDepthKey: 32, AVLinearPCMIsNonInterleaved: false
        ])
        trackOutput.alwaysCopiesSampleData = false
        guard reader.canAdd(trackOutput) else { throw MondayImportError.invalidMedia }
        reader.add(trackOutput)
        if let timeRange { reader.timeRange = timeRange }
        guard reader.startReading() else { throw reader.error ?? MondayImportError.invalidMedia }
        defer { reader.cancelReading() }
        let output = try AVAudioFile(forWriting: destination, settings: [
            AVFormatIDKey: kAudioFormatAppleLossless, AVSampleRateKey: rate,
            AVNumberOfChannelsKey: channels, AVEncoderBitDepthHintKey: 32
        ], commonFormat: .pcmFormatFloat32, interleaved: true)
        var writtenFrames = 0
        while let sample = trackOutput.copyNextSampleBuffer() {
            try Task.checkCancellation()
            try autoreleasepool {
                let frames = CMSampleBufferGetNumSamples(sample)
                guard frames > 0, frames <= Int(UInt32.max),
                      writtenFrames + frames <= Int(rate * 60),
                      let data = CMSampleBufferGetDataBuffer(sample),
                      let buffer = AVAudioPCMBuffer(pcmFormat: pcm, frameCapacity: AVAudioFrameCount(frames)) else {
                    throw MondayImportError.invalidMedia
                }
                buffer.frameLength = AVAudioFrameCount(frames)
                let bytes = frames * Int(pcm.streamDescription.pointee.mBytesPerFrame)
                guard CMBlockBufferGetDataLength(data) == bytes,
                      let destination = buffer.mutableAudioBufferList.pointee.mBuffers.mData,
                      CMBlockBufferCopyDataBytes(data, atOffset: 0, dataLength: bytes, destination: destination) == noErr else {
                    throw MondayImportError.invalidMedia
                }
                if gain != 1 {
                    let samples = destination.bindMemory(to: Float.self, capacity: frames * Int(channels))
                    for index in 0..<(frames * Int(channels)) {
                        samples[index] = min(max(samples[index] * gain, -1), 1)
                    }
                }
                try output.write(from: buffer)
                writtenFrames += frames
            }
        }
        try Task.checkCancellation()
        guard reader.status == .completed, writtenFrames > 0 else { throw reader.error ?? MondayImportError.invalidMedia }
    }
}
