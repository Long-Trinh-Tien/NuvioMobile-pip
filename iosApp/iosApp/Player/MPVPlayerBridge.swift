import Foundation
import UIKit
import AVFoundation
import AVKit
import Libmpv
import ComposeApp
import Darwin
import ObjectiveC

private func zdLog(_ message: String) {
    NSLog("%@", message)
}

/// Tiny helper view that reports when the player's view actually lands in (or
/// leaves) a window. UIViewController has no didMoveToWindow, so the PiP
/// controller creation hangs off this subview instead.
final class ZDWindowObserverView: UIView {
    var onWindowChange: ((Bool) -> Void)?

    override func didMoveToWindow() {
        super.didMoveToWindow()
        onWindowChange?(window != nil)
    }
}

// MARK: - Player Bridge Implementation (Kotlin protocol conformance)

final class MPVPlayerBridgeImpl: NSObject, NuvioPlayerBridge {

    private var playerVC: MPVPlayerViewController?

    func createPlayerViewController() -> UIViewController {
        return ensurePlayerViewController()
    }

    private func ensurePlayerViewController() -> MPVPlayerViewController {
        if let playerVC { return playerVC }
        let vc = MPVPlayerViewController()
        self.playerVC = vc
        return vc
    }

    func loadFile(url: String) { ensurePlayerViewController().loadFile(url) }
    func loadFileWithAudio(videoUrl: String, audioUrl: String?, headersJson: String?, subtitlesJson: String?) {
        ensurePlayerViewController().loadFile(
            videoUrl,
            audioUrl: audioUrl,
            requestHeaders: parseRequestHeaders(headersJson),
            subtitles: parseSubtitles(subtitlesJson)
        )
    }

    private func parseSubtitles(_ json: String?) -> [PluginSubtitle] {
        guard
            let json,
            let data = json.data(using: .utf8),
            let raw = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        else {
            return []
        }
        return raw.compactMap { dict in
            guard let url = dict["url"] as? String else { return nil }
            return PluginSubtitle(
                url: url,
                language: dict["language"] as? String ?? "Unknown",
                name: dict["name"] as? String,
                headers: dict["headers"] as? [String: String]
            )
        }
    }

    func play() { playerVC?.playPlayback() }
    func pause() { playerVC?.pausePlayback() }
    func seekTo(positionMs: Int64) { playerVC?.seekToMs(positionMs) }
    func seekBy(offsetMs: Int64) { playerVC?.seekByMs(offsetMs) }
    func retry() { playerVC?.retryPlayback() }
    func updateNowPlayingMetadata(
        title: String,
        subtitle: String?,
        artworkUrl: String?
    ) {
        ensurePlayerViewController().updateNowPlayingMetadata(
            title: title,
            subtitle: subtitle,
            artworkUrl: artworkUrl
        )
    }
    func clearNowPlayingInfo() { playerVC?.clearNowPlayingInfo() }
    func configureVideoOutput(
        hardwareDecoder: String,
        targetColorspaceHint: Bool,
        toneMapping: String,
        hdrComputePeak: Bool,
        targetPrimaries: String,
        targetTransfer: String,
        extendedDynamicRange: Bool,
        deband: Bool,
        interpolation: Bool,
        brightness: Int32,
        contrast: Int32,
        saturation: Int32,
        gamma: Int32
    ) {
        playerVC?.configureVideoOutput(
            hardwareDecoder: hardwareDecoder,
            targetColorspaceHint: targetColorspaceHint,
            toneMapping: toneMapping,
            hdrComputePeak: hdrComputePeak,
            targetPrimaries: targetPrimaries,
            targetTransfer: targetTransfer,
            extendedDynamicRange: extendedDynamicRange,
            deband: deband,
            interpolation: interpolation,
            brightness: Int(brightness),
            contrast: Int(contrast),
            saturation: Int(saturation),
            gamma: Int(gamma)
        )
    }
    func configureAudioOutput(audioOutput: String) {
        playerVC?.configureAudioOutput(audioOutput: audioOutput)
    }
    func setPlaybackSpeed(speed: Float) { playerVC?.setSpeed(speed) }
    func setMuted(muted: Bool) { playerVC?.setMuted(muted) }
    func setResizeMode(mode: Int32) { playerVC?.setResize(Int(mode)) }
    func syncVideoSurfaceLayout(width: Double, height: Double) {
        playerVC?.syncVideoSurfaceLayout(size: CGSize(width: width, height: height))
    }

    // Audio tracks
    func getAudioTrackCount() -> Int32 { Int32(playerVC?.audioTracks.count ?? 0) }
    func getAudioTrackIndex(at: Int32) -> Int32 {
        guard let t = playerVC?.audioTracks, Int(at) < t.count else { return 0 }
        return Int32(t[Int(at)].index)
    }
    func getAudioTrackId(at: Int32) -> String {
        guard let t = playerVC?.audioTracks, Int(at) < t.count else { return "0" }
        return "\(t[Int(at)].id)"
    }
    func getAudioTrackLabel(at: Int32) -> String {
        guard let t = playerVC?.audioTracks, Int(at) < t.count else { return "" }
        return t[Int(at)].title
    }
    func getAudioTrackLang(at: Int32) -> String {
        guard let t = playerVC?.audioTracks, Int(at) < t.count else { return "" }
        return t[Int(at)].lang
    }
    func isAudioTrackSelected(at: Int32) -> Bool {
        guard let t = playerVC?.audioTracks, Int(at) < t.count else { return false }
        return t[Int(at)].selected
    }

    // Subtitle tracks
    func getSubtitleTrackCount() -> Int32 { Int32(playerVC?.subtitleTracks.count ?? 0) }
    func getSubtitleTrackIndex(at: Int32) -> Int32 {
        guard let t = playerVC?.subtitleTracks, Int(at) < t.count else { return 0 }
        return Int32(t[Int(at)].index)
    }
    func getSubtitleTrackId(at: Int32) -> String {
        guard let t = playerVC?.subtitleTracks, Int(at) < t.count else { return "0" }
        return "\(t[Int(at)].id)"
    }
    func getSubtitleTrackLabel(at: Int32) -> String {
        guard let t = playerVC?.subtitleTracks, Int(at) < t.count else { return "" }
        return t[Int(at)].title
    }
    func getSubtitleTrackLang(at: Int32) -> String {
        guard let t = playerVC?.subtitleTracks, Int(at) < t.count else { return "" }
        return t[Int(at)].lang
    }
    func isSubtitleTrackSelected(at: Int32) -> Bool {
        guard let t = playerVC?.subtitleTracks, Int(at) < t.count else { return false }
        return t[Int(at)].selected
    }

    func selectAudioTrack(trackId: Int32) { playerVC?.selectAudio(Int(trackId)) }
    func applyAudioLanguagePreferences(languages: [String]) {
        ensurePlayerViewController().applyAudioLanguagePreferences(languages)
    }
    func selectSubtitleTrack(trackId: Int32) { playerVC?.selectSubtitle(Int(trackId)) }
    func setSubtitleUrl(url: String) { playerVC?.addSubtitleUrl(url) }
    func clearExternalSubtitle() { playerVC?.removeExternalSubtitles() }
    func clearExternalSubtitleAndSelect(trackId: Int32) { playerVC?.removeExternalSubtitlesAndSelect(Int(trackId)) }
    func setSubtitleDelayMs(delayMs: Int32) { playerVC?.setSubtitleDelayMs(Int(delayMs)) }
    func applySubtitleStyle(
        textColor: String,
        backgroundColor: String,
        outlineColor: String,
        outlineSize: Float,
        bold: Bool,
        fontSize: Float,
        subPos: Int32,
        stripSdh: Bool
    ) {
        playerVC?.applySubtitleStyle(
            textColor: textColor,
            backgroundColor: backgroundColor,
            outlineColor: outlineColor,
            outlineSize: outlineSize,
            bold: bold,
            fontSize: fontSize,
            subPos: Int(subPos),
            stripSdh: stripSdh
        )
    }

    // State - refreshes position from mpv on each call (polled from Kotlin every 250ms)
    func getIsLoading() -> Bool { playerVC?.refreshPlaybackState(); return playerVC?.isPlayerLoading ?? true }
    func getIsPlaying() -> Bool { return playerVC?.isPlayerPlaying ?? false }
    func getIsEnded() -> Bool { return playerVC?.isPlayerEnded ?? false }
    func getDurationMs() -> Int64 { return playerVC?.durationMs ?? 0 }
    func getPositionMs() -> Int64 { return playerVC?.positionMs ?? 0 }
    func getBufferedMs() -> Int64 { return playerVC?.bufferedMs ?? 0 }
    func getPlaybackSpeed() -> Float { playerVC?.currentSpeed ?? 1.0 }
    func getErrorMessage() -> String { playerVC?.currentErrorMessage ?? "" }
    func getProperty(name: String) -> String { playerVC?.getString(name) ?? "" }

    func destroy() {
        playerVC?.destroyPlayer()
        playerVC = nil
    }

    private func parseRequestHeaders(_ headersJson: String?) -> [String: String] {
        guard
            let headersJson,
            !headersJson.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            let data = headersJson.data(using: .utf8),
            let raw = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return [:]
        }

        var headers: [String: String] = [:]
        headers.reserveCapacity(raw.count)
        raw.forEach { key, value in
            guard let headerValue = value as? String else { return }
            headers[key] = headerValue
        }
        return headers
    }
}

struct PluginSubtitle {
    let url: String
    let language: String
    let name: String?
    let headers: [String: String]?
}

// MARK: - Track Info

struct TrackInfo {
    let index: Int
    let id: Int
    let type: String
    let title: String
    let lang: String
    let selected: Bool
}

private struct PendingLoadRequest {
    let urlString: String
    let audioUrl: String?
    let requestHeaders: [String: String]
    let subtitles: [PluginSubtitle]
    let queuedAtUptime: TimeInterval
}

// MARK: - MPV Player View Controller

final class MPVPlayerViewController: UIViewController, AVPictureInPictureControllerDelegate, AVPictureInPictureSampleBufferPlaybackDelegate {

    private static let defaultAudioOutput = "audiounit"

    private struct CachedNowPlayingMetadata {
        let title: String
        let subtitle: String?
        let artworkUrl: String?
    }

    private let errorStateLock = NSLock()
    // iOS video surface: the mpv `avfoundation` VO renders into this
    // AVSampleBufferDisplayLayer; it also serves as the PiP content source.
    private var videoLayer = AVSampleBufferDisplayLayer()
    private var pipController: AVPictureInPictureController?
    private var isPipActive = false
    private var pipStopForForeground = false
    private var pipFallbackWorkItem: DispatchWorkItem?
    private var pipBackgroundTask: UIBackgroundTaskIdentifier = .invalid
    private var lastKnownDurationSeconds: Double = 0
    private var pipPossibleObservation: NSKeyValueObservation?
    private var pipCreatedWhileActive = false
    private var pipRebuildCount = 0
    private let windowObserverView = ZDWindowObserverView()
    private var externallyManagedViewSize: CGSize?
    private var pendingSurfaceLayoutWorkItems: [DispatchWorkItem] = []
    private var pendingLoadRequest: PendingLoadRequest?
    private var pendingLoadRetryWorkItem: DispatchWorkItem?
    private var mpv: OpaquePointer?
    private var cachedNowPlayingMetadata: CachedNowPlayingMetadata?
    private lazy var nowPlayingController = PlayerNowPlayingController(owner: self)
    private lazy var eventQueue = DispatchQueue(label: "mpv-events", qos: .userInitiated)
    private var recentPlaybackLogs: [String] = []
    private var activeRequestHeaders: [String: String] = [:]
    private var preferredAudioLanguages: [String] = []

    // Cached track lists
    var audioTracks: [TrackInfo] = []
    var subtitleTracks: [TrackInfo] = []

