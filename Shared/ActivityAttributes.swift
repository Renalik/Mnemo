import Foundation
import ActivityKit

struct StudyAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var completed: Int
        var total: Int
        var started: Date
    }
    var language: String
}

struct WidgetSnapshot: Codable {
    var due: Int
    var reviewed: Int
    var streak: Int
    var language: String
    var accent: String
    var date: Date
}
