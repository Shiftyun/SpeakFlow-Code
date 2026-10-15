import SwiftUI

@MainActor
struct LearningRecordsView: View {
    @ObservedObject private var store = LearningStore.shared
    @State private var filter = 0
    private let words = (try? PracticeLibrary.words()) ?? []
    private let sentences = (try? PracticeLibrary.sentences()) ?? []
    private func included(_ record: LearningRecord) -> Bool {
        switch filter {
        case 1: return record.wrongCount > 0
        case 2: return record.needsPractice
        default: return record.attempts > 0
        }
    }
    var body: some View {
        List {
            Section {
                Picker("显示记录", selection: $filter) {
                    Text("学过").tag(0); Text("答错过").tag(1); Text("不熟练").tag(2)
                }.pickerStyle(.segmented)
                Text("记录保存在本机；普通覆盖更新或签名刷新不会主动清除。卸载 App 会删除本机数据。")
                    .font(.footnote).foregroundStyle(SpeakFlowStyle.muted)
                if let error = store.errorMessage { Text(error).foregroundStyle(.red) }
            }
            Section("单词") {
                ForEach(words.filter { included(store.record(for: $0.id, kind: .word)) }.sorted {
                    (store.record(for: $0.id, kind: .word).lastPracticedAt ?? .distantPast) >
                    (store.record(for: $1.id, kind: .word).lastPracticedAt ?? .distantPast)
                }) { item in
                    row(title: "\(item.word) · \(item.meaningZh)", record: store.record(for: item.id, kind: .word))
                }
            }
            Section("句子") {
                ForEach(sentences.filter { included(store.record(for: $0.id, kind: .sentence)) }.sorted {
                    (store.record(for: $0.id, kind: .sentence).lastPracticedAt ?? .distantPast) >
                    (store.record(for: $1.id, kind: .sentence).lastPracticedAt ?? .distantPast)
                }) { item in
                    row(title: item.text, record: store.record(for: item.id, kind: .sentence))
                }
            }
            Section {
                Text("不熟练：答对不足 3 次，或累计正确率低于 80%。这是简单学习标记，不是发音评分；优先复习算法留待后续阶段。")
                    .font(.footnote).foregroundStyle(SpeakFlowStyle.muted)
            }
        }.modifier(SpeakFlowPageStyle()).toolbar(.visible, for: .navigationBar).navigationTitle("学习记录")
    }
    private func row(title: String, record: LearningRecord) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
            Text("答对 \(record.correctCount) · 答错 \(record.wrongCount) · 正确率 \(Int(record.mastery * 100))%")
                .font(.caption).foregroundStyle(SpeakFlowStyle.muted)
            if let date = record.lastPracticedAt { Text("最近练习：\(date.formatted(date: .abbreviated, time: .shortened))").font(.caption) }
        }
    }
}