    // State (polled from Kotlin every 250ms)
    var isPlayerLoading: Bool = true
    var isPlayerPlaying: Bool = false
    var isPlayerEnded: Bool = false
    var durationMs: Int64 = 0
    var positionMs: Int64 = 0
    var bufferedMs: Int64 = 0
    var currentSpeed: Float = 1.0
    var currentErrorMessage: String {
        errorStateLock.lock()
        defer { errorStateLock.unlock() }
        return _currentErrorMessage ?? ""
    }
    private var _currentErrorMessage: String?

    // Discontinuity rescue: if mpv's time-pos suddenly drops to ~0 mid-playback
    // (sloppy ad-spliced HLS), seek back to the last good position.
    private var lastGoodPositionMs: Int64 = 0
    private var previousPollPositionMs: Int64 = 0
    private var previousPollWasPlaying: Bool = false
    private var discontinuityRescuesUsed: Int = 0
    private var discontinuityRescueCooldownUntil: TimeInterval = 0

    // User-facing timeline healing: after the sanitizer removes an ad cluster
    // that occupied real time in the movie clock, raw time-pos jumps forward
    // by the removed amount. These holes let the player show a continuous
    // clock and convert user seeks back into raw (mpv) targets.
    struct TimelineHole {
        var start: Double       // raw seconds where the gap begins
        var size: Double        // seconds removed at the gap
        var observed: Bool = false
    }
    var timelineHoles: [TimelineHole] = []
    private var previousRawPosition: Double = 0
    private var previousPollWasPaused: Bool = false
    private var holeDetectionMuteUntil: TimeInterval = 0

    private func resetDiscontinuityGuard() {
        lastGoodPositionMs = 0
        previousPollPositionMs = 0
        previousPollWasPlaying = false
        previousPollWasPaused = false
        discontinuityRescuesUsed = 0
        discontinuityRescueCooldownUntil = 0
        previousRawPosition = 0
        holeDetectionMuteUntil = 0
    }

    override var canBecomeFirstResponder: Bool {
        true
    }

    override var prefersHomeIndicatorAutoHidden: Bool {
        true
    }

    override var preferredScreenEdgesDeferringSystemGestures: UIRectEdge {
        [.bottom, .left, .right]
    }

    override var prefersStatusBarHidden: Bool {
        true
    }

    override var preferredStatusBarUpdateAnimation: UIStatusBarAnimation {
        .fade
    }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        view.layer.masksToBounds = true

        videoLayer.contentsGravity = .resize
        videoLayer.contentsScale = view.window?.screen.nativeScale ?? UIScreen.main.nativeScale
        videoLayer.backgroundColor = UIColor.black.cgColor
        videoLayer.videoGravity = .resizeAspect
        videoLayer.anchorPoint = CGPoint(x: 0, y: 0)
        videoLayer.position = .zero
        view.layer.addSublayer(videoLayer)
        layoutVideoLayer()
        setupDisplayLayerTimebase()

        windowObserverView.frame = .zero
        windowObserverView.isUserInteractionEnabled = false
        windowObserverView.onWindowChange = { [weak self] inWindow in
            guard let self, inWindow else { return }
            self.setupPictureInPicture(reason: "viewInWindow")
            zdLog(self.pipProxyDiagnostics("viewInWindow"))
        }
        view.addSubview(windowObserverView)

