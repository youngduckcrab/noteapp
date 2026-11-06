// pencil_bridge (INFRA, docs/plans/m5-7/01-infra.md 4.4.4 and 6.12.2,
// contract 00-overview 7.2.13). The FlutterStreamHandler of
// 'dev.noteapp/pencil/events': the first Dart listener attaches
// UIPencilInteraction and the hover / roll recognizers (onListen), the last
// cancel detaches them (onCancel). Dart's broadcast EventChannel stream sends
// listen / cancel by the number of listeners (6.12.1).
//
// Positions are in the attached view's coordinates: the Flutter view of this
// engine (registrar.viewController.view), which covers the window, so they
// are Flutter global logical px (4.4.3 — real device check C-1).
// Times `t` are ProcessInfo.systemUptime seconds (the UIEvent / UITouch base);
// the app adapter passes them on as StylusExtraEvent.timestamp.
import Flutter
import UIKit

final class PencilEventStream: NSObject, FlutterStreamHandler, UIPencilInteractionDelegate,
  UIGestureRecognizerDelegate
{
  private weak var registrar: FlutterPluginRegistrar?
  private var eventSink: FlutterEventSink?
  private var pencilInteraction: UIPencilInteraction?
  private var hoverRecognizer: UIHoverGestureRecognizer?
  private var rollRecognizer: UIGestureRecognizer?
  private var keyWindowObserver: NSObjectProtocol?
  private var lastHover: TimeInterval = -Double.infinity

  init(registrar: FlutterPluginRegistrar) {
    self.registrar = registrar
    super.init()
  }

  // MARK: - FlutterStreamHandler

  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink)
    -> FlutterError?
  {
    eventSink = events
    attach()
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    detach()
    eventSink = nil
    return nil
  }

  // MARK: - Attach / detach

  /// The Flutter view first (FlutterPlugin.h — the view this engine draws
  /// into, right with several scenes too), else the key window's root view;
  /// with neither yet, attach once a window becomes key.
  private func attach() {
    detach()
    if let view = targetView() {
      attach(to: view)
      return
    }
    keyWindowObserver = NotificationCenter.default.addObserver(
      forName: UIWindow.didBecomeKeyNotification, object: nil, queue: .main
    ) { [weak self] _ in
      self?.keyWindowDidChange()
    }
  }

  private func keyWindowDidChange() {
    guard eventSink != nil, let view = targetView() else { return }
    stopObservingKeyWindow()
    attach(to: view)
  }

  private func targetView() -> UIView? {
    if let view = registrar?.viewController?.view {
      return view
    }
    let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
    let scene = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
    return scene?.keyWindow?.rootViewController?.view
  }

  private func attach(to view: UIView) {
    let interaction = UIPencilInteraction()
    interaction.delegate = self
    view.addInteraction(interaction)
    pencilInteraction = interaction

    let hover = UIHoverGestureRecognizer(target: self, action: #selector(handleHover(_:)))
    hover.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.pencil.rawValue)]
    hover.cancelsTouchesInView = false
    hover.delegate = self
    view.addGestureRecognizer(hover)
    hoverRecognizer = hover

    if #available(iOS 17.5, *) {
      let roll = PencilRollRecognizer(target: nil, action: nil)
      roll.onRoll = { [weak self] t, angle in
        self?.send(PencilWire.rollEvent(t: t, angle: angle))
      }
      roll.delegate = self
      view.addGestureRecognizer(roll)
      rollRecognizer = roll
    }
  }

  /// Removes the interaction and both recognizers and stops waiting for a
  /// key window. Safe to call when nothing is attached.
  func detach() {
    stopObservingKeyWindow()
    if let interaction = pencilInteraction {
      interaction.view?.removeInteraction(interaction)
    }
    if let hover = hoverRecognizer {
      hover.view?.removeGestureRecognizer(hover)
    }
    if let roll = rollRecognizer {
      roll.view?.removeGestureRecognizer(roll)
    }
    pencilInteraction = nil
    hoverRecognizer = nil
    rollRecognizer = nil
    lastHover = -Double.infinity
  }

  private func stopObservingKeyWindow() {
    if let observer = keyWindowObserver {
      NotificationCenter.default.removeObserver(observer)
      keyWindowObserver = nil
    }
  }

  private func send(_ event: [String: Any]) {
    eventSink?(event)
  }

  // MARK: - UIPencilInteractionDelegate

  /// Before iPadOS 17.5 (17.5+ calls pencilInteraction(_:didReceiveTap:)
  /// instead): no hover pose, so no position.
  func pencilInteractionDidTap(_ interaction: UIPencilInteraction) {
    send(
      PencilWire.tapEvent(
        t: ProcessInfo.processInfo.systemUptime,
        action: PencilWire.actionName(UIPencilInteraction.preferredTapAction),
        position: nil, z: nil))
  }

  @available(iOS 17.5, *)
  func pencilInteraction(
    _ interaction: UIPencilInteraction, didReceiveTap tap: UIPencilInteraction.Tap
  ) {
    let pose = tap.hoverPose
    send(
      PencilWire.tapEvent(
        t: ProcessInfo.processInfo.systemUptime,
        action: PencilWire.actionName(UIPencilInteraction.preferredTapAction),
        position: pose?.location, z: pose?.zOffset))
  }

  @available(iOS 17.5, *)
  func pencilInteraction(
    _ interaction: UIPencilInteraction, didReceiveSqueeze squeeze: UIPencilInteraction.Squeeze
  ) {
    let phase: String
    switch squeeze.phase {
    case .began: phase = "began"
    case .changed: phase = "changed"
    case .ended: phase = "ended"
    case .cancelled: phase = "cancelled"
    @unknown default: return  // a phase iPadOS adds later is not sent
    }
    let pose = squeeze.hoverPose
    send(
      PencilWire.squeezeEvent(
        t: ProcessInfo.processInfo.systemUptime, phase: phase,
        action: PencilWire.actionName(UIPencilInteraction.preferredSqueezeAction),
        position: pose?.location, z: pose?.zOffset, roll: pose?.rollAngle))
  }

  // MARK: - Hover (≤ 60 Hz)

  @objc private func handleHover(_ recognizer: UIHoverGestureRecognizer) {
    guard recognizer.state == .began || recognizer.state == .changed,
      let view = recognizer.view
    else { return }
    let now = ProcessInfo.processInfo.systemUptime
    if now - lastHover < PencilWire.minInterval {
      return
    }
    lastHover = now
    var z: CGFloat?
    var altitude: CGFloat?
    var azimuth: CGFloat?
    var roll: CGFloat?
    if #available(iOS 16.1, *) {
      z = recognizer.zOffset
    }
    if #available(iOS 16.4, *) {
      altitude = recognizer.altitudeAngle
      azimuth = recognizer.azimuthAngle(in: view)
    }
    if #available(iOS 17.5, *) {
      roll = recognizer.rollAngle
    }
    send(
      PencilWire.hoverEvent(
        t: now, position: recognizer.location(in: view), z: z, altitude: altitude,
        azimuth: azimuth, roll: roll))
  }

  // MARK: - UIGestureRecognizerDelegate

  /// The engine's own hover recognizer also says YES, so both run together;
  /// the roll recognizer never blocks Flutter's touches either.
  func gestureRecognizer(
    _ gestureRecognizer: UIGestureRecognizer,
    shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
  ) -> Bool {
    return true
  }
}
