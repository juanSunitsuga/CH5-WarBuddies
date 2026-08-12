import AVFoundation
import CoreGraphics

/// One captured frame, handed to the detection layer.
///
/// `@unchecked Sendable`: `CVPixelBuffer` isn't `Sendable`-annotated but
/// AVFoundation hands each buffer to exactly one consumer per frame — safe
/// to pass across the `AsyncStream` boundary as long as nothing retains
/// and mutates it from a second task concurrently.
public struct CapturedFrame: @unchecked Sendable {
    public let pixelBuffer: CVPixelBuffer
    public let frameIndex: Int
    public let timestamp: TimeInterval

    public init(pixelBuffer: CVPixelBuffer, frameIndex: Int, timestamp: TimeInterval) {
        self.pixelBuffer = pixelBuffer
        self.frameIndex = frameIndex
        self.timestamp = timestamp
    }
}

/// One selectable video source — the Mac's built-in camera, an external
/// webcam, or an iPhone connected via Continuity Camera. On macOS a
/// paired/nearby iPhone with Continuity Camera enabled shows up as an
/// ordinary `AVCaptureDevice` (`deviceType == .continuityCamera`) — there
/// is no separate "connect to iPhone" pairing flow to build; this is a
/// device picker, same as picking any other camera.
public struct CameraDeviceOption: Sendable, Equatable, Identifiable {
    public let id: String            // AVCaptureDevice.uniqueID
    public let name: String          // AVCaptureDevice.localizedName
    public let isContinuityCamera: Bool
    public let isBuiltIn: Bool

    public init(id: String, name: String, isContinuityCamera: Bool, isBuiltIn: Bool) {
        self.id = id
        self.name = name
        self.isContinuityCamera = isContinuityCamera
        self.isBuiltIn = isBuiltIn
    }
}

/// Session-level things the camera layer observed that the app can't
/// otherwise know about — most importantly, that the *active* device just
/// vanished (an iPhone's Continuity Camera going away, a USB webcam being
/// unplugged). AVFoundation doesn't crash or throw when this happens; it
/// silently drops the input and stops delivering frames, which is exactly
/// what read as "the app doesn't want to detect the camera anymore" —
/// nothing was surfacing it. Consumers should treat any of these as "no
/// frames are coming right now," not just `.deviceDisconnected`.
public enum CameraStatusEvent: Sendable, Equatable {
    /// The device backing the current input was disconnected. Capture has
    /// stopped; the caller must pick a (still-available) device and call
    /// `start`/`switchCamera` again — this layer does not guess a
    /// replacement on its own.
    case deviceDisconnected(deviceID: String)
    case interrupted(reason: String)
    case interruptionEnded
    case runtimeError(String)
    /// The set of available cameras changed — a device appeared or
    /// disappeared (an iPhone's Continuity Camera reconnecting counts).
    /// Callers should re-fetch `AVFoundationCameraCapture.availableDevices()`
    /// to refresh whatever picker UI they're showing.
    case deviceListChanged
}

/// Abstracts the camera so `Detection`/tracking code never needs a real
/// `AVCaptureSession` to be testable — mirrors the same seam
/// `RiftboundExpertSystem.BoardObserving` uses for OCR fixtures.
public protocol CameraCapturing: AnyObject, Sendable {
    func frames() -> AsyncStream<CapturedFrame>
    /// Session/device-level events (disconnects, interruptions) the app
    /// should react to — see `CameraStatusEvent`.
    func statusEvents() -> AsyncStream<CameraStatusEvent>
    /// Starts capturing from `deviceID` (an `AVCaptureDevice.uniqueID`), or
    /// the system default video device if `nil`. Safe to call again after
    /// `stop()` or after a `.deviceDisconnected` event — session state is
    /// reset each time, not accumulated.
    func start(deviceID: String?) throws
    /// Switches to a different device without tearing down `frames()`'s
    /// `AsyncStream` — the UI can hop cameras mid-session.
    func switchCamera(to deviceID: String) throws
    func stop()
}

extension CameraCapturing {
    public func start() throws { try start(deviceID: nil) }
}