        setupMpv()
        activateAudioSessionForPlayback()
        refreshImmersiveSystemUI()
    }

    // MARK: - Picture in Picture

    /// Drive the display layer from the host clock so enqueued frames present
    /// smoothly and the PiP window has a valid timebase. Set once (idempotent);
    /// re-setting the timebase later would disturb playback.
    private func setupDisplayLayerTimebase() {
        guard videoLayer.controlTimebase == nil else { return }
        var timebase: CMTimebase?
        if CMTimebaseCreateWithSourceClock(allocator: kCFAllocatorDefault,
                                           sourceClock: CMClockGetHostTimeClock(),
                                           timebaseOut: &timebase) == noErr,
           let timebase = timebase {
            videoLayer.controlTimebase = timebase
            CMTimebaseSetTime(timebase, time: .zero)
            CMTimebaseSetRate(timebase, rate: 1.0)
        }
    }

    /// Create the PiP controller only once the view is attached to a window.
    /// The AVKit platform proxy resolves its scene-session identifier when it is
    /// set up (first layout); a controller created in viewDidLoad has no window
    /// yet, and a proxy created while the scene is inactive (e.g. an episode
    /// switch while PiP is up) caches a nil identifier that SpringBoard's remote
    /// object keeps forever. The Home-swipe check then fails
    /// (`matchesSceneIdentifier{false}`) and PiP only comes up on a second try.
    /// Creating with a window + active scene, plus the heal below, keeps the
    /// identifier correct.
    private func setupPictureInPicture(reason: String) {
        guard AVPictureInPictureController.isPictureInPictureSupported() else { return }
        guard pipController == nil else { return }
        guard view.window != nil else {
            zdLog("[PiP] setup skipped (\(reason)): no window yet")
            return
        }

        setupDisplayLayerTimebase()

        let source = AVPictureInPictureController.ContentSource(
            sampleBufferDisplayLayer: videoLayer,
            playbackDelegate: self
        )
        let controller = AVPictureInPictureController(contentSource: source)
        controller.delegate = self
        controller.canStartPictureInPictureAutomaticallyFromInline = true
        pipPossibleObservation = controller.observe(\.isPictureInPicturePossible, options: [.new]) { _, change in
            zdLog("[PiP] possible -> \(String(describing: change.newValue))")
        }
        pipController = controller
        pipCreatedWhileActive = Self.zdSceneIsForegroundActive()
        _ = Self.forceCompositeFn
        zdLog("[PiP] ready (auto-start from inline enabled) reason=\(reason) createdWhileActive=\(pipCreatedWhileActive)")
        zdLog(pipProxyDiagnostics("created"))

        // The AVKit adapter/proxy appears on the first layout pass; sample it
        // shortly after creation and heal a broken scene cache.
        for delay in [0.7, 2.2] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self, let pip = self.pipController else { return }
                zdLog(self.pipProxyDiagnostics("created+\(delay)"))
                self.healPipControllerIfNeeded(reason: "created+\(delay)", pip: pip)
            }
        }
    }

    /// Called when the app becomes active; re-checks the PiP proxy's scene
    /// cache and rebuilds the controller when it is broken (e.g. it was created
    /// during a background episode switch / PiP restore transition).
    @objc private func appDidBecomeActive() {
        guard mpv != nil, isViewLoaded, view.window != nil else { return }
        zdLog(pipProxyDiagnostics("didBecomeActive"))
        if let pip = pipController {
            healPipControllerIfNeeded(reason: "didBecomeActive", pip: pip)
        } else {
            setupPictureInPicture(reason: "didBecomeActive")
        }
    }

    private func healPipControllerIfNeeded(reason: String, pip: AVPictureInPictureController) {
        guard pipRebuildCount < 2 else { return }
        guard !pip.isPictureInPictureActive, !isPipActive, !pipStopForForeground else { return }
        guard view.window != nil, Self.zdSceneIsForegroundActive() else { return }
        guard let proxy = Self.zdFindPipProxy(in: pip) else { return }
        let session = Self.zdIvarString(proxy, "_sceneSessionPersistentIdentifier")
        guard session != "missing", session != "?" else { return }
        let appScene = Self.zdAppSceneSessionId()
        guard session != appScene else { return }
        zdLog("[PiP] heal: scene mismatch (session=\(session) app=\(appScene)) -> rebuilding (\(reason))")
        rebuildPipController(reason: reason)
    }

    private func rebuildPipController(reason: String) {
        guard let old = pipController else {
            setupPictureInPicture(reason: "rebuild:\(reason)")
            return
        }
        guard !old.isPictureInPictureActive, !isPipActive, !pipStopForForeground else { return }
        pipRebuildCount += 1
        pipPossibleObservation?.invalidate()
        pipPossibleObservation = nil
        old.delegate = nil
        pipController = nil
        zdLog("[PiP] rebuild #\(pipRebuildCount) (\(reason))")
        setupPictureInPicture(reason: "rebuild:\(reason)")
    }

    // MARK: - PiP diagnostics (read-only, for log forensics)

    private func pipProxyDiagnostics(_ tag: String) -> String {
        let appScene = Self.zdAppSceneSessionId()
        guard let pip = pipController else {
            return "[PiP] diag \(tag): no-controller app=\(appScene)"
        }
        guard let proxy = Self.zdFindPipProxy(in: pip) else {
            return "[PiP] diag \(tag): proxy-not-found app=\(appScene) possible=\(pip.isPictureInPicturePossible) active=\(pip.isPictureInPictureActive)"
        }
        let session = Self.zdIvarString(proxy, "_sceneSessionPersistentIdentifier")
        let match = session == appScene ? "Y" : "N"
        return "[PiP] diag \(tag): proxy=\(String(describing: Unmanaged.passUnretained(proxy).toOpaque())) session=\(session) app=\(appScene) match=\(match) possible=\(Self.zdIvarBool(proxy, "_isPictureInPicturePossible")) active=\(Self.zdIvarBool(proxy, "_isPictureInPictureActive")) shouldStart=\(Self.zdIvarBool(proxy, "_pictureInPictureShouldStartWhenEnteringBackground"))"
    }

    private static func zdAppScene() -> UIWindowScene? {
        if let active = UIApplication.shared.connectedScenes.first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene {
            return active
        }
        return UIApplication.shared.connectedScenes.first as? UIWindowScene
    }

    private static func zdSceneIsForegroundActive() -> Bool {
        if let scene = zdAppScene() { return scene.activationState == .foregroundActive }
        return UIApplication.shared.applicationState == .active
    }

    private static func zdAppSceneSessionId() -> String {
        return zdAppScene()?.session.persistentIdentifier ?? "nil"
    }

    private static func zdIvarString(_ obj: AnyObject, _ name: String) -> String {
        guard let iv = class_getInstanceVariable(type(of: obj), name) else { return "missing" }
        guard let value = object_getIvar(obj, iv) else { return "nil" }
        if let s = value as? String { return s }
        if let uuid = value as? UUID { return uuid.uuidString }
        return "?"
    }

    private static func zdIvarBool(_ obj: AnyObject, _ name: String) -> String {
        guard let iv = class_getInstanceVariable(type(of: obj), name) else { return "?" }
        let base = Unmanaged.passUnretained(obj).toOpaque()
        let byte = base.advanced(by: ivar_getOffset(iv)).load(as: UInt8.self)
        return byte != 0 ? "Y" : "N"
    }

    /// Breadth-first search through object-typed ivars (and shallow collections)
    /// for the AVKit platform proxy (`PGPictureInPictureProxy`) under the
    /// controller. Depth-capped and count-capped; read-only.
    private static func zdFindPipProxy(in root: AnyObject) -> NSObject? {
        var queue: [AnyObject] = [root]
        var depths: [Int] = [0]
        var visited = Set<ObjectIdentifier>()
        var index = 0
        while index < queue.count, visited.count < 400 {
            let obj = queue[index]
            let depth = depths[index]
            index += 1
            let oid = ObjectIdentifier(obj)
            if visited.contains(oid) { continue }
            visited.insert(oid)
            guard let cls = object_getClass(obj) else { continue }
            let name = NSStringFromClass(cls)
            if name.contains("PictureInPictureProxy") { return obj as? NSObject }
            if depth >= 4 { continue }
            if let arr = obj as? [Any] {
                for element in arr {
                    queue.append(element as AnyObject)
                    depths.append(depth + 1)
                }
                continue
            }
            guard depth == 0 || name.contains("AVPictureInPicture") || name.contains("PG") || name.contains("AVKit") else { continue }
            var ivarClass: AnyClass? = cls
            var hops = 0
            while let current = ivarClass, hops < 4 {
                var count: UInt32 = 0
                if let ivars = class_copyIvarList(current, &count) {
                    for i in 0..<Int(count) {
                        let iv = ivars[i]
                        guard let te = ivar_getTypeEncoding(iv), te.pointee == 0x40 else { continue }
                        if let value = object_getIvar(obj, iv) {
                            queue.append(value as AnyObject)
                            depths.append(depth + 1)
                        }
                    }
                    free(ivars)
                }
                ivarClass = class_getSuperclass(current)
                hops += 1
            }
        }
        return nil
    }

    // MARK: - PiP subtitle compositing + layer diagnostics

    /// The engine (vo_avfoundation) exports this hook. While Picture in Picture
    /// is active the OSD sublayer is not part of the PiP video pipeline, so we
    /// ask the video output to composite subtitles into the sample buffers.
    private static let forceCompositeFn: (@convention(c) (Int32) -> Void)? = {
        guard let sym = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "nuvio_avfoundation_set_force_composite") else {
            zdLog("[PiP] force-composite symbol NOT found")
            return nil
        }
        zdLog("[PiP] force-composite symbol found")
        return unsafeBitCast(sym, to: (@convention(c) (Int32) -> Void).self)
    }()

    private func setForceComposite(_ enabled: Bool) {
        guard let fn = Self.forceCompositeFn else { return }
        fn(enabled ? 1 : 0)
        zdLog("[PiP] force-composite -> \(enabled)")
    }

    private func layerStatusName() -> String {
        switch videoLayer.status {
        case .rendering: return "rendering"
        case .failed: return "failed"
        default: return "unknown"
        }
    }

    private func logLayerState(_ tag: String) {
        zdLog("[Layer] \(tag) status=\(layerStatusName()) reqFlush=\(videoLayer.requiresFlushToResumeDecoding) err=\(videoLayer.error?.localizedDescription ?? "-") pip=\(pipController?.isPictureInPictureActive ?? false)/\(pipController?.isPictureInPicturePossible ?? false)")
    }

    // MARK: - AVPictureInPictureControllerDelegate

    func pictureInPictureControllerDidStartPictureInPicture(_ controller: AVPictureInPictureController) {
        isPipActive = true
        endPipBackgroundTask()
        setForceComposite(true)
        logLayerState("pip-start")
        zdLog("[PiP] started")
    }

    func pictureInPictureControllerDidStopPictureInPicture(_ controller: AVPictureInPictureController) {
        isPipActive = false
        setForceComposite(false)
        videoLayer.flush()
        logLayerState("pip-stop")
        if pipStopForForeground {
            pipStopForForeground = false
        } else {
            // The user closed the floating window: stop playback.
            pausePlayback()
        }
        zdLog("[PiP] stopped")
    }

    func pictureInPictureController(
        _ controller: AVPictureInPictureController,
        failedToStartPictureInPictureWithError error: Error
    ) {
        zdLog("[PiP] failed to start: \(error)")
    }

    // MARK: - AVPictureInPictureSampleBufferPlaybackDelegate

    func pictureInPictureController(_ controller: AVPictureInPictureController, setPlaying playing: Bool) {
        if playing {
            playPlayback()
        } else {
            pausePlayback()
        }
    }

    func pictureInPictureController(
        _ controller: AVPictureInPictureController,
        didTransitionToRenderSize newSize: CMVideoDimensions
    ) {}

    func pictureInPictureController(
        _ controller: AVPictureInPictureController,
        skipByInterval skipInterval: CMTime,
        completion: @escaping () -> Void
    ) {
        let milliseconds = Int64((skipInterval.seconds * 1000).rounded())
        if milliseconds != 0 {
            seekByMs(milliseconds)
        }
        completion()
    }

    func pictureInPictureControllerIsPlaybackPaused(_ controller: AVPictureInPictureController) -> Bool {
        return !isPlayerPlaying
    }

    func pictureInPictureControllerTimeRangeForPlayback(
        _ controller: AVPictureInPictureController
    ) -> CMTimeRange {
        let durationSeconds = Double(durationMs) / 1000.0
        if durationSeconds > 0 {
            lastKnownDurationSeconds = durationSeconds
        }
        // Always expose a finite, seekable range so the PiP window consistently
        // shows a scrubber and never the live/"direct" mode on this VOD player.
        let useSeconds = durationSeconds > 0
            ? durationSeconds
            : (lastKnownDurationSeconds > 0 ? lastKnownDurationSeconds : 3600)
        return CMTimeRange(start: .zero, duration: CMTime(seconds: useSeconds, preferredTimescale: 600))
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        addPlaybackObservers()
        // The system may only auto-start PiP from a controller whose screen is
        // actually visible; stale (pushed-back) player screens must stay out.
        pipController?.canStartPictureInPictureAutomaticallyFromInline = true
        refreshImmersiveSystemUI()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        layoutVideoLayer()
        attemptStartPendingLoad()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        setupPictureInPicture(reason: "viewDidAppear")
        zdLog(pipProxyDiagnostics("viewDidAppear"))
        SystemUI.shared.playerDidBecomeVisible(self)
        refreshImmersiveSystemUI()
        becomeFirstResponder()
        UIApplication.shared.beginReceivingRemoteControlEvents()
        publishCachedNowPlayingInfoIfNeeded()
        syncVideoSurfaceLayout()
        attemptStartPendingLoad()
    }

    override func viewWillDisappear(_ animated: Bool) {
        removePlaybackObservers()
        pipController?.canStartPictureInPictureAutomaticallyFromInline = false
        SystemUI.shared.playerDidBecomeHidden(self)
        super.viewWillDisappear(animated)
    }

    override func didMove(toParent parent: UIViewController?) {
        super.didMove(toParent: parent)
        if parent == nil {
            SystemUI.shared.playerDidBecomeHidden(self)
        }
    }

    override func viewSafeAreaInsetsDidChange() {
        super.viewSafeAreaInsetsDidChange()
        syncVideoSurfaceLayout()
        refreshImmersiveSystemUI()
        attemptStartPendingLoad()
    }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)

        syncVideoSurfaceLayoutNow(scheduleDeferredPasses: false)
        coordinator.animate(alongsideTransition: { [weak self] _ in
            self?.syncVideoSurfaceLayoutNow(scheduleDeferredPasses: false)
        }, completion: { [weak self] _ in
            self?.syncVideoSurfaceLayout()
            self?.attemptStartPendingLoad()
        })
    }

    func syncVideoSurfaceLayout(size: CGSize) {
        if Thread.isMainThread {
            syncVideoSurfaceLayoutNow(size: size, scheduleDeferredPasses: true)
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.syncVideoSurfaceLayoutNow(size: size, scheduleDeferredPasses: true)
            }
        }
    }

    private func syncVideoSurfaceLayout() {
        if Thread.isMainThread {
            syncVideoSurfaceLayoutNow(size: nil, scheduleDeferredPasses: true)
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.syncVideoSurfaceLayoutNow(size: nil, scheduleDeferredPasses: true)
            }
        }
    }

    private func syncVideoSurfaceLayoutNow(size: CGSize? = nil, scheduleDeferredPasses: Bool) {
        guard isViewLoaded else { return }
        if let size, size.width > 1, size.height > 1 {
            externallyManagedViewSize = size
            applyExternallyManagedViewSize(size)
        }
        view.setNeedsLayout()
        view.layoutIfNeeded()
        layoutVideoLayer()

        if scheduleDeferredPasses {
            scheduleDeferredSurfaceLayoutPasses()
        }
    }

    private func scheduleDeferredSurfaceLayoutPasses() {
        pendingSurfaceLayoutWorkItems.forEach { $0.cancel() }
        pendingSurfaceLayoutWorkItems.removeAll(keepingCapacity: true)

        [0.0, 0.05, 0.15, 0.35].forEach { delay in
            let workItem = DispatchWorkItem { [weak self] in
                self?.syncVideoSurfaceLayoutNow(scheduleDeferredPasses: false)
            }
            pendingSurfaceLayoutWorkItems.append(workItem)
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
        }
    }

    private func applyExternallyManagedViewSize(_ size: CGSize) {
        let targetBounds = CGRect(origin: .zero, size: size)
        if view.bounds != targetBounds {
            view.bounds = targetBounds
        }

        var targetFrame = view.frame
        if targetFrame.size != size {
            targetFrame.size = size
            view.frame = targetFrame
        }
    }

    private func layoutVideoLayer() {
        let bounds = CGRect(origin: .zero, size: externallyManagedViewSize ?? view.bounds.size)
        guard bounds.width > 1, bounds.height > 1 else { return }

        let scale = view.window?.screen.nativeScale ?? UIScreen.main.nativeScale

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        videoLayer.contentsScale = scale
        videoLayer.position = .zero
        videoLayer.bounds = CGRect(origin: .zero, size: bounds.size)
        CATransaction.commit()
    }

    // MARK: - MPV Setup

    private func setupMpv() {
        installLavfWhitelistConfig()
        mpv = mpv_create()
        guard mpv != nil else {
            zdLog("[MPV] Failed to create mpv instance")
            return
        }

        checkError(mpv_request_log_messages(mpv, "warn"))

        var layerPointer = Int64(Int(bitPattern: Unmanaged.passUnretained(videoLayer).toOpaque()))
        checkError(mpv_set_option(mpv, "wid", MPV_FORMAT_INT64, &layerPointer))
        checkError(mpv_set_option_string(mpv, "vo", "avfoundation"))
        // Keep the video path zero-copy: composite OSD runs a CoreImage pass over
        // every frame while subtitles are visible and upscales to display
        // resolution, which stutters badly in Picture in Picture (the GPU is
        // throttled in the background). Subtitles render inline via the VO's
        // OSD layer instead.
        checkError(mpv_set_option_string(mpv, "avfoundation-composite-osd", "no"))
        checkError(mpv_set_option_string(mpv, "hwdec", "videotoolbox"))
        checkError(mpv_set_option_string(mpv, "ao", Self.defaultAudioOutput))
        checkError(mpv_set_option_string(mpv, "audio-channels", "auto"))
        checkError(mpv_set_option_string(mpv, "audio-fallback-to-null", "yes"))
        checkError(mpv_set_option_string(mpv, "video-rotate", "no"))
        checkError(mpv_set_option_string(mpv, "subs-match-os-language", "yes"))
        checkError(mpv_set_option_string(mpv, "subs-fallback", "yes"))
        configureBundledSubtitleFont()
        checkError(mpv_set_option_string(mpv, "keep-open", "yes"))
        checkError(mpv_set_option_string(mpv, "target-colorspace-hint", "yes"))
        checkError(mpv_set_option_string(mpv, "tone-mapping", "auto"))
        checkError(mpv_set_option_string(mpv, "hdr-compute-peak", "yes"))
        setLavfNestedProtocolWhitelist()

        checkError(mpv_initialize(mpv))
        applyAudioLanguagePreferences(preferredAudioLanguages)

        // Observe properties
        mpv_observe_property(mpv, 0, "pause", MPV_FORMAT_FLAG)
        mpv_observe_property(mpv, 0, "paused-for-cache", MPV_FORMAT_FLAG)
        mpv_observe_property(mpv, 0, "core-idle", MPV_FORMAT_FLAG)
        mpv_observe_property(mpv, 0, "eof-reached", MPV_FORMAT_FLAG)
        mpv_observe_property(mpv, 0, "seeking", MPV_FORMAT_FLAG)
        mpv_observe_property(mpv, 0, "track-list", MPV_FORMAT_NODE)
        mpv_observe_property(mpv, 0, "aid", MPV_FORMAT_INT64)

        mpv_set_wakeup_callback(mpv, { ctx in
            let vc = unsafeBitCast(ctx, to: MPVPlayerViewController.self)
            vc.readEvents()
        }, UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()))
    }

    private func configureBundledSubtitleFont() {
        guard let fontURL = Bundle.main.url(
            forResource: "NotoSansCJKsc-Regular",
            withExtension: "otf"
        ) else {
            zdLog("[MPV] Bundled CJK subtitle font is missing")
            return
        }

        let fontDirectory = fontURL.deletingLastPathComponent().path
        fontDirectory.withCString { path in
            checkError(mpv_set_option_string(mpv, "sub-fonts-dir", path))
        }
        checkError(mpv_set_option_string(mpv, "sub-font", "Noto Sans CJK SC"))
        zdLog("[MPV] Using bundled CJK subtitle font: \(fontURL.lastPathComponent)")
    }

    // MARK: - HLS local-playlist nested-protocol whitelist (build 141)

    /// FFmpeg's file:// protocol only allows nested "file,crypto,data" resources
    /// by default (libavformat/file.c default_whitelist), so a sanitized local
    /// HLS playlist cannot open its remote https segments: the hls demuxer fails
    /// and mpv falls back to demuxing the playlist as a plain list of segment
    /// files (segment-by-segment playback, tiny durations). Desktop mpv avoids
    /// this with its curl-based nested I/O; MPVKit's libmpv v0.41.0 does not
    /// have it, so widen the nested protocol whitelist explicitly.
    private static let lavfWhitelistPairs =
        "protocol_whitelist=file,http,https,tls,tcp,udp,rtp,crypto,data,httpproxy"

    /// Fallback mechanism: write an mpv.conf that the mpv core loads at
    /// initialize; the config parser supports "-append" with full values.
    private func installLavfWhitelistConfig() {
        guard let home = ProcessInfo.processInfo.environment["HOME"] else { return }
        let dir = URL(fileURLWithPath: home).appendingPathComponent(".config/mpv", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let conf = dir.appendingPathComponent("mpv.conf")
        let text = "demuxer-lavf-o-append=\(Self.lavfWhitelistPairs)\n"
        try? text.write(to: conf, atomically: true, encoding: .utf8)
    }

    /// Primary mechanism: set demuxer-lavf-o through the option API with a node
    /// map (key/value list with string values; commas stay intact because the
    /// map path copies pairs verbatim). Must run before mpv_initialize.
    private func setLavfNestedProtocolWhitelist() {
        guard let mpv = mpv else { return }
        guard let key = strdup("protocol_whitelist"),
              let value = strdup(Self.lavfWhitelistPairs) else { return }
        defer {
            free(key)
            free(value)
        }

        let keys = UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>.allocate(capacity: 1)
        keys[0] = key
        defer { keys.deallocate() }

        let values = UnsafeMutablePointer<mpv_node>.allocate(capacity: 1)
        values[0] = mpv_node()
        values[0].format = MPV_FORMAT_STRING
        withUnsafeMutableBytes(of: &values[0]) { raw in
            raw.storeBytes(of: value, toByteOffset: 0, as: UnsafeMutablePointer<CChar>.self)
        }
        defer { values.deallocate() }

        let list = UnsafeMutablePointer<mpv_node_list>.allocate(capacity: 1)
        list[0] = mpv_node_list()
        list[0].num = 1
        list[0].keys = keys
        list[0].values = values
        defer { list.deallocate() }

        var node = mpv_node()
        node.format = MPV_FORMAT_NODE_MAP
        withUnsafeMutableBytes(of: &node) { raw in
            raw.storeBytes(of: list, toByteOffset: 0, as: UnsafeMutablePointer<mpv_node_list>.self)
        }

        let err = mpv_set_option(mpv, "demuxer-lavf-o", MPV_FORMAT_NODE, &node)
        zdLog("[MPV] demuxer-lavf-o node set -> \(err)")
    }

    private func addPlaybackObservers() {
        // Idempotent: re-registering on every appearance.
        let center = NotificationCenter.default
        center.removeObserver(self, name: UIApplication.didEnterBackgroundNotification, object: nil)
        center.removeObserver(self, name: UIApplication.willEnterForegroundNotification, object: nil)
        center.removeObserver(self, name: UIApplication.didBecomeActiveNotification, object: nil)
        center.addObserver(self, selector: #selector(enterBackground),
                           name: UIApplication.didEnterBackgroundNotification, object: nil)
        center.addObserver(self, selector: #selector(enterForeground),
                           name: UIApplication.willEnterForegroundNotification, object: nil)
        center.addObserver(self, selector: #selector(appDidBecomeActive),
                           name: UIApplication.didBecomeActiveNotification, object: nil)
    }

    private func removePlaybackObservers() {
        let center = NotificationCenter.default
        center.removeObserver(self, name: UIApplication.didEnterBackgroundNotification, object: nil)
        center.removeObserver(self, name: UIApplication.willEnterForegroundNotification, object: nil)
        center.removeObserver(self, name: UIApplication.didBecomeActiveNotification, object: nil)
    }

    @objc private func enterBackground() {
        // Stale player screens (kept in the navigation stack) must not react:
        // their layer is off-screen and nudging their PiP controller fails with
        // -1001 and fights the active player for the floating window.
        guard mpv != nil, isViewLoaded, view.window != nil else { return }
        zdLog(pipProxyDiagnostics("enterBackground"))
        // Never disable the video track (vid=no) here: toggling it recreates the
        // whole video pipeline, breaks the VT decoder and leaves PiP black.
        guard isPlayerPlaying, let pip = pipController else {
            zdLog("[PiP] background while idle -> state left as-is")
            return
        }
        if pip.isPictureInPictureActive {
            zdLog("[PiP] background: PiP already active")
            return
        }

        zdLog("[PiP] background: active=\(pip.isPictureInPictureActive) possible=\(pip.isPictureInPicturePossible)")
        logLayerState("background")
        beginPipBackgroundTask()
        schedulePipNudge("background")
    }

    @objc private func enterForeground() {
        guard mpv != nil, isViewLoaded, view.window != nil else { return }
        zdLog(pipProxyDiagnostics("enterForeground"))
        pipFallbackWorkItem?.cancel()
        pipFallbackWorkItem = nil
        endPipBackgroundTask()
        var hadPip = false
        if let pip = pipController, pip.isPictureInPictureActive {
            hadPip = true
            pipStopForForeground = true
            pip.stopPictureInPicture()
        }
        videoLayer.flush()
        if hadPip {
            // Resume inline only when returning from an active PiP session;
            // otherwise keep whatever pause state the user had.
            playPlayback()
        }
        logLayerState("foreground")
    }

    // MARK: - Playback API

    func loadFile(_ urlString: String, audioUrl: String? = nil, requestHeaders: [String: String] = [:], subtitles: [PluginSubtitle] = []) {
        let request = PendingLoadRequest(
            urlString: urlString,
            audioUrl: audioUrl,
            requestHeaders: requestHeaders,
            subtitles: subtitles,
            queuedAtUptime: ProcessInfo.processInfo.systemUptime
        )

        if Thread.isMainThread {
            queueLoad(request)
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.queueLoad(request)
            }
        }
    }

    private func queueLoad(_ request: PendingLoadRequest) {
        pendingLoadRequest = request
        attemptStartPendingLoad()
    }

    private func attemptStartPendingLoad() {
        guard let request = pendingLoadRequest else { return }
        guard mpv != nil else { return }
        layoutVideoLayer()
        guard isViewportReadyForPlayback(queuedAtUptime: request.queuedAtUptime) else {
            schedulePendingLoadRetry()
            return
        }

        pendingLoadRequest = nil
        pendingLoadRetryWorkItem?.cancel()
        pendingLoadRetryWorkItem = nil
        startLoad(request)
    }

    private func startLoad(_ request: PendingLoadRequest) {
        if mpv == nil {
            // The backend may have been torn down while the view controller
            // survived (episode switches): bring it up again.
            setupMpv()
        }
        guard mpv != nil else { return }
        layoutVideoLayer()
        clearPlaybackError()
        let sanitizedHeaders = sanitizeRequestHeaders(request.requestHeaders)
        activeRequestHeaders = sanitizedHeaders
        applyRequestHeaders(sanitizedHeaders)
        isPlayerLoading = true
        isPlayerEnded = false
        applyAudioLanguagePreferences(preferredAudioLanguages)
        resetDiscontinuityGuard()
        // Fresh video-output state for the new file: re-enable the video track
        // and drop any queued frames from the previous episode.
        setStringProperty("vid", "auto")
        videoLayer.flush()
        logLayerState("pre-load")
        // Sanitize sloppy ad-spliced HLS playlists (e.g. KKPhim/phimapi) so mpv
        // keeps playing across discontinuities instead of resetting to 0.
        // Falls back to the original URL on any failure.
        HLSPlaylistSanitizer.shared.sanitizedURL(
            for: request.urlString,
            headers: sanitizedHeaders
        ) { [weak self] finalURL in
            guard let self else { return }
            guard self.mpv != nil else { return }
            // Sanitized playlists are loaded from local files, and FFmpeg's file
            // protocol only permits nested "file,crypto,data" resources by
            // default (libavformat/file.c). Their remote https segments would be
            // refused and mpv would demux the playlist as a plain list of
            // segment files (segment-by-segment playback, tiny durations,
            // stutter). Desktop mpv avoids this via its curl-based nested I/O;
            // MPVKit's libmpv v0.41.0 does not have it. Widen the whitelist for
            // nested URL opens so local playlists can reach their segments.
            if finalURL != request.urlString {
                self.timelineHoles = HLSPlaylistSanitizer.lastHoles.map {
                    TimelineHole(start: $0.start, size: $0.size)
                }
                zdLog("[MPV] timeline holes: \(self.timelineHoles.count)")
                self.command(
                    "change-list",
                    args: [
                        "demuxer-lavf-o",
                        "append",
                        Self.lavfWhitelistPairs
                    ],
                    checkForErrors: false
                )
            } else {
                self.timelineHoles = []
            }
            self.command("loadfile", args: [finalURL, "replace"])
        }
        if let audioUrl = request.audioUrl, !audioUrl.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                self?.command("audio-add", args: [audioUrl, "select"], checkForErrors: false)
            }
        }

        for subtitle in request.subtitles {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                self?.addSubtitle(subtitle, mode: "auto")
            }
        }
    }

    private func isViewportReadyForPlayback(queuedAtUptime: TimeInterval) -> Bool {
        guard isViewLoaded, view.window != nil else { return false }
        let bounds = view.bounds
        guard bounds.width > 1, bounds.height > 1 else { return false }
        if bounds.width >= bounds.height { return true }

        let age = ProcessInfo.processInfo.systemUptime - queuedAtUptime
        return age >= 0.9
    }

    private func schedulePendingLoadRetry() {
        guard pendingLoadRetryWorkItem == nil else { return }

        let workItem = DispatchWorkItem { [weak self] in
            self?.pendingLoadRetryWorkItem = nil
            self?.attemptStartPendingLoad()
        }
        pendingLoadRetryWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: workItem)
    }

    func playPlayback() {
        guard mpv != nil else { return }
        publishNowPlayingForPlaybackSession()
        setFlag("pause", false)
        isPlayerPlaying = true
        syncNowPlayingPlaybackState(isPlaying: true)
        pipController?.invalidatePlaybackState()
        if UIApplication.shared.applicationState == .background {
            // Playback started/restarted while backgrounded (e.g. a load
            // finished): make sure a PiP window comes up, or pause instead.
            schedulePipNudge("play-in-background")
        }
    }

    /// The system starts PiP itself (canStartPictureInPictureAutomaticallyFromInline).
    /// Manual startPictureInPicture() nudges raced with that start and failed
    /// with -1001, sometimes cancelling the system's own attempt (PiP then only
    /// came up on a second try). Keep only the safety net: pause if no PiP
    /// window came up, so audio never keeps playing in the background without a
    /// video view. Never touches the video track (vid): toggling it recreates
    /// the whole video pipeline.
    private func schedulePipNudge(_ reason: String) {
        pipFallbackWorkItem?.cancel()
        let pauseWork = DispatchWorkItem { [weak self] in
            guard let self else { return }
            guard UIApplication.shared.applicationState == .background, !self.isPipActive else { return }
            zdLog("[PiP] no PiP after backgrounding (\(reason)) - pausing")
            self.pausePlayback()
            self.endPipBackgroundTask()
            self.logLayerState("background-no-pip")
        }
        pipFallbackWorkItem = pauseWork
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.5, execute: pauseWork)
    }

    /// Keep the process running briefly while the app transitions to the
    /// background so iOS does not invalidate the VideoToolbox decode session
    /// before PiP takes over (invalid sessions force a software-decode fallback).
    private func beginPipBackgroundTask() {
        guard pipBackgroundTask == .invalid else { return }
        pipBackgroundTask = UIApplication.shared.beginBackgroundTask(withName: "pip-transition") { [weak self] in
            guard let self else { return }
            zdLog("[PiP] background task expired")
            self.endPipBackgroundTask()
        }
        zdLog("[PiP] background task started")
        // Safety: never hold the task for more than ~12s.
        DispatchQueue.main.asyncAfter(deadline: .now() + 12.0) { [weak self] in
            self?.endPipBackgroundTask()
        }
    }

    private func endPipBackgroundTask() {
        guard pipBackgroundTask != .invalid else { return }
        UIApplication.shared.endBackgroundTask(pipBackgroundTask)
        pipBackgroundTask = .invalid
    }

    func pausePlayback() {
        guard mpv != nil else { return }
        setFlag("pause", true)
        isPlayerPlaying = false
        syncNowPlayingPlaybackState(isPlaying: false)
        pipController?.invalidatePlaybackState()
    }

    func seekToMs(_ ms: Int64) {
        guard mpv != nil else { return }
        let rawSeconds = rawPosition(fromUI: Double(ms) / 1000.0)
        zdLog("[MPV] seekToMs ui=\(ms)ms raw=\(String(format: "%.3f", rawSeconds))s")
        muteHoleDetection(for: 3)
        command("seek", args: [String(format: "%.3f", rawSeconds), "absolute"])
    }

    func seekByMs(_ ms: Int64, exact: Bool = false) {
        guard mpv != nil else { return }
        let rawNow = max(getDouble("time-pos"), 0)
        let targetUI = uiPosition(fromRaw: rawNow) + Double(ms) / 1000.0
        let rawTarget = rawPosition(fromUI: max(targetUI, 0))
        zdLog("[MPV] seekByMs off=\(ms)ms raw=\(String(format: "%.3f", rawTarget))s (mode=\(exact ? "exact" : "normal"))")
        muteHoleDetection(for: 3)
        let seekMode = exact ? "absolute+exact" : "absolute"
        command("seek", args: [String(format: "%.3f", rawTarget), seekMode])
    }

    func retryPlayback() {
        guard mpv != nil else { return }
        if let path = getString("path") {
            clearPlaybackError()
            applyRequestHeaders(activeRequestHeaders)
            let pos = getDouble("time-pos")
            muteHoleDetection(for: 5)
            command("loadfile", args: [path, "replace"])
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.command("seek", args: [String(format: "%.3f", pos), "absolute"])
            }
        }
    }

    func configureVideoOutput(
        hardwareDecoder: String,
        targetColorspaceHint: Bool,
        toneMapping: String,
        hdrComputePeak: Bool,
        targetPrimaries: String,
        targetTransfer: String,
        extendedDynamicRange: Bool,
        deband: Bool,
        interpolation: Bool,
        brightness: Int,
        contrast: Int,
        saturation: Int,
        gamma: Int
    ) {
        // Extended dynamic range is handled by AVFoundation for the avfoundation output.
        guard mpv != nil else { return }

        setStringProperty("hwdec", hardwareDecoder)
        setStringProperty("target-colorspace-hint", targetColorspaceHint ? "yes" : "no")
        setStringProperty("tone-mapping", toneMapping)
        setStringProperty("hdr-compute-peak", hdrComputePeak ? "yes" : "no")
        setStringProperty("target-prim", targetPrimaries)
        setStringProperty("target-trc", targetTransfer)
        setStringProperty("deband", deband ? "yes" : "no")
        setStringProperty("interpolation", interpolation ? "yes" : "no")
        setVideoEqualizer("brightness", brightness)
        setVideoEqualizer("contrast", contrast)
        setVideoEqualizer("saturation", saturation)
        setVideoEqualizer("gamma", gamma)
    }

    func configureAudioOutput(audioOutput: String) {
        guard mpv != nil else { return }
        let resolvedAudioOutput: String
        if audioOutput.contains("avfoundation") {
            resolvedAudioOutput = Self.defaultAudioOutput
        } else {
            resolvedAudioOutput = audioOutput
        }
        setStringProperty("ao", resolvedAudioOutput)
    }

    func setSpeed(_ speed: Float) {
        guard mpv != nil else { return }
        var s = Double(speed)
        mpv_set_property(mpv, "speed", MPV_FORMAT_DOUBLE, &s)
    }

    func setMuted(_ muted: Bool) {
        guard mpv != nil else { return }
        setFlag("mute", muted)
    }

    func setResize(_ mode: Int) {
        guard mpv != nil else { return }
        switch mode {
        case 1: // Fill
            setStringProperty("panscan", "1.0")
            setStringProperty("video-unscaled", "no")
        case 2: // Zoom
            setStringProperty("panscan", "1.0")
            setStringProperty("video-unscaled", "no")
        default: // Fit
            setStringProperty("panscan", "0.0")
            setStringProperty("video-unscaled", "no")
        }
    }

    // MARK: - Track selection

    func selectAudio(_ trackId: Int) {
        guard mpv != nil else { return }
        var id = Int64(trackId)
        mpv_set_property(mpv, "aid", MPV_FORMAT_INT64, &id)
    }

    func applyAudioLanguagePreferences(_ languages: [String]) {
        preferredAudioLanguages = languages
        guard mpv != nil else { return }
        setStringProperty("alang", languages.joined(separator: ","))
        if let currentId = getString("aid"), Int(currentId) != nil {
            setStringProperty("aid", currentId)
        }
        setStringProperty("aid", "auto")
    }

    func selectSubtitle(_ trackId: Int) {
        guard mpv != nil else { return }
        if trackId < 0 {
            setStringProperty("sid", "no")
        } else {
            var id = Int64(trackId)
            mpv_set_property(mpv, "sid", MPV_FORMAT_INT64, &id)
        }
    }

    func addSubtitleUrl(_ url: String) {
        guard mpv != nil else { return }
        command("sub-add", args: [url, "select"])
    }

    private func addSubtitle(_ subtitle: PluginSubtitle, mode: String) {
        guard mpv != nil else { return }
        let subtitleHeaders = sanitizeRequestHeaders(subtitle.headers ?? [:])
        let previousHeaders = activeRequestHeaders

        if !subtitleHeaders.isEmpty {
            applyRequestHeaders(previousHeaders.merging(subtitleHeaders) { _, subtitleValue in subtitleValue })
        }

        command(
            "sub-add",
            args: [subtitle.url, mode, subtitle.name ?? subtitle.language, subtitle.language],
            checkForErrors: false
        )

        if !subtitleHeaders.isEmpty {
            applyRequestHeaders(previousHeaders)
        }
    }

    func removeExternalSubtitles() {
        guard mpv != nil else { return }
        let count = getInt("track-list/count")
        for i in stride(from: count - 1, through: 0, by: -1) {
            let type = getString("track-list/\(i)/type") ?? ""
            let external = getFlag("track-list/\(i)/external")
            if type == "sub" && external {
                let id = getInt("track-list/\(i)/id")
                command("sub-remove", args: ["\(id)"], checkForErrors: false)
            }
        }
        setStringProperty("sid", "no")
    }

    func removeExternalSubtitlesAndSelect(_ trackId: Int) {
        guard mpv != nil else { return }
        let count = getInt("track-list/count")
        for i in stride(from: count - 1, through: 0, by: -1) {
            let type = getString("track-list/\(i)/type") ?? ""
            let external = getFlag("track-list/\(i)/external")
            if type == "sub" && external {
                let id = getInt("track-list/\(i)/id")
                command("sub-remove", args: ["\(id)"], checkForErrors: false)
            }
        }
        if trackId >= 0 {
            selectSubtitle(trackId)
        } else {
            setStringProperty("sid", "no")
        }
    }

    func setSubtitleDelayMs(_ delayMs: Int) {
        guard mpv != nil else { return }
        var delaySeconds = Double(max(-60_000, min(60_000, delayMs))) / 1000.0
        checkError(mpv_set_property(mpv, "sub-delay", MPV_FORMAT_DOUBLE, &delaySeconds))
    }

    func applySubtitleStyle(
        textColor: String,
        backgroundColor: String,
        outlineColor: String,
        outlineSize: Float,
        bold: Bool,
        fontSize: Float,
        subPos: Int,
        stripSdh: Bool
    ) {
        guard mpv != nil else { return }

        checkError(mpv_set_property_string(mpv, "sub-ass-override", "no"))
        checkError(mpv_set_property_string(mpv, "sub-color", textColor))
        checkError(mpv_set_property_string(mpv, "sub-back-color", backgroundColor))
        checkError(mpv_set_property_string(mpv, "sub-outline-color", outlineColor))
        checkError(mpv_set_property_string(mpv, "sub-border-style", backgroundColor.hasPrefix("#00") ? "outline-and-shadow" : "opaque-box"))
        setStringProperty("sub-bold", bold ? "yes" : "no")

        var outline = Double(outlineSize)
        checkError(mpv_set_property(mpv, "sub-outline-size", MPV_FORMAT_DOUBLE, &outline))

        var size = Double(fontSize)
        checkError(mpv_set_property(mpv, "sub-font-size", MPV_FORMAT_DOUBLE, &size))

        var position = Int64(subPos)
        checkError(mpv_set_property(mpv, "sub-pos", MPV_FORMAT_INT64, &position))
        setStringProperty("sub-filter-sdh", stripSdh ? "yes" : "no")
        setStringProperty("sub-filter-sdh-harder", stripSdh ? "yes" : "no")
    }

    func destroyPlayer() {
        NotificationCenter.default.removeObserver(self)
        UIApplication.shared.endReceivingRemoteControlEvents()
        resignFirstResponder()
        pendingLoadRetryWorkItem?.cancel()
        pendingLoadRetryWorkItem = nil
        pendingSurfaceLayoutWorkItems.forEach { $0.cancel() }
        pendingSurfaceLayoutWorkItems.removeAll(keepingCapacity: false)
        pendingLoadRequest = nil
        nowPlayingController.invalidate()
        clearPlaybackError()
        deactivateAudioSession()
        guard let ctx = mpv else { return }
        mpv = nil  // nil first so event loop stops reading
        mpv_terminate_destroy(ctx)
    }

    private func activateAudioSessionForPlayback() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .moviePlayback, options: [.mixWithOthers])
            try session.setActive(true)
        } catch {
            print("[NowPlaying] Failed to activate audio session: \(error)")
        }
    }

    private func deactivateAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        } catch {
            print("[NowPlaying] Failed to deactivate audio session: \(error)")
        }
    }

    // MARK: - State Update

    /// Lightweight state refresh — called by Kotlin polling (every 250ms).
    /// Only reads cheap scalar properties; does NOT re-enumerate tracks.
    func refreshPlaybackState() {
        guard mpv != nil else { return }
        let duration = getDouble("duration")
        let position = getDouble("time-pos")
        let cached = getDouble("demuxer-cache-time")
        let speed = getDouble("speed")
        let paused = getFlag("pause")
        let eofReached = getFlag("eof-reached")
        let idle = getFlag("core-idle")
        let seeking = getFlag("seeking")
        let bufferingCache = getFlag("paused-for-cache")

        isPlayerLoading = (idle && !paused && !eofReached) || seeking || bufferingCache
        isPlayerPlaying = !paused && !idle && !eofReached
        isPlayerEnded = eofReached

        let rawPosition = max(position, 0)
        detectTimelineHoleCrossing(raw: rawPosition, seeking: seeking, paused: paused)
        previousPollWasPaused = paused
        durationMs = Int64(max(duration - totalHoleSeconds, 0) * 1000)
        positionMs = Int64(uiPosition(fromRaw: rawPosition) * 1000)
        bufferedMs = Int64(uiPosition(fromRaw: max(position + cached, 0)) * 1000)
        currentSpeed = Float(speed > 0 ? speed : 1.0)

        let shouldPublishNowPlayingState = !isPlayerLoading || isPlayerPlaying || durationMs > 0 || positionMs > 0
        if shouldPublishNowPlayingState {
            syncNowPlayingPlaybackState(isPlaying: isPlayerPlaying)
        }

        guardDiscontinuityReset(seeking: seeking, eofReached: eofReached)
    }

    /// Safety net for ad-spliced HLS: mpv can reset time-pos to ~0 when it hits
    /// a discontinuity instead of playing through. Detect the sudden drop and
    /// seek back to the last good position (max 3 rescues per load).
    private func guardDiscontinuityReset(seeking: Bool, eofReached: Bool) {
        defer {
            previousPollPositionMs = positionMs
            previousPollWasPlaying = isPlayerPlaying
        }

        if positionMs > lastGoodPositionMs {
            lastGoodPositionMs = positionMs
        }

        let now = ProcessInfo.processInfo.systemUptime
        let suddenDrop = previousPollWasPlaying
            && !seeking
            && !eofReached
            && previousPollPositionMs - positionMs > 20_000
            && positionMs < 2_000
            && lastGoodPositionMs > 30_000
            && durationMs > 60_000
            && discontinuityRescuesUsed < 3
            && now >= discontinuityRescueCooldownUntil

        guard suddenDrop else { return }

        discontinuityRescuesUsed += 1
        discontinuityRescueCooldownUntil = now + 5
        let rescueMs = lastGoodPositionMs
        zdLog("[MPV] Discontinuity reset detected (\(previousPollPositionMs) -> \(positionMs)), rescuing to \(rescueMs) (attempt \(discontinuityRescuesUsed))")
        if Thread.isMainThread {
            seekToMs(rescueMs)
        } else {
            DispatchQueue.main.async { [weak self] in self?.seekToMs(rescueMs) }
        }
    }

    // MARK: - Timeline healing (removed ad gaps)

    private var totalHoleSeconds: Double {
        timelineHoles.reduce(0) { $0 + $1.size }
    }

    /// Raw (presentation) position -> user-facing continuous position.
    private func uiPosition(fromRaw raw: Double) -> Double {
        guard !timelineHoles.isEmpty, raw > 0 else { return raw }
        var ui = raw
        for hole in timelineHoles where hole.observed && raw > hole.start {
            ui -= hole.size
        }
        return max(ui, 0)
    }

    /// User-facing position -> raw seek target. Holes the target passes become
    /// observed so the clock stays consistent after the seek lands.
    private func rawPosition(fromUI ui: Double) -> Double {
        guard !timelineHoles.isEmpty else { return max(ui, 0) }
        var raw = max(ui, 0)
        for _ in 0..<4 {
            var next = max(ui, 0)
            for (index, hole) in timelineHoles.enumerated() where raw > hole.start {
                next += hole.size
                timelineHoles[index].observed = true
            }
            if abs(next - raw) < 0.001 {
                raw = next
                break
            }
            raw = next
        }
        return raw
    }

    private func muteHoleDetection(for seconds: TimeInterval) {
        holeDetectionMuteUntil = ProcessInfo.processInfo.systemUptime + seconds
    }

    /// Playback crossing a removed-ad gap makes raw time-pos jump forward by
    /// the gap size; pin the matching hole to the exact crossing point.
    private func detectTimelineHoleCrossing(raw: Double, seeking: Bool, paused: Bool) {
        defer { previousRawPosition = raw }
        let now = ProcessInfo.processInfo.systemUptime
        guard now >= holeDetectionMuteUntil else { return }
        guard !seeking, !paused, !previousPollWasPaused else { return }
        let delta = raw - previousRawPosition
        guard delta > 5.0, raw > 120, previousRawPosition > 30 else { return }
        if let index = timelineHoles.firstIndex(where: {
            $0.start <= previousRawPosition + 2.0 && $0.start >= previousRawPosition - 30.0
        }) {
            timelineHoles[index].start = previousRawPosition
            timelineHoles[index].size = delta
            timelineHoles[index].observed = true
            zdLog("[MPV] timeline hole \(index) observed at \(previousRawPosition) size \(delta)")
        } else {
            timelineHoles.append(TimelineHole(start: previousRawPosition, size: delta, observed: true))
            zdLog("[MPV] timeline hole (unknown) observed at \(previousRawPosition) size \(delta)")
        }
    }

    private func syncNowPlayingPlaybackState(isPlaying: Bool) {
        nowPlayingController.syncPlayback(
            positionMs: positionMs,
            durationMs: durationMs,
            isPlaying: isPlaying,
            playbackSpeed: currentSpeed
        )
    }

    /// Full state + track refresh — called from MPV event loop on property changes.
    func updateState() {
        refreshPlaybackState()
        refreshTracks()
    }

    private func refreshTracks() {
        guard mpv != nil else { return }
        var audio = [TrackInfo]()
        var subs = [TrackInfo]()
        let count = getInt("track-list/count")
        var audioIdx = 0
        var subIdx = 0

        for i in 0..<count {
            let type = getString("track-list/\(i)/type") ?? ""
            let id = getInt("track-list/\(i)/id")
            let title = getTrackString(i, "title")
            let lang = getTrackString(i, "lang")
            let codec = getTrackString(i, "codec")
            let decoderDescription = getTrackString(i, "decoder-desc")
            let channels = getTrackString(i, "demux-channels")
            let channelCount = getInt("track-list/\(i)/demux-channel-count")
            let selected = getFlag("track-list/\(i)/selected")
            let displayTitle = formatTrackTitle(
                type: type,
                index: type == "audio" ? audioIdx : subIdx,
                title: title,
                lang: lang,
                codec: codec,
                decoderDescription: decoderDescription,
                channels: channels,
                channelCount: channelCount
            )

            if type == "audio" {
                audio.append(TrackInfo(index: audioIdx, id: id, type: type, title: displayTitle, lang: lang, selected: selected))
                audioIdx += 1
            } else if type == "sub" {
                subs.append(TrackInfo(index: subIdx, id: id, type: type, title: displayTitle, lang: lang, selected: selected))
                subIdx += 1
            }
        }
        audioTracks = audio
        subtitleTracks = subs
    }

    func updateNowPlayingMetadata(
        title: String,
        subtitle: String?,
        artworkUrl: String?
    ) {
        cachedNowPlayingMetadata = CachedNowPlayingMetadata(
            title: title,
            subtitle: subtitle,
            artworkUrl: artworkUrl
        )
        nowPlayingController.updateMetadata(
            title: title,
            subtitle: subtitle,
            artworkUrl: artworkUrl
        )
        publishNowPlayingForPlaybackSession()
    }

    func clearNowPlayingInfo() {
        cachedNowPlayingMetadata = nil
        nowPlayingController.clear()
    }

    private func publishCachedNowPlayingInfoIfNeeded() {
        guard let metadata = cachedNowPlayingMetadata else { return }
        nowPlayingController.updateMetadata(
            title: metadata.title,
            subtitle: metadata.subtitle,
            artworkUrl: metadata.artworkUrl
        )
    }

    private func publishNowPlayingForPlaybackSession() {
        activateAudioSessionForPlayback()
        if isViewLoaded, view.window != nil {
            becomeFirstResponder()
        }
        UIApplication.shared.beginReceivingRemoteControlEvents()
        publishCachedNowPlayingInfoIfNeeded()
        syncNowPlayingPlaybackState(isPlaying: isPlayerPlaying)
    }

    private func getTrackString(_ index: Int, _ field: String) -> String {
        (getString("track-list/\(index)/\(field)") ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func formatTrackTitle(
        type: String,
        index: Int,
        title: String,
        lang: String,
        codec: String,
        decoderDescription: String,
        channels: String,
        channelCount: Int
    ) -> String {
        let base = ifNotBlank(title)
            ?? localizedLanguageName(lang)
            ?? (type == "sub" ? "Subtitle \(index + 1)" : "Track \(index + 1)")
        let codecName = codecDisplayName(codec) ?? codecDisplayName(decoderDescription)
        let channelName = type == "audio" ? channelLayoutName(channels: channels, channelCount: channelCount) : nil
        let details = [channelName, codecName]
            .compactMap { $0 }
            .filter { detail in !base.localizedCaseInsensitiveContains(detail) }
        return details.isEmpty ? base : "\(base) (\(details.joined(separator: ", ")))"
    }

    private func ifNotBlank(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func localizedLanguageName(_ languageCode: String) -> String? {
        guard let code = ifNotBlank(languageCode) else { return nil }
        return Locale.current.localizedString(forLanguageCode: code) ?? code
    }

    private func channelLayoutName(channels: String, channelCount: Int) -> String? {
        if let normalized = ifNotBlank(channels), normalized != "unknown" {
            let lower = normalized.lowercased()
            if lower == "mono" { return "Mono" }
            if lower == "stereo" { return "Stereo" }
            return normalized
        }
        switch channelCount {
        case 1:
            return "Mono"
        case 2:
            return "Stereo"
        case 6:
            return "5.1"
        case 8:
            return "7.1"
        case let count where count > 0:
            return "\(count)ch"
        default:
            return nil
        }
    }

    private func codecDisplayName(_ value: String) -> String? {
        guard let raw = ifNotBlank(value) else { return nil }
        let codec = raw.lowercased()
        if codec.contains("eac3") || codec.contains("e-ac-3") || codec.contains("e ac-3") {
            return codec.contains("joc") || codec.contains("atmos") ? "E-AC-3-JOC" : "E-AC-3"
        }
        if codec.contains("truehd") || codec.contains("true hd") { return "TrueHD" }
        if codec.contains("ac3") || codec.contains("ac-3") { return "AC-3" }
        if codec.contains("dts-hd") || codec.contains("dtshd") || codec.contains("dts hd") { return "DTS-HD" }
        if codec.contains("dts") || codec == "dca" { return "DTS" }
        if codec.contains("aac") { return "AAC" }
        if codec.contains("mp3") || codec.contains("mpeg audio") { return "MP3" }
        if codec.contains("mp2") { return "MP2" }
        if codec.contains("opus") { return "Opus" }
        if codec.contains("vorbis") { return "Vorbis" }
        if codec.contains("flac") { return "FLAC" }
        if codec.contains("alac") { return "ALAC" }
        if codec.contains("pcm") || codec.contains("wav") { return "WAV" }
        if codec.contains("amr_wb") || codec.contains("amr-wb") { return "AMR-WB" }
        if codec.contains("amr_nb") || codec.contains("amr-nb") { return "AMR-NB" }
        if codec.contains("amr") { return "AMR" }
        if codec.contains("iamf") { return "IAMF" }
        if codec.contains("mpegh") || codec.contains("mpeg-h") { return "MPEG-H" }
        if codec.contains("pgs") || codec.contains("hdmv") { return "PGS" }
        if codec.contains("subrip") || codec == "srt" { return "SRT" }
        if codec.contains("ass") || codec.contains("ssa") { return "SSA" }
        if codec.contains("webvtt") || codec == "vtt" { return "VTT" }
        if codec.contains("ttml") { return "TTML" }
        if codec.contains("mov_text") || codec.contains("tx3g") { return "TX3G" }
        if codec.contains("dvb") { return "DVB" }
        return raw
    }

    private func clearPlaybackError() {
        errorStateLock.lock()
        recentPlaybackLogs.removeAll(keepingCapacity: true)
        _currentErrorMessage = nil
        errorStateLock.unlock()
    }

    private func appendPlaybackLog(prefix: String, level: String, text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard level == "warn" || level == "error" || level == "fatal" else { return }

        let formatted = "[\(prefix)] \(trimmed)"
        errorStateLock.lock()
        recentPlaybackLogs.append(formatted)
        if recentPlaybackLogs.count > 4 {
            recentPlaybackLogs.removeFirst(recentPlaybackLogs.count - 4)
        }
        errorStateLock.unlock()
    }

    private func setPlaybackError(_ fallback: String) {
        let trimmedFallback = fallback.trimmingCharacters(in: .whitespacesAndNewlines)
        errorStateLock.lock()
        var parts = recentPlaybackLogs.suffix(3)
        if !trimmedFallback.isEmpty && !parts.contains(trimmedFallback) {
            parts.append(trimmedFallback)
        }
        _currentErrorMessage = parts.isEmpty ? "Unable to play this stream." : parts.joined(separator: "\n")
        errorStateLock.unlock()
    }

    // MARK: - Event Loop

    private func readEvents() {
        eventQueue.async { [weak self] in
            guard let self, let mpv = self.mpv else { return }

            while true {
                let event = mpv_wait_event(mpv, 0)
                guard let eventPtr = event else { break }
                if eventPtr.pointee.event_id == MPV_EVENT_NONE { break }

                switch eventPtr.pointee.event_id {
                case MPV_EVENT_PROPERTY_CHANGE:
                    DispatchQueue.main.async { self.updateState() }
                case MPV_EVENT_FILE_LOADED:
                    DispatchQueue.main.async {
                        self.clearPlaybackError()
                        self.isPlayerLoading = false
                        self.updateState()
                        self.publishNowPlayingForPlaybackSession()
                        self.logCurrentAudioOutput()
                        self.logLayerState("file-loaded")
                        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in self?.logLayerState("file-loaded+3s") }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 8.0) { [weak self] in self?.logLayerState("file-loaded+8s") }
                    }
                case MPV_EVENT_PLAYBACK_RESTART:
                    DispatchQueue.main.async {
                        self.updateState()
                        self.publishNowPlayingForPlaybackSession()
                    }
                case MPV_EVENT_END_FILE:
                    if let data = eventPtr.pointee.data {
                        let endFile = UnsafePointer<mpv_event_end_file>(OpaquePointer(data)).pointee
                        if endFile.reason == MPV_END_FILE_REASON_ERROR {
                            let errorText = String(cString: mpv_error_string(endFile.error))
                            self.setPlaybackError("[mpv] \(errorText)")
                            zdLog("[MPV] End file error: \(errorText)")
                        }
                    }
                case MPV_EVENT_SHUTDOWN:
                    return
                case MPV_EVENT_LOG_MESSAGE:
                    if let msg = UnsafeMutablePointer<mpv_event_log_message>(OpaquePointer(eventPtr.pointee.data)) {
                        let prefix = String(cString: msg.pointee.prefix!)
                        let level = String(cString: msg.pointee.level!)
                        let text = String(cString: msg.pointee.text!)
                        self.appendPlaybackLog(prefix: prefix, level: level, text: text)
                        zdLog("[MPV][\(prefix)] \(level): \(text)")
                    }
                default:
                    break
                }
            }
        }
    }

    // MARK: - MPV Helpers

    private func command(_ command: String, args: [String?] = [], checkForErrors: Bool = true) {
        guard mpv != nil else { return }
        var cargs = makeCArgs(command, args).map { $0.flatMap { UnsafePointer<CChar>(strdup($0)) } }
        defer { for ptr in cargs where ptr != nil { free(UnsafeMutablePointer(mutating: ptr!)) } }
        let ret = mpv_command(mpv, &cargs)
        if checkForErrors { checkError(ret) }
    }

    private func makeCArgs(_ command: String, _ args: [String?]) -> [String?] {
        var strArgs = args
        strArgs.insert(command, at: 0)
        strArgs.append(nil)
        return strArgs
    }

    private func getDouble(_ name: String) -> Double {
        guard mpv != nil else { return 0.0 }
        var data = Double()
        mpv_get_property(mpv, name, MPV_FORMAT_DOUBLE, &data)
        return data
    }

    fileprivate func getString(_ name: String) -> String? {
        guard mpv != nil else { return nil }
        let cstr = mpv_get_property_string(mpv, name)
        let str: String? = cstr == nil ? nil : String(cString: cstr!)
        mpv_free(cstr)
        return str
    }

    private func getFlag(_ name: String) -> Bool {
        guard mpv != nil else { return false }
        var data = Int64()
        mpv_get_property(mpv, name, MPV_FORMAT_FLAG, &data)
        return data > 0
    }

    private func setFlag(_ name: String, _ flag: Bool) {
        guard mpv != nil else { return }
        var data: Int = flag ? 1 : 0
        mpv_set_property(mpv, name, MPV_FORMAT_FLAG, &data)
    }

    private func setStringProperty(_ name: String, _ value: String) {
        guard mpv != nil else { return }
        checkError(mpv_set_property_string(mpv, name, value))
    }

    private func setVideoEqualizer(_ name: String, _ value: Int) {
        guard mpv != nil else { return }
        var clamped = Int64(max(-100, min(100, value)))
        checkError(mpv_set_property(mpv, name, MPV_FORMAT_INT64, &clamped))
    }

    private func getInt(_ name: String) -> Int {
        guard mpv != nil else { return 0 }
        var data = Int64()
        mpv_get_property(mpv, name, MPV_FORMAT_INT64, &data)
        return Int(data)
    }

    private func logCurrentAudioOutput() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self, self.mpv != nil else { return }
            let currentAo = self.getString("current-ao") ?? "unknown"
            let channels = self.getString("audio-out-params/hr-channels")
                ?? self.getString("audio-params/hr-channels")
                ?? "unknown"
            let channelCount = self.getInt("audio-out-params/channel-count")
            let codec = self.getString("audio-codec-name") ?? "unknown"
            zdLog("[MPV] Audio output: ao=\(currentAo), channels=\(channels), channelCount=\(channelCount), codec=\(codec)")
        }
    }

    private func checkError(_ status: CInt) {
        if status < 0 {
            zdLog("[MPV] API error: \(String(cString: mpv_error_string(status)))")
        }
    }

    private func sanitizeRequestHeaders(_ headers: [String: String]) -> [String: String] {
        guard !headers.isEmpty else { return [:] }

        var sanitized: [String: String] = [:]
        sanitized.reserveCapacity(headers.count)
        headers.forEach { rawKey, rawValue in
            let key = rawKey.trimmingCharacters(in: .whitespacesAndNewlines)
            let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty, !value.isEmpty else { return }
            guard key.caseInsensitiveCompare("Range") != .orderedSame else { return }
            sanitized[key] = value
        }
        return sanitized
    }

    private func applyRequestHeaders(_ headers: [String: String]) {
        guard mpv != nil else { return }
        if headers.isEmpty {
            checkError(mpv_set_property_string(mpv, "http-header-fields", ""))
            return
        }

        let serialized = headers
            .sorted { $0.key.localizedCaseInsensitiveCompare($1.key) == .orderedAscending }
            .map { key, value in
                let escapedValue = value
                    .replacingOccurrences(of: "\\", with: "\\\\")
                    .replacingOccurrences(of: ",", with: "\\,")
                return "\(key): \(escapedValue)"
            }
            .joined(separator: ",")
        checkError(mpv_set_property_string(mpv, "http-header-fields", serialized))
    }

    private func refreshImmersiveSystemUI() {
        setNeedsUpdateOfHomeIndicatorAutoHidden()
        setNeedsUpdateOfScreenEdgesDeferringSystemGestures()
        setNeedsStatusBarAppearanceUpdate()

        var currentParent = parent
        while let controller = currentParent {
            controller.setNeedsUpdateOfHomeIndicatorAutoHidden()
            controller.setNeedsUpdateOfScreenEdgesDeferringSystemGestures()
            controller.setNeedsStatusBarAppearanceUpdate()
            if let rootController = controller as? RootComposeViewController {
                rootController.refreshImmersiveSystemUI()
            }
            currentParent = controller.parent
        }
    }
}

