import Foundation
import AVFoundation

class TTSService: NSObject, ObservableObject {
    static let shared = TTSService()
    
    private let synthesizer = AVSpeechSynthesizer()
    
    @Published var isPlaying = false
    @Published var isPaused = false
    @Published var currentRate: Float = UserDefaults.standard.float(forKey: "ttsRate") > 0 ? UserDefaults.standard.float(forKey: "ttsRate") : 0.5
    
    // 用于追踪播放进度的属性
    @Published var totalCharacters: Int = 0
    @Published var spokenCharacters: Int = 0
    @Published var playbackProgress: Double = 0.0
    
    private var currentText: String = "" // 存储当前朗读的完整文本
    private var currentPosition: Int = 0 // 代表在完整文本中的当前位置
    private var currentTextOffset: Int = 0 // 当播放剩余文本时，记录其在完整文本中的起始偏移
    
    private let voiceIdentifier = "com.apple.ttsbundle.Mei-Jia-compact" // 默认台湾话语音
    private var selectedVoice: AVSpeechSynthesisVoice?
    
    override init() {
        super.init()
        synthesizer.delegate = self
        loadVoice()
        setupAudioSession() // 设置音频会话
    }
    
    private func loadVoice() {
        if let voice = AVSpeechSynthesisVoice(identifier: voiceIdentifier) {
            selectedVoice = voice
        } else {
            selectedVoice = AVSpeechSynthesisVoice(language: "zh-CN") // 备选中文语音
            print("[TTSService] Preferred voice not found, using default zh-CN.")
        }
    }

    private func setupAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [])
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("[TTSService] Failed to set up audio session: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Public Methods
    
    func speak(_ text: String) {
        synthesizer.stopSpeaking(at: .immediate) // 确保停止任何当前播放
        
        currentText = text
        currentPosition = 0
        currentTextOffset = 0
        isPaused = false
        
        // 更新进度相关属性
        totalCharacters = text.count
        spokenCharacters = 0
        updatePlaybackProgress()
        
        if text.isEmpty {
            print("[TTSService] Attempted to speak empty text.")
            // 更新UI状态，即使文本为空
            DispatchQueue.main.async {
                self.isPlaying = false
                self.isPaused = false
                self.totalCharacters = 0
                self.spokenCharacters = 0
                self.playbackProgress = 0.0
            }
            return
        }
        
        startSpeakingInternal(from: currentText)
    }
    
    func pause() {
        if synthesizer.isSpeaking {
            synthesizer.pauseSpeaking(at: .word)
        }
    }
    
    func resume() {
        if isPaused {
            guard currentPosition < currentText.count else {
                stop() // 如果已经到末尾，则停止
                return
            }
            let startIndex = currentText.index(currentText.startIndex, offsetBy: currentPosition)
            let remainingText = String(currentText[startIndex...])
            
            self.currentTextOffset = self.currentPosition // 更新偏移量
            
            startSpeakingInternal(from: remainingText)
        }
    }
    
    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
        // 状态和进度重置由 didCancel 或 didFinish 代理处理
    }
    
    func togglePlayPause() {
        if isPlaying { // 如果正在播放，则暂停
            pause()
        } else if isPaused { // 如果已暂停，则继续
            resume()
        } else { // 如果未播放且未暂停（即停止状态），则从头开始播放
            if !currentText.isEmpty {
                // 重置进度并从头播放
                spokenCharacters = 0
                currentPosition = 0
                currentTextOffset = 0
                updatePlaybackProgress()
                speak(currentText)
            } else {
                print("[TTSService] No text to play for togglePlayPause.")
            }
        }
    }
    
    func updateRate(_ newRate: Float) {
        let clampedRate = max(AVSpeechUtteranceMinimumSpeechRate, min(AVSpeechUtteranceMaximumSpeechRate, newRate))
        currentRate = clampedRate
        UserDefaults.standard.set(currentRate, forKey: "ttsRate")
        
        if isPlaying { // 如果正在播放，则暂停再继续以应用新语速
            // 记录当前播放的文本段，以便重新播放
            let textToContinueFrom = String(currentText.dropFirst(currentPosition))
            
            synthesizer.stopSpeaking(at: .immediate) // 立即停止
            
            // 确保偏移量正确
            self.currentTextOffset = self.currentPosition
            
            // 延迟一点点时间再播放，给synthesizer足够时间停止
             DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                if !textToContinueFrom.isEmpty {
                    self.startSpeakingInternal(from: textToContinueFrom)
                } else if !self.currentText.isEmpty && self.currentPosition >= self.currentText.count {
                    // 如果已经播放完毕，则重置
                     self.stop()
                }
             }
        } else if isPaused { // 如果已暂停，则标记需要在恢复时重建utterance
             // resume() 方法会检查并用新语速创建 utterance
        }
    }
    
    // MARK: - Private Methods
    
    private func startSpeakingInternal(from text: String) {
        // 在播放新utterance前，先强制停止当前的，以清除暂停等状态
        // 这一步很重要，因为直接在 paused 状态下 speak 新的 utterance 可能导致没声音
        // 但如果不是 paused 状态，过度 stop 也可能打断流畅性。
        // speak() 方法开头已经 stop 过了，这里确保如果之前有 utterance 在队列，则清除。
        if synthesizer.isSpeaking || synthesizer.isPaused {
             synthesizer.stopSpeaking(at: .immediate)
        }

        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = currentRate
        utterance.voice = selectedVoice
        // utterance.postUtteranceDelay = 0.005 // 可选：添加一点延迟，有时有帮助
        
        // 确保在主线程调用speak
        DispatchQueue.main.async {
            self.synthesizer.speak(utterance)
        }
    }
    
    private func updatePlaybackProgress() {
        guard totalCharacters > 0 else {
            playbackProgress = 0.0
            return
        }
        // 确保 spokenCharacters 不会超过 totalCharacters
        let currentSpoken = min(spokenCharacters, totalCharacters)
        playbackProgress = Double(currentSpoken) / Double(totalCharacters)
    }
}