/// Real capture backend. Requires camera access
/// (`NSCameraUsageDescription` in the app's Info.plist) and must run
/// inside a full macOS app process — cannot be exercised headlessly, which
/// is why this class carries no test coverage; `ObjectTracker`/
/// `TemporalEventDetector`/`ZoneMapper` (the actually testable core) do.
///
/// All session mutation (start/switch/stop, plus the notification handlers
/// below) is funneled through `sessionQueue` — Apple's own guidance for
/// `AVCaptureSession` configuration, and what actually makes this safe:
/// without it, a device-disconnect notification arriving on AVFoundation's
/// callback thread could race a `switchCamera` call arriving from the
/// UI/MainActor at the same moment.
///
/// No zoom control here — `AVCaptureDevice.videoZoomFactor` (and `min`/
/// `maxAvailableVideoZoomFactor`) are explicitly `API_UNAVAILABLE(macos)`
/// in the SDK headers, so there's no hardware zoom API to expose on this
/// platform even for Continuity Camera input. This layer does lock
/// focus, though (`disableAutoFocus`, which *is* available on macOS).
public final class AVFoundationCameraCapture: NSObject, CameraCapturing, @unchecked Sendable {
    private let session = AVCaptureSession()
    private var currentInput: AVCaptureDeviceInput?
    private let output = AVCaptureVideoDataOutput()
    private var isOutputAttached = false
    private let sessionQueue = DispatchQueue(label: "RiftboundVision.camera.session")
    private let sampleBufferQueue = DispatchQueue(label: "RiftboundVision.camera.samples")
    private var continuation: AsyncStream<CapturedFrame>.Continuation?
    private var statusContinuation: AsyncStream<CameraStatusEvent>.Continuation?
    private var frameIndex = 0
    private var devicesObservation: NSKeyValueObservation?

    /// Retained for the lifetime of the process, not constructed fresh per
    /// call. This matters more than it looks like it should: macOS only
    /// keeps *watching* for camera hot-plug/reconnect events (including a
    /// Continuity Camera iPhone coming back after being disconnected)
    /// while an `AVCaptureDevice.DiscoverySession` observing video devices
    /// is alive. A short-lived construct-query-discard session — what
    /// this used to do on every call — can miss the reconnect entirely,
    /// which is exactly what read as "won't reappear until another app
    /// (e.g. Zoom) looks for it again": that other app's own long-lived
    /// discovery session was doing the watching ours wasn't.
    // `nonisolated(unsafe)`: `AVCaptureDevice.DiscoverySession` isn't
    // Sendable-annotated, but Apple documents it as safe to query/observe
    // from any thread — matches the `@unchecked Sendable` pattern already
    // used elsewhere in this file for other AVFoundation types.
    private nonisolated(unsafe) static let discoverySession = AVCaptureDevice.DiscoverySession(
        deviceTypes: [.builtInWideAngleCamera, .continuityCamera, .external, .deskViewCamera],
        mediaType: .video,
        position: .unspecified
    )

