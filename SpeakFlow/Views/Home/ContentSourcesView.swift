import SwiftUI

struct ContentSourcesView: View {
    private let notice: String = {
        guard let url = Bundle.main.url(forResource: "ContentLicenses", withExtension: "txt") else { return "内容来源暂时无法读取。" }
        return (try? String(contentsOf: url, encoding: .utf8)) ?? "内容来源暂时无法读取。"
    }()
    var body: some View {
        List {
            Section("正式题库") {
                Text("3000 个单词 · 1200 个句子。每轮题数在训练设置中单独调整。")
                Text("单词复用 ECDICT 英汉释义，优先有频率记录的常见词；句子主要来自 VOA 美式英语教学对话，另含 60 句本项目初始内容。")
                Text("场景标签与三级难度用于选题，是导入时的初步分类，不代表正式 CEFR 等级。部分词有多个含义，释义用于提示当前英文词。")
                Link("ECDICT 开源词库", destination: URL(string: "https://github.com/skywind3000/ECDICT")!)
                Link("VOA 美式英语课程", destination: URL(string: "https://learningenglish.voanews.com/p/5644.html")!)
            }
            Section("离线英文朗读") {
                Text("Heart 美式女声：开发阶段用 Kokoro 预先生成，手机仅播放本地音频，未安装语音模型。")
                Text("模型和所选英文音色来源标注 Apache-2.0；生成工具只在开发电脑使用。官方未给生成音频另附独立许可证，来源与生成记录已保留。")
                Link("Kokoro 官方模型", destination: URL(string: "https://huggingface.co/hexgrad/Kokoro-82M")!)
            }
            Section("离线中文朗读") {
                Text("用户选定的中文女声 3（zf_003），由 Kokoro 中文专用版本预先生成，本地离线播放。")
                Link("中文模型来源", destination: URL(string: "https://huggingface.co/hexgrad/Kokoro-82M-v1.1-zh")!)
            }
            Section("来源与许可") { Text(notice).font(.footnote).textSelection(.enabled) }
        }.modifier(SpeakFlowPageStyle()).toolbar(.visible, for: .navigationBar).navigationTitle("题库与内容来源")
    }
}
