import SwiftUI
import UIKit

// SpeakFlow styling inspired by the user-selected Mural reference.
// Original SwiftUI implementation; no external UI runtime or branded assets.
enum SpeakFlowStyle {
    static func adaptive(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(uiColor: UIColor { traits in
            let hex = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: CGFloat((hex >> 16) & 255) / 255,
                green: CGFloat((hex >> 8) & 255) / 255, blue: CGFloat(hex & 255) / 255, alpha: 1)
        })
    }
    static let background = adaptive(0xFFF9EF, 0x201C18)
    static let surface = adaptive(0xFFFCF5, 0x2C2621)
    static let ink = adaptive(0x362A20, 0xF5EBDD)
    static let muted = adaptive(0x806957, 0xBFAE9D)
    static let accent = adaptive(0xB64720, 0xFFA478)
}

struct SpeakFlowPageStyle: ViewModifier {
    func body(content: Content) -> some View {
        content.scrollContentBackground(.hidden)
            .background(SpeakFlowStyle.background.ignoresSafeArea())
            .foregroundStyle(SpeakFlowStyle.ink)
            .tint(SpeakFlowStyle.accent).font(.system(.body, design: .rounded))
    }
}

@MainActor
struct HomeView: View {
    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 24) {
                        HStack {
                            Circle().fill(SpeakFlowStyle.accent.gradient).frame(width: 16, height: 16)
                            Text("SpeakFlow").font(.system(.title2, design: .rounded).bold())
                            Spacer()
                            NavigationLink { TrainingSettingsView() } label: {
                                Image(systemName: "slider.horizontal.3").font(.title3)
                                    .frame(width: 48, height: 48)
                            }.accessibilityLabel("训练设置与试听")
                        }
                        Spacer(minLength: 12)
                        VStack(spacing: 20) {
                            NavigationLink { WordPracticeView() } label: {
                                mode("单词模式", icon: "character.book.closed")
                            }.accessibilityIdentifier("home.wordMode")
                            NavigationLink { SentencePracticeView() } label: {
                                mode("句子模式", icon: "waveform")
                            }.accessibilityIdentifier("home.sentenceMode")
                        }.buttonStyle(.plain)
                        Spacer(minLength: 12)
                        VStack(spacing: 0) {
                            NavigationLink { LearningRecordsView() } label: {
                                linkRow("学习记录", icon: "clock.arrow.circlepath")
                            }
                            Divider().padding(.leading, 48)
                            NavigationLink { ContentSourcesView() } label: {
                                linkRow("题库与内容来源", icon: "books.vertical")
                            }
                        }.buttonStyle(.plain)
                    }.padding(24).frame(minHeight: geometry.size.height)
                }
            }.modifier(SpeakFlowPageStyle()).toolbar(.hidden, for: .navigationBar)
        }
    }
    private func mode(_ title: String, icon: String) -> some View {
        HStack(spacing: 18) {
            Image(systemName: icon).font(.title2).foregroundStyle(SpeakFlowStyle.accent)
                .frame(width: 52, height: 52)
                .background(SpeakFlowStyle.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
            Text(title).font(.system(.title2, design: .rounded).bold())
            Spacer(minLength: 0)
            Image(systemName: "arrow.up.right").foregroundStyle(SpeakFlowStyle.muted)
        }.padding(24).frame(maxWidth: .infinity, minHeight: 120, alignment: .leading)
            .background(SpeakFlowStyle.surface, in: RoundedRectangle(cornerRadius: 28))
            .overlay(RoundedRectangle(cornerRadius: 28).stroke(SpeakFlowStyle.muted.opacity(0.08)))
            .shadow(color: .black.opacity(0.025), radius: 16, y: 6)
            .contentShape(RoundedRectangle(cornerRadius: 28))
    }
    private func linkRow(_ title: String, icon: String) -> some View {
        HStack(spacing: 16) {
            Image(systemName: icon).frame(width: 28).foregroundStyle(SpeakFlowStyle.muted)
            Text(title).font(.headline)
            Spacer()
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(SpeakFlowStyle.muted)
        }.padding(.vertical, 20).frame(maxWidth: .infinity).contentShape(Rectangle())
    }
}


/// Layered waves with quiet idle motion; microphone amplitude adds height.
struct InputWaveform: View {
    let level: Double
    private let ink = Color(red: 0, green: 0.65, blue: 0.9)
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: false)) { timeline in
            let phase = timeline.date.timeIntervalSinceReferenceDate * 2.3
            let amplitude = 0.10 + 0.90 * level
            ZStack {
                    ForEach(1..<5) { layer in
                        VoiceWave(level: amplitude * (1 - Double(layer) * 0.17), phase: phase - Double(layer) * 0.12)
                            .stroke(ink.opacity(0.22 - Double(layer) * 0.035), style: StrokeStyle(lineWidth: 1, lineCap: .round))
                    }
                VoiceWave(level: amplitude, phase: phase)
                    .stroke(ink, style: StrokeStyle(lineWidth: 2, lineCap: .round))
            }
        }.animation(.easeOut(duration: 0.14), value: level)
            .accessibilityLabel("波浪声纹，点击暂停")
    }
}

private struct VoiceWave: Shape {
    var level: Double
    var phase: Double
    var animatableData: Double {
        get { level }
        set { level = newValue }
    }
    func path(in rect: CGRect) -> Path {
        var path = Path()
        for step in 0...160 {
            let x = Double(step) / 160
            let envelope = pow(sin(.pi * x), 0.65)
            let height = sin(x * .pi * 2 - phase) * envelope * level * Double(rect.height * 0.42)
            let point = CGPoint(x: rect.minX + x * Double(rect.width), y: rect.midY + height)
            if step == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        return path
    }
}
