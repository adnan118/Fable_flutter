import AVFoundation
import Flutter
import Foundation
import UIKit
import UniformTypeIdentifiers

// RC120 - Native AVPlayer progressive playback adapter. The only resource URL
// is the private, synthetic fable-media scheme; AVURLAsset must ask our loader.
// No HTTP client, bearer, media token, local cache, DRM or manifest fallback.

private enum ProtectedMediaError: Error {
  case unavailable
}

private final class WeakProtectedMediaView {
  weak var view: FableProtectedMediaPlatformView?
  init(_ value: FableProtectedMediaPlatformView) { view = value }
}

final class FableProtectedMediaBridge: NSObject {
  private let channel: FlutterMethodChannel
  private var views = [Int64: WeakProtectedMediaView]()
  private var observers = [NSObjectProtocol]()
  private var sequence: Int64 = 0

  init(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(
      name: "fable/protected_player_v1", binaryMessenger: messenger)
    super.init()
    channel.setMethodCallHandler { [weak self] call, result in
      self?.handle(call, result: result)
        ?? result(FlutterError(code: "unavailable", message: "No player", details: nil))
    }

    // UI lifecycle belongs to UIScene/FlutterSceneDelegate, not AppDelegate.
    // A scene resigning foreground immediately releases all native decoders.
    for name in [UIScene.willDeactivateNotification,
                 UIScene.didEnterBackgroundNotification] {
      observers.append(NotificationCenter.default.addObserver(
        forName: name, object: nil, queue: .main
      ) { [weak self] _ in self?.stopAll() })
    }
  }

  deinit {
    observers.forEach(NotificationCenter.default.removeObserver)
    channel.setMethodCallHandler(nil)
  }

  func attach(_ view: FableProtectedMediaPlatformView, id: Int64) {
    views[id] = WeakProtectedMediaView(view)
  }

  func detach(_ id: Int64) { views.removeValue(forKey: id) }

  func notifyRenderer(viewId: Int64, leaseId: Int64, rangeEpoch: Int,
                      event: String) {
    guard leaseId > 0, ["ready", "ended", "failed", "playing", "paused", "seeked"].contains(event) else {
      return
    }
    // Delivery must occur on Flutter's platform thread. Only categorical
    // renderer state crosses the bridge; never raw AVFoundation errors.
    let send: () -> Void = { [weak self] in
      guard let self else { return }
      self.channel.invokeMethod("playerEvent", arguments: [
        "viewId": viewId, "leaseId": leaseId,
        "rangeEpoch": rangeEpoch, "event": event
      ])
    }
    if Thread.isMainThread { send() }
    else { DispatchQueue.main.async(execute: send) }
  }

