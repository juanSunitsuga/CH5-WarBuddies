import AVFoundation
import CoreVideo
import Foundation
import Testing
@testable import RiftboundDetection

/// Proves a recording actually reaches the pipeline.
///
/// There was no test here, and the one failure this source can have —
/// yielding nothing, so the window stays blank — is invisible to every other
/// test in the suite, because they all feed frames in by hand.
@Suite("Video file capture")
struct VideoFileCaptureTests {

    /// Writes a short BGRA movie to a temporary file and returns its URL.
    private static func makeMovie(frames: Int = 12, fps: Int32 = 30) async throws -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("capture-\(UUID().uuidString).mov")
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(
            mediaType: .video,
            outputSettings: [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: 64,
                AVVideoHeightKey: 64
            ]
        )
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: 64,
                kCVPixelBufferHeightKey as String: 64
            ]
        )
        writer.add(input)
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)

        for index in 0..<frames {
            var buffer: CVPixelBuffer?
            CVPixelBufferCreate(kCFAllocatorDefault, 64, 64, kCVPixelFormatType_32BGRA, nil, &buffer)
            guard let buffer else { throw CocoaError(.featureUnsupported) }
            CVPixelBufferLockBaseAddress(buffer, [])
            if let base = CVPixelBufferGetBaseAddress(buffer) {
                // A different grey per frame, so a stuck first frame is not
                // mistaken for playback.
                memset(base, Int32(index * 8), CVPixelBufferGetDataSize(buffer))
            }
            CVPixelBufferUnlockBaseAddress(buffer, [])

            while !input.isReadyForMoreMediaData {
                try await Task.sleep(nanoseconds: 1_000_000)
            }
            adaptor.append(buffer, withPresentationTime: CMTime(value: CMTimeValue(index), timescale: fps))
        }
        input.markAsFinished()
        await writer.finishWriting()
        return url
    }

    @Test("A recording yields frames, numbered from 1 and timestamped from 0")
    func playsAFile() async throws {
        let url = try await Self.makeMovie()
        defer { try? FileManager.default.removeItem(at: url) }

        let capture = VideoFileCapture(url: url)
        let frames = capture.frames()
        try capture.start(deviceID: nil)

        var received: [CapturedFrame] = []
        for await frame in frames {
            received.append(frame)
            if received.count == 3 { break }
        }
        capture.stop()

        #expect(received.count == 3)
        // The blank-window bug: a file whose frames never arrive, or arrive
        // on the camera's host clock instead of the recording's own.
        #expect(received[0].frameIndex == 1)
        #expect(received[0].timestamp < 1.0)
        #expect(received[1].timestamp > received[0].timestamp)
        #expect(CVPixelBufferGetWidth(received[0].pixelBuffer) == 64)
    }

    @Test("A file with no readable video track reports an error instead of hanging")
    func reportsAMissingTrack() async throws {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("not-a-movie-\(UUID().uuidString).mov")
        try Data("not a movie".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let capture = VideoFileCapture(url: url)
        let events = capture.statusEvents()
        try capture.start(deviceID: nil)

        var reported: CameraStatusEvent?
        for await event in events {
            reported = event
            break
        }
        capture.stop()

        if case .runtimeError = reported { } else {
            Issue.record("Expected a runtime error, got \(String(describing: reported))")
        }
    }
}
