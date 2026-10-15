import SwiftUI

/// Shared presentation for both training modes. The microphone becomes active only on capture readiness.
struct TrainingCardView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let title: String
    let prompt: String
    let answer: String
    let phonetic: String?
    let hidden: Bool
    let state: PracticeState
    let progress: Double
    let ready: Bool
    let level: Double
    let total: Int
    let mistakes: Int
    let elapsed: TimeInterval
    let start: () -> Void
    let pause: () -> Void
    let replay: () -> Void
    let reveal: () -> Void
    let submit: (String) -> Void
    @State private var typing = false
    @State private var typedAnswer = ""
    private let blue = Color(red: 0.10, green: 0.69, blue: 0.94)
    private let green = Color(red: 0.34, green: 0.77, blue: 0.04)
    private var feedback: Bool { state == .success || state == .retry }
    private var busy: Bool { state == .preparing || state == .playingPrompt || state == .processingSpeech || feedback || state == .movingToNext || (state == .listening && !ready) }
    private var active: Bool { state == .listening }
    private var cardColor: Color { state == .success ? Color(red: 0.86, green: 0.97, blue: 0.71) : state == .retry ? Color(red: 1, green: 0.95, blue: 0.72) : .white }
    private var answerColor: Color { state == .success ? green : Color(red: 0.87, green: 0.66, blue: 0.02) }

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                HStack(spacing: 20) {
                    Button { pause(); dismiss() } label: {
                        Image(systemName: "xmark").font(.system(size: 22, weight: .bold)).foregroundStyle(.gray)
                            .frame(width: 44, height: 44)
                    }.accessibilityLabel("退出练习")
                    GeometryReader { track in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color(white: 0.91))
                            Capsule().fill(green).frame(width: max(0, track.size.width * min(1, max(0, progress))))
                        }
                    }.frame(height: 15).animation(reduceMotion ? nil : .easeInOut(duration: 0.35), value: progress).accessibilityLabel("练习进度")
                        .accessibilityValue("\(Int(progress * 100))%")
                }.padding(.horizontal, 18).padding(.top, 6)
                if state == .completed {
                    completion
                } else {
                    Text(title).font(.system(size: 22, weight: .bold, design: .rounded))
                        .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 28).padding(.top, 24)
                    Spacer(minLength: 20)
                    let width = min(280.0, geometry.size.width * 0.62)
                    ZStack {
                        ForEach(1..<5) { layer in
                            RoundedRectangle(cornerRadius: 22).fill(Color.white)
                                .overlay(RoundedRectangle(cornerRadius: 22).stroke(Color(white: 0.88), lineWidth: 1.5))
                                .frame(width: width - CGFloat(layer) * 13, height: width * 1.06)
                                .offset(y: -CGFloat(layer) * 8)
                        }
                        RoundedRectangle(cornerRadius: 24).fill(cardColor)
                            .overlay(RoundedRectangle(cornerRadius: 24).stroke(feedback ? answerColor.opacity(0.3) : Color(white: 0.87), lineWidth: 1.5))
                        VStack(spacing: 14) {
                            Text(feedback ? answer : prompt)
                                .font(.system(size: feedback ? 30 : 32, weight: .bold, design: .rounded))
                                .multilineTextAlignment(.center).lineLimit(6).minimumScaleFactor(0.45)
                                .foregroundStyle(feedback ? answerColor : Color(white: 0.15))
                                .blur(radius: hidden && !feedback ? 7 : 0)
                                .accessibilityLabel(hidden && !feedback ? "句子已遮挡，点击显示" : feedback ? answer : prompt)
                            if feedback, let phonetic, !phonetic.isEmpty {
                                Text("/\(phonetic)/").font(.system(size: 16)).foregroundStyle(answerColor)
                                    .multilineTextAlignment(.center).lineLimit(2)
                            }
                        }.padding(24)
                        if state == .success {
                            Image(systemName: "sparkles").font(.system(size: 20)).foregroundStyle(.white)
                                .offset(x: width * 0.35, y: -width * 0.35).accessibilityHidden(true)
                        }
                    }.frame(width: width, height: width * 1.06)
                        .contentShape(RoundedRectangle(cornerRadius: 24)).onTapGesture(perform: reveal)
                        .animation(reduceMotion ? nil : .easeInOut(duration: 0.22), value: state)
                    HStack(spacing: 12) {
                        Button { active ? pause() : start() } label: {
                            Group {
                                if ready && active { MicrophoneBars(level: level) }
                                else { Image(systemName: "mic.fill").font(.system(size: 26, weight: .semibold)) }
                            }.foregroundStyle(.white).frame(width: width - 66, height: 54)
                        }.buttonStyle(TrainingRaisedButtonStyle(color: busy ? Color(white: 0.85) : blue))
                            .disabled(busy).accessibilityLabel(ready && active ? "正在录音，点击暂停" : "开始或继续录音")
                        Button(action: replay) {
                            Image(systemName: "arrow.triangle.2.circlepath").font(.system(size: 23, weight: .bold))
                                .foregroundStyle(busy ? Color(white: 0.8) : blue).frame(width: 54, height: 54)
                        }.buttonStyle(TrainingRaisedButtonStyle(color: .white, outlined: true))
                            .disabled(busy).accessibilityLabel("重播提示并重新录音")
                    }.padding(.top, 30)
                    if case .error(let message) = state {
                        Text(message).font(.footnote).foregroundStyle(Color(white: 0.4)).multilineTextAlignment(.center)
                            .padding(.horizontal, 28).padding(.top, 20)
                    }
                    Spacer(minLength: 20)
                    Button { pause(); typedAnswer = ""; typing = true } label: {
                        Text("输入答案").font(.system(size: 14, weight: .medium)).foregroundStyle(Color(white: 0.6))
                            .frame(minHeight: 44)
                    }.disabled(busy).padding(.bottom, 24)
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        }.background(Color.white.ignoresSafeArea()).preferredColorScheme(.light)
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $typing) {
                NavigationStack {
                    Form {
                        TextField("输入英文答案", text: $typedAnswer).textInputAutocapitalization(.never).autocorrectionDisabled()
                        Button("确认答案") { let text = typedAnswer; typing = false; submit(text) }
                            .disabled(typedAnswer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }.navigationTitle("输入答案").toolbar { Button("取消") { typing = false } }
                }.presentationDetents([.medium])
            }
    }

    private var completion: some View {
        VStack(spacing: 30) {
            Spacer()
            ZStack {
                ForEach(0..<16) { n in
                    RoundedRectangle(cornerRadius: 2).fill(n % 2 == 0 ? green : Color.yellow)
                        .frame(width: 7, height: 14).rotationEffect(.degrees(Double(n * 37)))
                        .offset(x: cos(Double(n) * .pi / 8) * 105, y: sin(Double(n) * .pi / 8) * 105)
                }
                Circle().fill(green.opacity(0.12)).frame(width: 150, height: 150)
                Image(systemName: "checkmark.seal.fill").font(.system(size: 106)).foregroundStyle(green)
            }.frame(height: 225)
            Text("练习完成！").font(.system(size: 29, weight: .bold, design: .rounded)).foregroundStyle(Color(red: 0.91, green: 0.69, blue: 0))
            HStack(spacing: 10) {
                summary("完成", "\(total)", "checkmark", green)
                summary("待加强次数", "\(mistakes)", "arrow.clockwise", .orange)
                summary("用时", String(format: "%d:%02d", Int(elapsed) / 60, Int(elapsed) % 60), "clock", blue)
            }
            Spacer()
            Button { pause(); dismiss() } label: {
                Text("完成练习").font(.system(size: 18, weight: .bold)).foregroundStyle(.white)
                    .frame(maxWidth: .infinity).frame(height: 52)
            }.buttonStyle(TrainingRaisedButtonStyle(color: blue)).padding(.bottom, 24)
        }.padding(.horizontal, 25)
    }
    private func summary(_ label: String, _ value: String, _ icon: String, _ color: Color) -> some View {
        VStack(spacing: 12) {
            Text(label).font(.system(size: 12, weight: .bold)).foregroundStyle(.white)
                .frame(maxWidth: .infinity).padding(.vertical, 7).background(color)
            Label(value, systemImage: icon).font(.system(size: 17, weight: .bold)).foregroundStyle(color).padding(.bottom, 14)
        }.frame(maxWidth: .infinity).clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(color, lineWidth: 2))
    }
}

struct TrainingRaisedButtonStyle: ButtonStyle {
    let color: Color
    var outlined = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.background(color, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(outlined ? Color(white: 0.88) : color, lineWidth: 1.5))
            .background(RoundedRectangle(cornerRadius: 12).fill(outlined ? Color(white: 0.86) : color.opacity(0.65)).offset(y: 4))
            .offset(y: configuration.isPressed ? 3 : 0)
    }
}

private struct MicrophoneBars: View {
    let level: Double
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 20, paused: level < 0.01)) { timeline in
            HStack(spacing: 4) {
                ForEach(0..<11) { index in
                    let envelope = 1 - abs(Double(index - 5)) / 6
                    let movement = 0.5 + 0.5 * abs(sin(timeline.date.timeIntervalSinceReferenceDate * 9 + Double(index)))
                    Capsule().fill(Color.white).frame(width: 3, height: 3 + 27 * min(1, max(0, level)) * envelope * movement)
                }
            }.frame(height: 32)
        }.accessibilityHidden(true)
    }
}