// MARK: - Bridge Creator (implements Kotlin protocol)

final class MPVPlayerBridgeCreator: NSObject, NuvioPlayerBridgeCreator {
    func createBridge() -> any NuvioPlayerBridge {
        return MPVPlayerBridgeImpl()
    }
}

// MARK: - Registration (called from Swift app startup)

enum NuvioPlayerRegistration {
    static func register() {
        NuvioPlayerBridgeFactory.shared.registerFactory(creator: MPVPlayerBridgeCreator())
    }
}

// MARK: - HLS ad-discontinuity sanitizer (fix: reset-to-0 on ad segments)
import Foundation

/// Rewrites HLS (m3u8) playlists so mpv keeps playing across sloppy
/// ad-injected discontinuities instead of resetting position to 0.
///
/// What it does (VOD only, anything else passes through untouched):
///  1. Collapses consecutive duplicate `#EXT-X-DISCONTINUITY` tags into one.
///     Back-to-back duplicates are meaningless per the HLS spec but trip up
///     demuxers (observed on phimapi/KKPhim ad-spliced playlists).
///  2. Absolutizes every relative URI (segments, KEY, MAP, variants) so the
///     rewritten playlist can be played from a local temp file.
///  3. Keeps everything else byte-identical (incl. ENDLIST / TARGETDURATION).
///
/// On any failure it falls back to the original URL (current behavior).
final class HLSPlaylistSanitizer {