  private func stopAll() {
    for entry in views.values { entry.view?.stop() }
  }

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard let args = call.arguments as? [String: Any],
      let numericId = args["viewId"] as? NSNumber else {
      result(FlutterError(code: "unknown_view",
                          message: "Protected player surface is unavailable", details: nil))
      return
    }
    let requestedLease = (args["leaseId"] as? NSNumber)?.int64Value ?? -1
    let cleanup = call.method == "stop" || call.method == "dispose"
    guard let surface = views[numericId.int64Value]?.view else {
      // Flutter may unregister the UIKit PlatformView before asynchronous
      // Dart State.dispose() cleanup reaches the MethodChannel. A missing
      // view is therefore a successful no-op for stop/dispose only.
      if cleanup { result(nil); return }
      result(FlutterError(code: "unknown_view",
                          message: "Protected player surface is unavailable", details: nil))
      return
    }
    // A stale cleanup from an old lease must never stop a newly reused view.
    if cleanup && (requestedLease <= 0 || requestedLease != surface.leaseId) {
      result(nil)
      return
    }
    do {
      // All playback-changing commands remain strict on the active lease.
      guard requestedLease > 0,
        (call.method == "prepare" || requestedLease == surface.leaseId) else {
        throw ProtectedMediaError.unavailable
      }
      switch call.method {
      case "prepare":
        guard let size = args["totalLength"] as? NSNumber,
          let mime = args["mimeType"] as? String,
          let epoch = args["rangeEpoch"] as? NSNumber else {
          throw ProtectedMediaError.unavailable
        }
        try surface.prepare(total: size.int64Value, mime: mime,
                            epoch: epoch.intValue, newLease: requestedLease)
      case "play": try surface.play()
      case "pause": try surface.pause()
      case "seek":
        guard let millis = args["millis"] as? NSNumber,
          let epoch = args["rangeEpoch"] as? NSNumber else {
          throw ProtectedMediaError.unavailable
        }
        try surface.seek(milliseconds: millis.int64Value,
                         epoch: epoch.intValue)
      case "stop", "dispose": surface.stop()
      default: result(FlutterMethodNotImplemented); return
      }
      result(nil)
    } catch {
      // Do not publish player or protected-source exception descriptions.
      result(FlutterError(code: "protected_player_rejected",
                          message: "Protected media operation rejected", details: nil))
    }
  }

  func read(
    id: Int64, leaseId: Int64, offset: Int64, count: Int, epoch: Int,
    expectedTotal: Int64, expectedType: String,
    completion: @escaping (Data?) -> Void
  ) {
    guard leaseId > 0, count > 0 && count <= 524288 && offset >= 0 else {
      completion(nil)
      return
    }
    sequence += 1
    let requestId = sequence
    channel.invokeMethod("readRange", arguments: [
      "viewId": id, "leaseId": leaseId,
      "requestId": requestId, "start": offset,
      "length": count, "rangeEpoch": epoch
    ]) { answer in
      guard let payload = answer as? [String: Any],
        payload["status"] as? String == "bytes",
        let start = payload["start"] as? NSNumber,
        start.int64Value == offset,
        let total = payload["totalLength"] as? NSNumber,
        total.int64Value == expectedTotal,
        let mime = payload["mimeType"] as? String,
        mime == expectedType,
        let wrapped = payload["bytes"] as? FlutterStandardTypedData,
        !wrapped.data.isEmpty, wrapped.data.count <= count else {
        completion(nil)
        return
      }
      completion(wrapped.data)
    }
  }
}

final class FableProtectedMediaViewFactory: NSObject, FlutterPlatformViewFactory {
  private let bridge: FableProtectedMediaBridge
  init(bridge: FableProtectedMediaBridge) {
    self.bridge = bridge
    super.init()
  }

  func create(
    withFrame frame: CGRect, viewIdentifier viewId: Int64,
    arguments args: Any?
  ) -> FlutterPlatformView {
    let value = FableProtectedMediaPlatformView(
      frame: frame, identifier: viewId, bridge: bridge)
    bridge.attach(value, id: viewId)
    return value
  }

  func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
    FlutterStandardMessageCodec.sharedInstance()
  }
}

private final class ProtectedVideoSurface: UIView {
  override class var layerClass: AnyClass { AVPlayerLayer.self }
  var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
}

final class FableProtectedMediaPlatformView: NSObject, FlutterPlatformView {
  private let identifier: Int64
  private let bridge: FableProtectedMediaBridge
  private let surface: ProtectedVideoSurface
  private var player: AVPlayer?
  private var asset: AVURLAsset?
  private var loader: FableProtectedAssetLoader?
  private var statusObservation: NSKeyValueObservation?
  private var timeControlObservation: NSKeyValueObservation?
  private var playbackRequested = false
  private var hasObservedNativePlaying = false
  private var finishedObserver: NSObjectProtocol?
  private(set) var leaseId: Int64 = 0
  private var active = false
  private var rangeEpoch = 0

  init(frame: CGRect, identifier: Int64, bridge: FableProtectedMediaBridge) {
    self.identifier = identifier
    self.bridge = bridge
    surface = ProtectedVideoSurface(frame: frame)
    surface.backgroundColor = .black
    surface.playerLayer.videoGravity = .resizeAspect
    super.init()
  }

  func view() -> UIView { surface }

