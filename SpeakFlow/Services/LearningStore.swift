import Foundation
import Combine

enum PracticeKind: String, Codable { case word, sentence }

struct LearningRecord: Codable, Equatable {
    var correctCount = 0
    var wrongCount = 0
    var lastPracticedAt: Date? = nil
    var attempts: Int { correctCount + wrongCount }
    var mastery: Double { attempts == 0 ? 0 : Double(correctCount) / Double(attempts) }
    var needsPractice: Bool { attempts > 0 && (correctCount < 3 || mastery < 0.8) }
}

@MainActor
protocol LearningRecording: AnyObject {
    func record(for id: String, kind: PracticeKind) -> LearningRecord
    func saveAnswer(id: String, kind: PracticeKind, correct: Bool, date: Date) throws
}

@MainActor
final class LearningStore: ObservableObject, LearningRecording {
    static let shared = LearningStore()
    @Published private(set) var records: [String: LearningRecord] = [:]
    @Published private(set) var errorMessage: String?
    private let fileURL: URL
    private struct Snapshot: Codable {
        var version = 1
        var records: [String: LearningRecord]
    }

    init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? FileManager.default.urls(for: .applicationSupportDirectory,
            in: .userDomainMask)[0].appendingPathComponent("SpeakFlow/learning-v1.json")
        guard FileManager.default.fileExists(atPath: self.fileURL.path) else { return }
        do {
            let snapshot = try JSONDecoder().decode(Snapshot.self, from: Data(contentsOf: self.fileURL))
            guard snapshot.version == 1,
                  snapshot.records.values.allSatisfy({ $0.correctCount >= 0 && $0.wrongCount >= 0 }) else {
                throw StoreError.invalidData
            }
            records = snapshot.records
        } catch {
            errorMessage = "学习记录暂时无法读取，原文件已保留。请先反馈问题，避免覆盖已有记录。"
        }
    }

    func record(for id: String, kind: PracticeKind) -> LearningRecord {
        records["\(kind.rawValue):\(id)"] ?? LearningRecord()
    }

    func saveAnswer(id: String, kind: PracticeKind, correct: Bool, date: Date = Date()) throws {
        guard errorMessage == nil else { throw StoreError.invalidData }
        let key = "\(kind.rawValue):\(id)"
        var updated = records
        var item = updated[key] ?? LearningRecord()
        if correct { item.correctCount += 1 } else { item.wrongCount += 1 }
        item.lastPracticedAt = date
        updated[key] = item
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(Snapshot(records: updated))
            try data.write(to: fileURL, options: .atomic)
            records = updated
        } catch {
            throw StoreError.writeFailed
        }
    }

    enum StoreError: LocalizedError {
        case invalidData, writeFailed
        var errorDescription: String? {
            switch self {
            case .invalidData: return "已有学习记录无法读取，已保留原文件。"
            case .writeFailed: return "学习记录保存失败，请检查设备空间后继续。"
            }
        }
    }
}
