import SwiftUI

struct WaveSample: Identifiable {
    let id = UUID()
    let value: CGFloat
    let time: TimeInterval
}

struct WaveformView: View {
    let audioLevel: Float
    let isRecording: Bool
    let timeElapsed: TimeInterval
    
    // Настройки
    private let pixelsPerSecond: CGFloat = 65.0
    private let barWidth: CGFloat = 2.5
    private let barSpacing: CGFloat = 2.0
    private let accentColor = Color.red
    private let verticalPadding: CGFloat = 4.0
    
    @State private var samples: [WaveSample] = []
    @State private var smoothedLevel: CGFloat = 0
    
    var body: some View {
        GeometryReader { geo in
            Canvas { context, size in
                let midX = size.width / 2
                let waveHeight = size.height - 30
                let midY = waveHeight / 2
                
                // --- отрисовка таймлайна ---
                let visibleSecondsRange = Double(size.width / pixelsPerSecond)
                let firstVisibleSecond = max(0, Int(timeElapsed - visibleSecondsRange))
                let lastVisibleSecond = Int(timeElapsed + visibleSecondsRange) + 1
                
                for sec in firstVisibleSecond...lastVisibleSecond {
                    let x = midX + CGFloat(Double(sec) - timeElapsed) * pixelsPerSecond
                    
                    let tickStartY = waveHeight + verticalPadding
                    let tickEndY = tickStartY + 10 // Длина палочки
                    
                    var tickPath = Path()
                    tickPath.move(to: CGPoint(x: x, y: tickStartY))
                    tickPath.addLine(to: CGPoint(x: x, y: tickEndY))
                    context.stroke(tickPath, with: .color(.secondary.opacity(0.5)), lineWidth: 1)
                    
                    if sec > 0 {
                        let text = Text("\(sec)s")
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundColor(.secondary)
                        // Текст рисуем чуть ниже палочки
                        context.draw(text, at: CGPoint(x: x, y: tickEndY + 6))
                    }
                    
                    // Мелкие деления
                    for i in 1...3 {
                        let tickX = x + CGFloat(Double(i) * 0.25) * pixelsPerSecond
                        let minorTickStartY = waveHeight + verticalPadding + 4
                        var minorPath = Path()
                        minorPath.move(to: CGPoint(x: tickX, y: minorTickStartY))
                        minorPath.addLine(to: CGPoint(x: tickX, y: tickEndY))
                        context.stroke(minorPath, with: .color(.secondary.opacity(0.2)), lineWidth: 1)
                    }
                }
                
                // --- отрисовка волны ---
                var wavePath = Path()
                for sample in samples {
                    let x = midX + CGFloat(sample.time - timeElapsed) * pixelsPerSecond
                    if x < -barWidth || x > size.width + barWidth { continue }
                    
                    // Максимальная высота волны с учетом отступов сверху и снизу
                    let maxHeight = waveHeight - (verticalPadding * 2)
                    let height = max(barWidth, sample.value * maxHeight)
                    let y = midY - height / 2
                    
                    let rect = CGRect(x: x - barWidth/2, y: y, width: barWidth, height: height)
                    wavePath.addRoundedRect(in: rect, cornerSize: CGSize(width: barWidth/2, height: barWidth/2))
                }
                context.fill(wavePath, with: .color(accentColor))
                
                // --- плейхед (ц. линия) ---
                var playhead = Path()
                playhead.move(to: CGPoint(x: midX, y: verticalPadding)) // симметричный отступ verticalPadding сверху и снизу (4)
                playhead.addLine(to: CGPoint(x: midX, y: waveHeight - verticalPadding))
                context.stroke(playhead, with: .color(accentColor), lineWidth: 1.5)
            }
        }
        .frame(height: 110)
        .onChange(of: timeElapsed) { newTime in
            guard isRecording else { return }
            
            if newTime == 0 {
                samples.removeAll()
                return
            }
            
            let timePerSample = TimeInterval((barWidth + barSpacing) / pixelsPerSecond)
            let lastTime = samples.last?.time ?? 0
            
            if newTime - lastTime >= timePerSample {
                let rawLevel = CGFloat(audioLevel)
                
                smoothedLevel = (rawLevel * 0.3) + (smoothedLevel * 0.7)
                
                let gain: CGFloat = 3.5
                
                let dynamicLevel = pow(smoothedLevel, 1.4) * gain  // используем степень
                
                // Обрезаем верхушку только если звук реально очень громкий
                let amplified = min(1.0, dynamicLevel)
                
                // Оставляем минимальную точку (0.02) для тишины, чтобы волна не исчезала
                let finalValue = max(0.01, amplified)
                
                samples.append(WaveSample(value: finalValue, time: newTime))
                
                if samples.count > 400 {
                    samples.removeAll(where: { $0.time < newTime - 15.0 })
                }
            }
        }
    }
}