    public override init() {
        super.init()
        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(deviceWasDisconnected(_:)), name: .AVCaptureDeviceWasDisconnected, object: nil)
        center.addObserver(self, selector: #selector(sessionWasInterrupted(_:)), name: .AVCaptureSessionWasInterrupted, object: session)
        center.addObserver(self, selector: #selector(sessionInterruptionEnded(_:)), name: .AVCaptureSessionInterruptionEnded, object: session)
        center.addObserver(self, selector: #selector(sessionRuntimeError(_:)), name: .AVCaptureSessionRuntimeError, object: session)

        // KVO on `.devices` is how the retained discovery session above
        // actually earns its keep — without observing it, nothing ever
        // reads it again after `availableDevices()` returns, and it may
        // as well have been thrown away.
        devicesObservation = Self.discoverySession.observe(\.devices, options: [.new]) { [weak self] _, _ in
            self?.statusContinuation?.yield(.deviceListChanged)
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        devicesObservation?.invalidate()
    }

    /// Every currently available video source — built-in, external, and
    /// any iPhone/iPad offering itself as a Continuity Camera. Reads the
    /// shared, continuously-live `discoverySession` above rather than
    /// creating a new one — call this whenever you need a fresh snapshot
    /// (e.g. on `.deviceListChanged`); it's cheap since no new session is
    /// constructed.
    ///
    /// `deviceType == .continuityCamera` alone is NOT a reliable signal —
    /// confirmed against real hardware, an iPhone can show up typed
    /// `.external` instead (macOS version-dependent, apparently). The
    /// reliable tell is the *pairing*: a Continuity Camera-capable device
    /// always has a matching "<name> Desk View Camera" sibling entry
    /// (`.deskViewCamera`) — the Mac's own built-in camera has exactly the
    /// same pairing ("MacBook Pro Camera" / "MacBook Pro Desk View
    /// Camera"), which is what makes this detectable without hardcoding
    /// anything about "iPhone" specifically.
    public static func availableDevices() -> [CameraDeviceOption] {
        let devices = discoverySession.devices
        let deskViewSuffix = " Desk View Camera"
        let namesWithDeskViewCompanion = Set(
            devices
                .filter { $0.deviceType == .deskViewCamera && $0.localizedName.hasSuffix(deskViewSuffix) }
                .map { String($0.localizedName.dropLast(deskViewSuffix.count)) }
        )

        return devices.map { device in
            let isPersonalDeviceCamera = device.deviceType == .continuityCamera
                || (device.deviceType == .external && namesWithDeskViewCompanion.contains(device.localizedName))
            return CameraDeviceOption(
                id: device.uniqueID,
                name: device.localizedName,
                isContinuityCamera: isPersonalDeviceCamera,
                isBuiltIn: device.deviceType == .builtInWideAngleCamera
            )
        }
    }

    /// Diagnostic dump of every video-capable `AVCaptureDevice` macOS
    /// currently reports, across every device type — not just the ones
    /// `availableDevices()` curates. Exists specifically for "the picker
    /// says no iPhone camera, but Continuity Camera works elsewhere" —
    /// this answers whether the device is missing entirely, or present
    /// under a `deviceType` our curated list doesn't recognize as a
    /// phone. Call it and check the console (or wherever the app routes
    /// this string).
    public static func debugDeviceReport() -> String {
        let allTypes: [AVCaptureDevice.DeviceType] = [
            .builtInWideAngleCamera, .continuityCamera, .external, .deskViewCamera
        ]
        let broadDiscovery = AVCaptureDevice.DiscoverySession(deviceTypes: allTypes, mediaType: .video, position: .unspecified)
        // `AVCaptureDevice.devices(for:)` is the older, simpler API —
        // included in case a device is enumerable there but not through
        // any `DiscoverySession` device-type combination we guessed at.
        let legacyDevices = AVCaptureDevice.devices(for: .video)

        var lines: [String] = []
        lines.append("=== RiftboundVision camera diagnostic ===")
        lines.append("DiscoverySession (deviceTypes: \(allTypes.map(\.rawValue))): \(broadDiscovery.devices.count) device(s)")
        for device in broadDiscovery.devices {
            lines.append(describeDevice(device))
        }
        lines.append("AVCaptureDevice.devices(for: .video): \(legacyDevices.count) device(s)")
        for device in legacyDevices where !broadDiscovery.devices.contains(device) {
            lines.append(describeDevice(device) + "  [NOT in DiscoverySession above]")
        }
        lines.append("==========================================")
        return lines.joined(separator: "\n")
    }

    private static func describeDevice(_ device: AVCaptureDevice) -> String {
        "- \"\(device.localizedName)\" | deviceType=\(device.deviceType.rawValue) | uniqueID=\(device.uniqueID) | manufacturer=\(device.manufacturer) | isConnected=\(device.isConnected) | isSuspended=\(device.isSuspended)"
    }

    public func frames() -> AsyncStream<CapturedFrame> {
        AsyncStream { continuation in
            self.continuation = continuation
        }
    }

    public func statusEvents() -> AsyncStream<CameraStatusEvent> {
        AsyncStream { continuation in
            self.statusContinuation = continuation
        }
    }

    public func start(deviceID: String?) throws {
        try sessionQueue.sync {
            let device = try resolveDevice(deviceID)
            try attachInputLocked(device)
            try attachOutputLockedIfNeeded()
            if !session.isRunning {
                session.startRunning()
            }
        }
    }

    public func switchCamera(to deviceID: String) throws {
        try sessionQueue.sync {
            let device = try resolveDevice(deviceID)
            session.beginConfiguration()
            defer { session.commitConfiguration() }
            try attachInputLocked(device)
            if !session.isRunning {
                session.startRunning()
            }
        }
    }

    public func stop() {
        sessionQueue.sync {
            session.stopRunning()
            detachInputLocked()
        }
        continuation?.finish()
        continuation = nil
    }

    /// Attaches `device` as the session's input, replacing whatever was
    /// there before. Idempotent and safe to call repeatedly — including
    /// after the previous input silently vanished (disconnected device),
    /// which is exactly the state a naive "just addInput" implementation
    /// gets stuck in, since the stale `currentInput` reference is no
    /// longer a member of `session.inputs` and re-adding without removing
    /// it first is what previously left the session unable to start again.
    private func attachInputLocked(_ device: AVCaptureDevice) throws {
        if let currentInput, currentInput.device.uniqueID == device.uniqueID, session.inputs.contains(currentInput) {
            return // already attached to this exact device — nothing to do
        }
        let newInput = try AVCaptureDeviceInput(device: device)
        detachInputLocked()
        guard session.canAddInput(newInput) else { throw CameraError.cannotConfigureSession }
        session.addInput(newInput)
        currentInput = newInput
        disableAutoFocus(device)
    }

    /// Disables continuous auto-focus so the camera stops hunting/
    /// refocusing on its own while scanning a static table. Tries
    /// `.locked` first (freeze at
    /// whatever's already in focus) and falls back to a one-shot
    /// `.autoFocus` if the device doesn't support locking — not every
    /// camera does (some virtual/Continuity devices only expose
    /// continuous auto), so this degrades gracefully rather than failing
    /// silently in a worse way.
    private func disableAutoFocus(_ device: AVCaptureDevice) {
        do {
            try device.lockForConfiguration()
            defer { device.unlockForConfiguration() }
            if device.isFocusModeSupported(.locked) {
                device.focusMode = .locked
            } else if device.isFocusModeSupported(.autoFocus) {
                device.focusMode = .autoFocus
            }
        } catch {
            // Best-effort — leaves whatever focus behavior the device
            // already had rather than throwing and blocking capture.
        }
    }

    private func detachInputLocked() {
        guard let currentInput else { return }
        if session.inputs.contains(currentInput) {
            session.removeInput(currentInput)
        }
        self.currentInput = nil
    }

    private func attachOutputLockedIfNeeded() throws {
        guard !isOutputAttached else { return }
        output.setSampleBufferDelegate(self, queue: sampleBufferQueue)
        guard session.canAddOutput(output) else { throw CameraError.cannotConfigureSession }
        session.addOutput(output)
        isOutputAttached = true
    }

    private func resolveDevice(_ deviceID: String?) throws -> AVCaptureDevice {
        if let deviceID {
            guard let device = AVCaptureDevice(uniqueID: deviceID) else {
                throw CameraError.deviceNotFound(deviceID)
            }
            return device
        }
        guard let device = AVCaptureDevice.default(for: .video) else {
            throw CameraError.noCameraAvailable
        }
        return device
    }

    public enum CameraError: Error {
        case noCameraAvailable
        case cannotConfigureSession
        case deviceNotFound(String)
    }

    // MARK: - Notifications

    @objc private func deviceWasDisconnected(_ notification: Notification) {
        guard let device = notification.object as? AVCaptureDevice else { return }
        let disconnectedID = device.uniqueID
        sessionQueue.async { [weak self] in
            guard let self else { return }
            guard self.currentInput?.device.uniqueID == disconnectedID else { return }
            self.session.beginConfiguration()
            self.detachInputLocked()
            self.session.commitConfiguration()
            self.statusContinuation?.yield(.deviceDisconnected(deviceID: disconnectedID))
        }
    }

    @objc private func sessionWasInterrupted(_ notification: Notification) {
        // `AVCaptureSessionInterruptionReasonKey`/`InterruptionReason` are
        // iOS-only — macOS's notification doesn't carry a structured
        // reason, so this just reports that an interruption happened.
        statusContinuation?.yield(.interrupted(reason: "session interrupted"))
    }

    @objc private func sessionInterruptionEnded(_ notification: Notification) {
        statusContinuation?.yield(.interruptionEnded)
    }

    @objc private func sessionRuntimeError(_ notification: Notification) {
        let error = notification.userInfo?[AVCaptureSessionErrorKey] as? Error
        statusContinuation?.yield(.runtimeError(error?.localizedDescription ?? "unknown error"))
    }
}

extension AVFoundationCameraCapture: AVCaptureVideoDataOutputSampleBufferDelegate {
    public func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds
        frameIndex += 1
        continuation?.yield(CapturedFrame(pixelBuffer: pixelBuffer, frameIndex: frameIndex, timestamp: timestamp))
    }
}