  func prepare(total: Int64, mime: String, epoch: Int,
               newLease: Int64) throws {
    // AVFoundation receives a verified UTI, never a raw HTML/content URL.
    guard total > 0 && epoch >= 0 && newLease > 0,
      ["video/mp4", "audio/mp4", "audio/mpeg"].contains(mime),
      let uti = UTType(mimeType: mime)?.identifier else {
      throw ProtectedMediaError.unavailable
    }
    stop()
    leaseId = newLease
    rangeEpoch = epoch
    let queue = DispatchQueue(label: "fable.secure.media.loader.\(identifier)")
    let delegate = FableProtectedAssetLoader(
      bridge: bridge, viewId: identifier, leaseId: newLease, total: total,
      uniformType: uti, mimeType: mime, epoch: epoch, queue: queue)
    let url = URL(string: "fable-media://session/content")!
    let nativeAsset = AVURLAsset(url: url)
    nativeAsset.resourceLoader.setDelegate(delegate, queue: queue)
    let item = AVPlayerItem(asset: nativeAsset)
    let nativePlayer = AVPlayer(playerItem: item)
    active = true
    loader = delegate
    asset = nativeAsset
    player = nativePlayer
    surface.playerLayer.player = nativePlayer
    surface.playerLayer.isHidden = false

    statusObservation = item.observe(\.status, options: [.new]) {
      [weak self] observed, _ in
      DispatchQueue.main.async { [weak self] in
        guard let self, self.active, self.leaseId == newLease,
          self.player?.currentItem === observed else { return }
        switch observed.status {
        case .readyToPlay:
          self.bridge.notifyRenderer(viewId: self.identifier, leaseId: newLease,
                                     rangeEpoch: self.rangeEpoch, event: "ready")
        case .failed:
          self.bridge.notifyRenderer(viewId: self.identifier, leaseId: newLease,
                                     rangeEpoch: self.rangeEpoch, event: "failed")
        default:
          break
        }
      }
    }
    timeControlObservation = nativePlayer.observe(\.timeControlStatus, options: [.new]) {
      [weak self] observed, _ in
      DispatchQueue.main.async { [weak self] in
        guard let self, self.active, self.playbackRequested,
          self.leaseId == newLease, self.player === observed else { return }
        switch observed.timeControlStatus {
        case .playing:
          self.bridge.notifyRenderer(viewId: self.identifier, leaseId: newLease,
                                     rangeEpoch: self.rangeEpoch, event: "playing")
        case .paused:
          self.bridge.notifyRenderer(viewId: self.identifier, leaseId: newLease,
                                     rangeEpoch: self.rangeEpoch, event: "paused")
        default:
          break
        }
      }
    }
    finishedObserver = NotificationCenter.default.addObserver(
      forName: AVPlayerItem.didPlayToEndTimeNotification, object: item,
      queue: .main
    ) { [weak self] _ in
      guard let self, self.active, self.leaseId == newLease else { return }
      self.bridge.notifyRenderer(viewId: self.identifier, leaseId: newLease,
                                 rangeEpoch: self.rangeEpoch, event: "ended")
    }
  }

  func play() throws {
    guard active, let player else { throw ProtectedMediaError.unavailable }
    playbackRequested = true
    player.play()
  }

  func pause() throws {
    guard active, let player else { throw ProtectedMediaError.unavailable }
    player.pause()
  }

  func seek(milliseconds: Int64, epoch: Int) throws {
    guard active, milliseconds >= 0, epoch > rangeEpoch,
      let player, let loader else { throw ProtectedMediaError.unavailable }
    rangeEpoch = epoch
    loader.advanceEpoch(epoch)
    let expectedLease = leaseId
    player.seek(to: CMTime(value: milliseconds, timescale: 1000),
                toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] finished in
      DispatchQueue.main.async { [weak self] in
        guard finished, let self, self.active,
          self.leaseId == expectedLease, self.rangeEpoch == epoch else { return }
        self.bridge.notifyRenderer(viewId: self.identifier, leaseId: expectedLease,
                                   rangeEpoch: epoch, event: "seeked")
      }
    }
  }

  func stop() {
    active = false
    playbackRequested = false
    timeControlObservation?.invalidate()
    timeControlObservation = nil
    statusObservation?.invalidate()
    statusObservation = nil
    if let finishedObserver {
      NotificationCenter.default.removeObserver(finishedObserver)
    }
    finishedObserver = nil
    player?.pause()
    surface.playerLayer.player = nil
    // Prevent rendering the last frame after an identity/session revoke.
    surface.playerLayer.isHidden = true
    surface.playerLayer.contents = nil
    player?.replaceCurrentItem(with: nil)
    player = nil
    loader?.invalidate()
    asset?.resourceLoader.setDelegate(nil, queue: nil)
    loader = nil
    asset = nil
  }

  deinit {
    stop()
    bridge.detach(identifier)
  }
}

// The resource loader's serial queue is the only owner of mutable loading
// requests. Dart replies are marshaled back to this queue, and discarded after
// stop/seek/cancel. At most one bounded chunk per pending request at a time.
private final class FableProtectedAssetLoader: NSObject, AVAssetResourceLoaderDelegate {
  private struct Progress {
    var next: Int64
    let end: Int64
    let epoch: Int
  }

