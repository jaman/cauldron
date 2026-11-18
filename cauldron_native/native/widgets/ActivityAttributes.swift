#if os(iOS)
import ActivityKit
import Foundation

struct CauldronActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var title: String
        var detail: String
        var progress: Double?
        var icon: String
        var ends: Date?
        var endsLabel: String?
        var image: String?
        var compactImage: String?
        var background: String?
        var tint: String?
        var badge: String?
        var url: String?
    }

    var name: String
}
#endif
