// pencil_bridge (INFRA, docs/plans/m5-7/01-infra.md 4.4.4 and 6.12.2): a
// passive recognizer that reports UITouch.rollAngle of the pencil while
// drawing, at most 60 times a second ({type: roll, t, angle}).
//
// It never recognizes and never holds Flutter's touches back: no cancel, no
// delayed began / ended, and it fails when the touch ends. Pairing a roll
// value with a Flutter PointerEvent is EDITOR's ('latest roll at pen down' —
// contract 7.2.9).
import UIKit
import UIKit.UIGestureRecognizerSubclass

@available(iOS 17.5, *)
final class PencilRollRecognizer: UIGestureRecognizer {
  /// (t = UITouch.timestamp seconds, angle in rad).
  var onRoll: ((TimeInterval, CGFloat) -> Void)?
  private var lastSent: TimeInterval = -Double.infinity

  override init(target: Any?, action: Selector?) {
    super.init(target: target, action: action)
    cancelsTouchesInView = false
    delaysTouchesBegan = false
    delaysTouchesEnded = false
    allowedTouchTypes = [NSNumber(value: UITouch.TouchType.pencil.rawValue)]
  }

  override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
    super.touchesBegan(touches, with: event)
    report(touches)
  }

  override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
    super.touchesMoved(touches, with: event)
    report(touches)
  }

  override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
    super.touchesEnded(touches, with: event)
    state = .failed
  }

  override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
    super.touchesCancelled(touches, with: event)
    state = .failed
  }

  override func reset() {
    super.reset()
    lastSent = -Double.infinity
  }

  private func report(_ touches: Set<UITouch>) {
    for touch in touches where touch.type == .pencil {
      if touch.timestamp - lastSent < PencilWire.minInterval {
        continue
      }
      lastSent = touch.timestamp
      onRoll?(touch.timestamp, touch.rollAngle)
    }
  }
}
