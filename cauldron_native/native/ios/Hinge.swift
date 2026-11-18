import UIKit

enum Hinge {
    static func watch(_ view: UIView) {
        #if os(iOS)
        guard #available(iOS 27.1, *) else { return }
        view.addInteraction(UIHingeInteraction { _, update in report(update.hinge) })
        #endif
    }

    #if os(iOS)
    @available(iOS 27.1, *)
    private static func report(_ hinge: UIHinge?) {
        guard let hinge else { return }
        cn_posture(fold(hinge.status), 1, Float(hinge.angle * 180 / .pi), 0, 0, 0, 0, 0, 0, 0)
    }

    @available(iOS 27.1, *)
    private static func fold(_ status: UIHinge.Status) -> Int32 {
        switch status {
        case .closed: Int32(CN_FOLD_CLOSED)
        case .partiallyOpen: Int32(CN_FOLD_HALF_OPEN)
        case .fullyOpen: Int32(CN_FOLD_OPEN)
        default: Int32(CN_FOLD_UNKNOWN)
        }
    }
    #endif
}