// MARK: - AVSpeechSynthesizerDelegate
extension TTSService: AVSpeechSynthesizerDelegate {
    
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        DispatchQueue.main.async {
            self.isPlaying = true
            self.isPaused = false
        }
    }
    
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        DispatchQueue.main.async {
            // 检查是否所有文本都已完成
            // currentTextOffset + utterance.speechString.count 应该等于 fullText.count
            // 或者，如果 spokenCharacters 达到了 totalCharacters
            // 由于我们分段播放，这个完成可能只是一个片段的完成
            // 真正的“完成”是当 spokenCharacters >= totalCharacters

            if self.currentTextOffset + utterance.speechString.count >= self.totalCharacters || self.spokenCharacters >= self.totalCharacters {
                 self.isPlaying = false
                 self.isPaused = false
                 // 不在此处重置 spokenCharacters 和 totalCharacters，除非明确是整个任务结束
                 // speak 方法会重置它们。这里只标记播放停止。
                 // 如果希望播放完自动重置进度条，可以在此设置 spokenCharacters = totalCharacters 以确保进度条满
                 self.spokenCharacters = self.totalCharacters
                 self.updatePlaybackProgress() // 更新到100%

            } else {
                // 这可能是一个片段完成，如果还有后续，isPlaying 可能不应该设为 false
                // 但对于简单的实现，每次utterance结束，就认为当前播放停止了
                 self.isPlaying = false
                 self.isPaused = false
            }
        }
    }
    
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didPause utterance: AVSpeechUtterance) {
        DispatchQueue.main.async {
            self.isPlaying = false
            self.isPaused = true
        }
    }
    
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didContinue utterance: AVSpeechUtterance) {
        DispatchQueue.main.async {
            self.isPlaying = true
            self.isPaused = false
        }
    }
    
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        DispatchQueue.main.async {
            self.isPlaying = false
            self.isPaused = false
            // 取消时，可以考虑重置进度，但这取决于产品逻辑
            // 通常，stop() 会调用这个，所以进度应该重置为初始状态
            self.spokenCharacters = 0
            self.currentPosition = 0
            self.currentTextOffset = 0
            // totalCharacters 保持不变，直到新的 speak()
            self.updatePlaybackProgress()
        }
    }
    
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, willSpeakRangeOfSpeechString characterRange: NSRange, utterance: AVSpeechUtterance) {
        DispatchQueue.main.async {
            // characterRange.location 是相对于当前 utterance.speechString 的
            // 所以绝对位置是 currentTextOffset + characterRange.location
            self.currentPosition = self.currentTextOffset + characterRange.location
            self.spokenCharacters = self.currentPosition // 更新已读字符数
            self.updatePlaybackProgress() // 更新进度条
        }
    }
}
