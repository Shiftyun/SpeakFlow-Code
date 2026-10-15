import SwiftUI

@main
struct SpeakFlowApp: App {
    var body: some Scene {
        WindowGroup {
            #if DEBUG
            if CommandLine.arguments.contains("--preview-word") {
                NavigationStack { WordPracticeView() }
            } else if CommandLine.arguments.contains("--preview-sentence") {
                NavigationStack { SentencePracticeView() }
            } else {
                HomeView()
            }
            #else
            HomeView()
            #endif
        }
    }
}
