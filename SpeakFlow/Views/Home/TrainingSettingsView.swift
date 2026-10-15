import SwiftUI
import AVFoundation

@MainActor
struct TrainingSettingsView: View {
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject private var settings = TrainingSettings.shared
    @StateObject private var preview = AudioPreviewModel()
    var body: some View {
        Form {
            Section("每轮练习") {
                Stepper("每轮最多 \(settings.options.roundSize) 题", value: $settings.options.roundSize, in: 1...100)
                Picker("生活场景", selection: $settings.options.scene) {
                    Text("全部场景").tag("all")
                    ForEach(PracticeLibrary.scenes, id: \.id) { item in Text(item.title).tag(item.id) }
                }
                Picker("难度", selection: $settings.options.difficulty) {
                    Text("全部难度").tag(0); Text("基础").tag(1); Text("初级").tag(2); Text("中级").tag(3)
                }
                Text("从符合条件的题库随机选题；可用题目不足时按实际数量练习。题库总量与每轮题数分开。")
                    .font(.footnote).foregroundStyle(SpeakFlowStyle.muted)
            }
            Section("美式英语朗读") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Heart · 已选定美式女声（离线）").font(.headline)
                    HStack {
                        Button("试听单词") { preview.previewVoice(identifier: HeartAudioLibrary.voiceIdentifier, kind: .word, options: settings.options) }
                        Button("试听句子") { preview.previewVoice(identifier: HeartAudioLibrary.voiceIdentifier, kind: .sentence, options: settings.options) }
                    }.buttonStyle(.bordered)

                }
                Text("Heart 是唯一英文朗读音色。完整题库音频已保存在手机中，可离线播放。")
                    .font(.footnote).foregroundStyle(SpeakFlowStyle.muted)

            }
            Section("中文提示朗读") {
                Text("中文女声 3 · 已选定（离线）").font(.headline)
                Button("试听中文") {
                    preview.previewVoice(identifier: HeartAudioLibrary.voiceIdentifier, kind: .word,
                        options: settings.options, language: "zh-CN", text: "苹果")
                }.buttonStyle(.bordered)
            }
            Section("语速分别设置") {
                Text("单词语速"); Slider(value: $settings.options.wordRate, in: 0.3...0.6)
                Text("句子语速"); Slider(value: $settings.options.sentenceRate, in: 0.3...0.6)
                Text("左侧更慢，右侧更快。单词默认较慢，句子默认自然语速。")
                    .font(.footnote).foregroundStyle(SpeakFlowStyle.muted)
            }
            Section("状态音效试听与选择") {
                Text("卡片训练使用视频参考中的正确、错误和完成音效。蓝色录音按钮中的声纹表示麦克风已就绪。")
                    .font(.footnote).foregroundStyle(SpeakFlowStyle.muted)
                Text("音效音量"); Slider(value: $settings.options.cueVolume, in: 0.1...0.6)
                ForEach([CuePack.selected]) { pack in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(pack.title).font(.headline)
                        HStack {
                            Button("完成") { preview.previewCue(.completed, pack: pack, volume: settings.options.cueVolume) }
                            Button("正确") { preview.previewCue(.correct, pack: pack, volume: settings.options.cueVolume) }
                            Button("错误") { preview.previewCue(.incorrect, pack: pack, volume: settings.options.cueVolume) }
                        }.buttonStyle(.bordered)

                    }
                }
                Text("当前：\(settings.options.cuePack.title)").font(.footnote)
            }
            if !preview.status.isEmpty { Section { Text(preview.status) } }
        }
        .modifier(SpeakFlowPageStyle()).toolbar(.visible, for: .navigationBar).navigationTitle("训练设置与试听")
        .onDisappear { preview.stop() }
        .onChange(of: scenePhase) { if $0 != .active { preview.stop() } }
        .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.interruptionNotification)) { _ in preview.stop() }
        .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.routeChangeNotification)) { notification in
            guard let raw = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
                  let reason = AVAudioSession.RouteChangeReason(rawValue: raw) else { return }
            if reason == .oldDeviceUnavailable || reason == .newDeviceAvailable { preview.stop() }
        }
    }
}
