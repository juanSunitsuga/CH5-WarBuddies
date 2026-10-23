import AVFoundation
import CoreVideo
import Foundation

/// Plays a recorded video in place of the camera, so a measurement run can
/// be repeated.
///
/// This exists for the thesis's Subbab 4.4. Numbers taken from a live camera
/// cannot be reproduced — the cards are never in quite the same place, the
/// light moves, and a reviewer cannot re-run the session. Feeding the same
/// file through the same pipeline makes every figure in Tabel 4.28
/// re-derivable, and lets the same recording be replayed after a code change
/// to see whether a number moved because of the change or because of the
/// room.
///
/// Conforms to `CameraCapturing`, so nothing downstream knows the
/// difference: tracking, ingestion, translation and validation all run
/// exactly as they do against a camera. That is the point — a source that
/// bypassed any of them would measure a pipeline the app does not have.
///
/// **Frames are paced to the video's own timestamps**, not delivered as fast
/// as they decode. A pipeline fed faster than real time would report
/// latencies no player would ever see, and detection would fall behind in a
/// way the measurement then hides.
public final class VideoFileCapture: CameraCapturing, @unchecked Sendable {

    private let url: URL
    private let loops: Bool

    private let lock = NSLock()
    private var continuation: AsyncStream<CapturedFrame>.Continuation?
    private var statusContinuation: AsyncStream<CameraStatusEvent>.Continuation?
    private var playback: Task<Void, Never>?
    private var frameIndex = 0

    /// - Parameters:
    ///   - url: the recording to play.
    ///   - loops: repeat on reaching the end. Off by default: a measurement
    ///     run should end when the recording does, so the sample count is
    ///     the recording's length rather than however long someone left it
    ///     running.
    public init(url: URL, loops: Bool = false) {
        self.url = url
        self.loops = loops
    }

    // MARK: - CameraCapturing

    /// Same `.bufferingNewest(1)` policy as the live camera.
    ///
    /// Deliberately not "deliver every frame": matching the camera is what
    /// makes the measurement representative. If detection cannot keep up
    /// with the recording, that is a real finding about the pipeline, and a
    /// source that queued frames instead would conceal it behind a backlog.
    public func frames() -> AsyncStream<CapturedFrame> {
        AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            lock.lock(); self.continuation = continuation; lock.unlock()
        }
    }

    public func statusEvents() -> AsyncStream<CameraStatusEvent> {
        AsyncStream(bufferingPolicy: .bufferingNewest(64)) { continuation in
            lock.lock(); self.statusContinuation = continuation; lock.unlock()
        }
    }

    /// `deviceID` is ignored — there is one file and it was chosen at init.
    public func start(deviceID: String?) throws {
        stop()
        let task = Task { [weak self] in await self?.play() }
        lock.lock(); playback = task; lock.unlock()
    }

    /// Switching source mid-run would split a measurement across two
    /// recordings, so this reports the error rather than silently carrying
    /// on against a different input.
    public func switchCamera(to deviceID: String) throws {
        throw VideoFileCaptureError.cannotSwitchSource
    }

    public func stop() {
        lock.lock()
        let task = playback
        playback = nil
        lock.unlock()
        task?.cancel()
    }

    // MARK: - Playback

    /// Loops with `repeat`, not by calling itself.
    ///
    /// A recursive replay never returns from the previous pass, so each loop
    /// keeps its frame alive and a long unattended run — exactly what a
    /// measurement session is — eventually overflows the stack.
    private func play() async {
        do {
            repeat {
                let asset = AVURLAsset(url: url)
                let reader = try AVAssetReader(asset: asset)

                guard let track = try await asset.loadTracks(withMediaType: .video).first else {
                    emit(.runtimeError("The file has no video track: \(url.lastPathComponent)"))
                    return
                }

                // BGRA because that is what the detector and the preview
                // conversion already expect from the camera.
                let output = AVAssetReaderTrackOutput(
                    track: track,
                    outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
                )
                // Copies, deliberately. Without this the pixel buffer belongs
                // to the sample buffer, which is released at the end of each
                // iteration — and the pipeline reads frames asynchronously, so
                // detection could be looking at memory already recycled for a
                // later frame. That failure looks like a bad model rather than
                // a freed buffer, which is the worst way for it to present.
                output.alwaysCopiesSampleData = true
                reader.add(output)
                reader.startReading()

                let startedAt = CFAbsoluteTimeGetCurrent()

                while !Task.isCancelled, let sample = output.copyNextSampleBuffer() {
                    guard let pixelBuffer = CMSampleBufferGetImageBuffer(sample) else { continue }
                    let presentation = CMSampleBufferGetPresentationTimeStamp(sample).seconds

                    // Pace to the recording's own clock. Without this the whole
                    // file decodes in a second or two and every latency figure
                    // is measured under a load no camera produces.
                    let elapsed = CFAbsoluteTimeGetCurrent() - startedAt
                    if presentation > elapsed {
                        try? await Task.sleep(nanoseconds: UInt64((presentation - elapsed) * 1_000_000_000))
                    }

                    lock.lock()
                    frameIndex += 1
                    let index = frameIndex
                    let stream = continuation
                    lock.unlock()

                    stream?.yield(CapturedFrame(pixelBuffer: pixelBuffer, frameIndex: index, timestamp: presentation))
                }

                if Task.isCancelled { return }

                if !loops {
                    // Not an error: the recording simply ended. Reported so the
                    // dashboard can show the run as finished rather than
                    // appearing to hang on a frozen last frame.
                    emit(.interruptionEnded)
                }
            } while loops && !Task.isCancelled
        } catch {
            emit(.runtimeError("Couldn't read \(url.lastPathComponent): \(error.localizedDescription)"))
        }
    }

    private func emit(_ event: CameraStatusEvent) {
        lock.lock()
        let stream = statusContinuation
        lock.unlock()
        stream?.yield(event)
    }
}

public enum VideoFileCaptureError: LocalizedError {
    case cannotSwitchSource

    public var errorDescription: String? {
        switch self {
        case .cannotSwitchSource:
            return "A recorded run plays one file from start to finish. Stop the run and pick another file."
        }
    }
}