    static let shared = HLSPlaylistSanitizer()

    /// A gap in the stream's presentation clock left behind after removing an
    /// ad cluster whose ads occupied real time in the movie timeline (clusters
    /// where every ad segment carried its own discontinuity tag). `start` is
    /// the playlist position where the gap begins (seconds), `size` the number
    /// of seconds removed.
    struct TimelineHole {
        var start: Double
        var size: Double
    }

    /// Holes found while sanitizing the most recent playlist. The player reads
    /// this to present a continuous user-facing timeline (no clock jump at the
    /// removed ad breaks). Guarded by `holesLock` (sanitizer runs on its work
    /// queue, the player reads on the main thread).
    private static let holesLock = NSLock()
    private static var _lastHoles: [TimelineHole] = []
    static var lastHoles: [TimelineHole] {
        get { holesLock.lock(); defer { holesLock.unlock() }; return _lastHoles }
        set { holesLock.lock(); _lastHoles = newValue; holesLock.unlock() }
    }

    private let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 12
        config.timeoutIntervalForResource = 12
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: config)
    }()

    private let workQueue = DispatchQueue(label: "hls-sanitizer", qos: .userInitiated)

    /// Resolve `urlString` to a playable URL, calling completion on main thread.
    func sanitizedURL(
        for urlString: String,
        headers: [String: String],
        completion: @escaping (String) -> Void
    ) {
        guard
            let url = URL(string: urlString),
            let scheme = url.scheme?.lowercased(),
            (scheme == "http" || scheme == "https"),
            url.pathExtension.lowercased() == "m3u8"
        else {
            completion(urlString)
            return
        }

        workQueue.async { [weak self] in
            guard let self else {
                DispatchQueue.main.async { completion(urlString) }
                return
            }
            HLSPlaylistSanitizer.lastHoles = []
            self.rewritePlaylist(at: url, headers: headers) { localURL in
                DispatchQueue.main.async { completion(localURL ?? urlString) }
            }
        }
    }

    // MARK: - Core

    private func rewritePlaylist(
        at url: URL,
        headers: [String: String],
        completion: @escaping (String?) -> Void
    ) {
        fetchText(url: url, headers: headers) { [weak self] text in
            guard let self, let text else { completion(nil); return }
            guard text.contains("#EXTM3U") else { completion(nil); return }

            if text.contains("#EXT-X-STREAM-INF") {
                self.rewriteMaster(text, baseURL: url, headers: headers, completion: completion)
            } else if text.contains("#EXT-X-ENDLIST") {
                // VOD media playlist -> sanitize into a temp file.
                let sanitized = self.sanitizeMediaPlaylist(text, baseURL: url)
                HLSPlaylistSanitizer.lastHoles = sanitized.holes
                if let fileURL = self.writeMediaPlaylist(sanitized.body, suffix: "media") {
                    completion(fileURL.path)
                } else {
                    completion(nil)
                }
            } else {
                // Live / event playlist (no ENDLIST): do not touch.
                completion(nil)
            }
        }
    }

    private func rewriteMaster(
        _ text: String,
        baseURL: URL,
        headers: [String: String],
        completion: @escaping (String?) -> Void
    ) {
        let lines = text.components(separatedBy: .newlines)
        // Collect variant + rendition URIs that need local copies.
        var targets: [(lineIndex: Int, uri: String, kind: String)] = []
        var i = 0
        while i < lines.count {
            let line = lines[i].trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("#EXT-X-STREAM-INF") || line.hasPrefix("#EXT-X-I-FRAMES-ONLY") {
                if i + 1 < lines.count {
                    let uri = lines[i + 1].trimmingCharacters(in: .whitespaces)
                    if !uri.isEmpty, !uri.hasPrefix("#") {
                        targets.append((i + 1, uri, "variant"))
                    }
                }
            } else if line.hasPrefix("#EXT-X-MEDIA:") {
                if let uri = Self.attributeURI(line, key: "URI") {
                    targets.append((i, uri, "media"))
                }
            }
            i += 1
        }
        guard !targets.isEmpty else { completion(nil); return }

        guard let dir = Self.makeTempDir() else { completion(nil); return }
        let group = DispatchGroup()
        var rewritten = lines
        var failed = false
        let lock = NSLock()

        for (index, uri, kind) in targets {
            guard let absolute = Self.absoluteURL(uri, base: baseURL) else { continue }
            group.enter()
            if kind == "variant" {
                fetchText(url: absolute, headers: headers) { [weak self] mediaText in
                    defer { group.leave() }
                    guard let self, let mediaText, mediaText.contains("#EXTM3U") else {
                        lock.lock(); failed = true; lock.unlock(); return
                    }
                    let body: String
                    if mediaText.contains("#EXT-X-STREAM-INF") {
                        body = mediaText // nested master: absolutize only
                    } else if mediaText.contains("#EXT-X-ENDLIST") {
                        let sanitized = self.sanitizeMediaPlaylist(mediaText, baseURL: absolute)
                        body = sanitized.body
                        if !sanitized.holes.isEmpty {
                            lock.lock()
                            if HLSPlaylistSanitizer.lastHoles.isEmpty {
                                HLSPlaylistSanitizer.lastHoles = sanitized.holes
                            }
                            lock.unlock()
                        }
                    } else {
                        body = mediaText
                    }
                    let fileName = "v\(index).m3u8"
                    let fileURL = dir.appendingPathComponent(fileName)
                    do {
                        try body.write(to: fileURL, atomically: true, encoding: .utf8)
                        lock.lock(); rewritten[index] = fileURL.path; lock.unlock()
                    } catch {
                        lock.lock(); failed = true; lock.unlock()
                    }
                }
            } else {
                // Rendition (audio/subs) playlist: absolutize only, keep remote.
                lock.lock(); rewritten[index] = Self.rewriteURIAttribute(lines[index], key: "URI", base: baseURL); lock.unlock()
                group.leave()
            }
        }

        group.notify(queue: workQueue) {
            lock.lock(); let ok = !failed; lock.unlock()
            guard ok else { completion(nil); return }
            let masterURL = dir.appendingPathComponent("master.m3u8")
            do {
                try rewritten.joined(separator: "\n").write(to: masterURL, atomically: true, encoding: .utf8)
                completion(masterURL.path)
            } catch {
                completion(nil)
            }
        }
    }

    /// Sanitize a VOD HLS media playlist for ad-spliced streams:
    /// - Drop ad segments that sit between nearby `#EXT-X-DISCONTINUITY` markers.
    ///   Ad clips carry their own near-zero timestamps while the movie keeps
    ///   absolute presentation times; ffmpeg's HLS demuxer does not process the
    ///   discontinuity tag at all (verified against n8.1.2 and current master),
    ///   so the raw timestamp reset makes players jump back to ~0 unless the ad
    ///   spans are removed. Movie segment timestamps are untouched, so subtitle
    ///   timing and seek positions stay exactly as they were.
    /// - Remove all discontinuity tags and absolutize URIs.
    func sanitizeMediaPlaylist(_ text: String, baseURL: URL) -> (body: String, holes: [TimelineHole]) {
        let lines = text.components(separatedBy: .newlines)

        // 1) Collapse back-to-back duplicate discontinuity tags.
        var collapsed: [String] = []
        collapsed.reserveCapacity(lines.count)
        var previousWasDiscontinuity = false
        for rawLine in lines {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line == "#EXT-X-DISCONTINUITY" {
                if previousWasDiscontinuity { continue }
                previousWasDiscontinuity = true
                collapsed.append(rawLine)
            } else {
                previousWasDiscontinuity = false
                collapsed.append(rawLine)
            }
        }

        // 2) Mark ad spans: from one discontinuity up to (excluding) the next,
        //    when the span looks like a short ad break.
        var discontinuityIndexes: [Int] = []
        for (index, rawLine) in collapsed.enumerated()
            where rawLine.trimmingCharacters(in: .whitespaces) == "#EXT-X-DISCONTINUITY" {
            discontinuityIndexes.append(index)
        }

        var dropped = [Bool](repeating: false, count: collapsed.count)
        var spanInfos: [(start: Int, end: Int, droppedDuration: Double, segmentCount: Int)] = []
        for (position, start) in discontinuityIndexes.enumerated() {
            guard position + 1 < discontinuityIndexes.count else { continue }
            let end = discontinuityIndexes[position + 1]
            var segmentCount = 0
            var duration = 0.0
            var index = start + 1
            while index < end {
                let line = collapsed[index].trimmingCharacters(in: .whitespaces)
                if line.hasPrefix("#EXTINF:") {
                    segmentCount += 1
                    let value = line.dropFirst("#EXTINF:".count)
                        .split(separator: ",").first.map(String.init) ?? ""
                    duration += Double(value) ?? 0
                }
                index += 1
            }
            if segmentCount > 0, segmentCount <= 30, duration <= 120.0 {
                for index in start..<end {
                    dropped[index] = true
                }
                spanInfos.append((start, end, duration, segmentCount))
            }
        }

        // Group consecutive spans into clusters. When a cluster marks a real
        // timeline hole (each of its segments individually tagged with a
        // discontinuity — the movie around it was re-timed), pad the first
        // surviving segment after the cluster by the dropped duration, so the
        // demuxer's EXTINF-based seek map keeps matching the stream's
        // presentation timestamps. Clusters with only boundary tags leave the
        // movie timeline continuous, so nothing is padded.
        var extinfAdjustments: [Int: Double] = [:]
        var holes: [TimelineHole] = []
        var holeShift = 0.0
        var clusterPos = 0
        while clusterPos < spanInfos.count {
            var clusterEnd = clusterPos
            var total = 0.0
            var segments = 0
            var discCount = 0
            while true {
                let span = spanInfos[clusterEnd]
                total += span.droppedDuration
                segments += span.segmentCount
                for index in span.start..<span.end
                    where collapsed[index].trimmingCharacters(in: .whitespaces) == "#EXT-X-DISCONTINUITY" {
                    discCount += 1
                }
                if clusterEnd + 1 < spanInfos.count, spanInfos[clusterEnd + 1].start == span.end {
                    clusterEnd += 1
                } else {
                    break
                }
            }
            if discCount >= segments, segments > 0 {
                var k = spanInfos[clusterEnd].end
                while k < collapsed.count,
                      dropped[k] || !collapsed[k].trimmingCharacters(in: .whitespaces).hasPrefix("#EXTINF:") {
                    k += 1
                }
                if k < collapsed.count {
                    extinfAdjustments[k, default: 0] += total
                    // Record the timeline hole so the player can show a
                    // continuous clock (raw time-pos keeps the removed gap).
                    var start = 0.0
                    for index in 0..<spanInfos[clusterPos].start where !dropped[index] {
                        let line = collapsed[index].trimmingCharacters(in: .whitespaces)
                        if line.hasPrefix("#EXTINF:") {
                            let value = line.dropFirst("#EXTINF:".count)
                                .split(separator: ",").first.map(String.init) ?? ""
                            start += Double(value) ?? 0
                        }
                    }
                    holes.append(TimelineHole(start: start + holeShift, size: total))
                    holeShift += total
                }
            }
            clusterPos = clusterEnd + 1
        }

        // 3) Emit: skip dropped lines and every discontinuity tag, absolutize URIs.
        var out: [String] = []
        out.reserveCapacity(collapsed.count)
        for (index, rawLine) in collapsed.enumerated() {
            if dropped[index] { continue }
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line == "#EXT-X-DISCONTINUITY" { continue }

            if line.hasPrefix("#EXTINF:") {
                if let adjust = extinfAdjustments[index] {
                    let value = line.dropFirst("#EXTINF:".count)
                        .split(separator: ",").first.map(String.init) ?? ""
                    if let duration = Double(value) {
                        out.append(String(format: "#EXTINF:%.3f,", duration + adjust))
                        continue
                    }
                }
                out.append(rawLine)
                continue
            }

            if line.hasPrefix("#EXT-X-KEY:") {
                out.append(Self.rewriteURIAttribute(rawLine, key: "URI", base: baseURL))
            } else if line.hasPrefix("#EXT-X-MAP:") {
                out.append(Self.rewriteURIAttribute(rawLine, key: "URI", base: baseURL))
            } else if line.hasPrefix("#EXT-X-MEDIA:") {
                out.append(Self.rewriteURIAttribute(rawLine, key: "URI", base: baseURL))
            } else if !line.isEmpty, !line.hasPrefix("#") {
                // Segment URI.
                out.append(Self.absoluteURL(line, base: baseURL)?.absoluteString ?? rawLine)
            } else {
                out.append(rawLine)
            }
        }
        return (out.joined(separator: "\n"), holes)
    }

    // MARK: - Helpers

    private func fetchText(
        url: URL,
        headers: [String: String],
        completion: @escaping (String?) -> Void
    ) {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        for (key, value) in headers where !value.isEmpty {
            request.setValue(value, forHTTPHeaderField: key)
        }
        session.dataTask(with: request) { data, response, _ in
            guard
                let data,
                let http = response as? HTTPURLResponse,
                (200..<300).contains(http.statusCode),
                let text = String(data: data, encoding: .utf8),
                !text.isEmpty
            else {
                completion(nil)
                return
            }
            completion(text)
        }.resume()
    }

    private func writeMediaPlaylist(_ body: String, suffix: String) -> URL? {
        guard let dir = Self.makeTempDir() else { return nil }
        let fileURL = dir.appendingPathComponent("\(suffix).m3u8")
        do {
            try body.write(to: fileURL, atomically: true, encoding: .utf8)
            return fileURL
        } catch {
            return nil
        }
    }

    private static func makeTempDir() -> URL? {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("nuvio-hls-\(UUID().uuidString)", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            return dir
        } catch {
            return nil
        }
    }

    private static func absoluteURL(_ uri: String, base: URL) -> URL? {
        if let url = URL(string: uri), url.scheme != nil { return url }
        return URL(string: uri, relativeTo: base)?.absoluteURL
    }

    private static func attributeURI(_ line: String, key: String) -> String? {
        // Matches KEY="value" with optional whitespace.
        let pattern = key + "\\s*=\\s*\"([^\"]*)\""
        guard
            let regex = try? NSRegularExpression(pattern: pattern),
            let match = regex.firstMatch(
                in: line,
                range: NSRange(line.startIndex..., in: line)
            ),
            let range = Range(match.range(at: 1), in: line)
        else {
            return nil
        }
        return String(line[range])
    }

    private static func rewriteURIAttribute(_ line: String, key: String, base: URL) -> String {
        guard
            let uri = attributeURI(line, key: key),
            !uri.isEmpty,
            let absolute = absoluteURL(uri, base: base)
        else {
            return line
        }
        let pattern = "(" + key + "\\s*=\\s*\")[^\"]*(\")"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return line }
        return regex.stringByReplacingMatches(
            in: line,
            range: NSRange(line.startIndex..., in: line),
            withTemplate: "$1" + absolute.absoluteString + "$2"
        )
    }
}