  private let bridge: FableProtectedMediaBridge
  private let viewId: Int64
  private let leaseId: Int64
  private let total: Int64
  private let uniformType: String
  private let mediaType: String
  private let queue: DispatchQueue
  private var epoch: Int
  private var active = true
  private var pending = [ObjectIdentifier: (AVAssetResourceLoadingRequest, Progress)]()

  init(
    bridge: FableProtectedMediaBridge, viewId: Int64, leaseId: Int64,
    total: Int64, uniformType: String, mimeType: String,
    epoch: Int, queue: DispatchQueue
  ) {
    self.bridge = bridge
    self.viewId = viewId
    self.leaseId = leaseId
    self.total = total
    self.uniformType = uniformType
    self.mediaType = mimeType
    self.epoch = epoch
    self.queue = queue
    super.init()
  }

  private func rejection() -> NSError {
    NSError(domain: "FableProtectedMedia", code: -1, userInfo: nil)
  }

  func advanceEpoch(_ next: Int) {
    queue.sync {
      guard active && next > epoch else { return }
      epoch = next
      for (_, pair) in pending {
        pair.0.finishLoading(with: rejection())
      }
      pending.removeAll()
    }
  }

  func invalidate() {
    queue.sync {
      guard active else { return }
      active = false
      for (_, pair) in pending {
        pair.0.finishLoading(with: rejection())
      }
      pending.removeAll()
    }
  }

  func resourceLoader(
    _ resourceLoader: AVAssetResourceLoader,
    shouldWaitForLoadingOfRequestedResource request: AVAssetResourceLoadingRequest
  ) -> Bool {
    guard active, request.request.url?.scheme == "fable-media",
      request.request.url?.host == "session" else { return false }
    if let info = request.contentInformationRequest {
      if let allowed = info.allowedContentTypes,
         !allowed.isEmpty && !allowed.contains(uniformType) {
        request.finishLoading(with: rejection())
        return true
      }
      info.contentType = uniformType
      info.contentLength = total
      info.isByteRangeAccessSupported = true
    }
    guard let body = request.dataRequest else {
      request.finishLoading()
      return true
    }
    let start = max(body.currentOffset, body.requestedOffset)
    guard start >= 0 && start <= total else {
      request.finishLoading(with: rejection())
      return true
    }
    let end: Int64
    if body.requestsAllDataToEndOfResource {
      end = total
    } else {
      let length = max(0, Int64(body.requestedLength))
      end = min(total, start + min(length, total - start))
    }
    let id = ObjectIdentifier(request)
    pending[id] = (request, Progress(next: start, end: end, epoch: epoch))
    pump(id)
    return true
  }

  private func pump(_ id: ObjectIdentifier) {
    guard active, let (request, progress) = pending[id] else { return }
    if progress.epoch != epoch {
      pending.removeValue(forKey: id)
      request.finishLoading(with: rejection())
      return
    }
    if progress.next >= progress.end {
      pending.removeValue(forKey: id)
      request.finishLoading()
      return
    }
    let start = progress.next
    let count = Int(min(65536, progress.end - start))
    let tokenEpoch = epoch
    DispatchQueue.main.async { [weak self] in
      guard let self else { return }
      self.bridge.read(id: self.viewId, leaseId: self.leaseId, offset: start,
                       count: count, epoch: tokenEpoch,
                       expectedTotal: self.total,
                       expectedType: self.mediaType) { [weak self] data in
        guard let self else { return }
        self.queue.async {
          guard self.active, let (nextRequest, state) = self.pending[id],
            state.epoch == self.epoch, state.epoch == tokenEpoch,
            state.next == start else { return }
          guard let data, !data.isEmpty,
            data.count <= count,
            Int64(data.count) <= state.end - state.next else {
            self.pending.removeValue(forKey: id)
            nextRequest.finishLoading(with: self.rejection())
            return
          }
          nextRequest.dataRequest?.respond(with: data)
          self.pending[id] = (
            nextRequest, Progress(next: state.next + Int64(data.count),
                                  end: state.end, epoch: state.epoch))
          self.pump(id)
        }
      }
    }
  }

  func resourceLoader(
    _ resourceLoader: AVAssetResourceLoader,
    didCancel loadingRequest: AVAssetResourceLoadingRequest
  ) {
    pending.removeValue(forKey: ObjectIdentifier(loadingRequest))
  }
}
