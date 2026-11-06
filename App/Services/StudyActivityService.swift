import Foundation
import ActivityKit
import MnemoCore

@MainActor final class StudyActivityService {
    private var activity: Activity<StudyAttributes>?
    private var started = Date()
    func start(total: Int, language: Language, enabled: Bool) {
        #if MNEMO_WIDGETS
        guard enabled, ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        started = Date()
        let state = StudyAttributes.ContentState(completed: 0, total: total, started: started)
        activity = try? Activity.request(attributes: StudyAttributes(language: language.rawValue), content: ActivityContent(state: state, staleDate: Date().addingTimeInterval(3600)), pushType: nil)
        #endif
    }
    func update(completed: Int, total: Int) {
        guard let activity else { return }
        let content = ActivityContent(state: StudyAttributes.ContentState(completed: completed, total: total, started: started), staleDate: Date().addingTimeInterval(3600))
        Task { await activity.update(content) }
    }
    func end() {
        guard let activity else { return }; self.activity = nil
        Task { await activity.end(nil, dismissalPolicy: .immediate) }
    }
}
