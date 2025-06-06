import Foundation
import AVFoundation

class TTSService: NSObject, ObservableObject {
    static let shared = TTSService()
    
    private let synthesizer = AVSpeechSynthesizer()
    
    @Published var isPlaying = false
    @Published var isPaused = false
    @Published var currentRate: Float = UserDefaults.standard.float(forKey: "ttsRate") > 0 ? UserDefaults.standard.float(forKey: "ttsRate") : 0.5
    
    // 【修改】currentText 现在存储完整的原始文本
    private var currentText: String = ""
    // 【修改】currentPosition 始终代表在完整文本中的位置
    private var currentPosition: Int = 0
    // 【新增】用于在播放剩余文本时，记录剩余文本在完整文本中的起始偏移量
    private var currentTextOffset: Int = 0
    
    // 使用固定的台湾话语音
    private let voiceIdentifier = "com.apple.ttsbundle.Mei-Jia-compact"
    private var selectedVoice: AVSpeechSynthesisVoice?
    
    override init() {
        super.init()
        synthesizer.delegate = self
        loadVoice()
    }
    
    private func loadVoice() {
        if let voice = AVSpeechSynthesisVoice(identifier: voiceIdentifier) {
            selectedVoice = voice
        } else {
            selectedVoice = AVSpeechSynthesisVoice(language: "zh-CN")
        }
    }
    
    // MARK: - Public Methods
    
    func speak(_ text: String) {
        // 【修改】重置状态时，也要重置偏移量
        synthesizer.stopSpeaking(at: .immediate)
        currentText = text
        currentPosition = 0
        currentTextOffset = 0 // 播放全新文本，偏移量为0
        isPaused = false
        
        startSpeaking(from: currentText)
    }
    
    func pause() {
        if synthesizer.isSpeaking {
            synthesizer.pauseSpeaking(at: .word)
            // isPlaying 和 isPaused 会在代理方法中更新
        }
    }
    
    func resume() {
        if isPaused {
            // 【关键改动】
            // 1. 从当前位置获取剩余文本
            guard currentPosition < currentText.count else {
                // 如果已经到末尾，就停止
                stop()
                return
            }
            let startIndex = currentText.index(currentText.startIndex, offsetBy: currentPosition)
            let remainingText = String(currentText[startIndex...])
            
            // 2. 更新偏移量
            self.currentTextOffset = self.currentPosition
            
            // 3. 开始播放剩余的文本
            //    startSpeaking 方法内部会处理 stop 和 speak 的调用，确保状态正确
            startSpeaking(from: remainingText)
        }
    }
    
    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
        // 状态重置现在主要由代理方法 didFinish/didCancel 处理，确保一致性
    }
    
    func togglePlayPause() {
        if isPlaying {
            pause()
        } else if isPaused {
            resume()
        } else {
            if !currentText.isEmpty {
                // 从头开始播放
                speak(currentText)
            }
        }
    }
    
    func updateRate(_ newRate: Float) {
        currentRate = newRate
        UserDefaults.standard.set(currentRate, forKey: "ttsRate")
        
        // 【新增】如果正在播放，调整语速后立即生效
        if isPlaying {
            // 暂停再立即用新语速恢复，会重新创建 utterance
            pause()
            resume()
        }
    }
    
    // MARK: - Private Methods
    
    // 【修改】此方法现在接受要播放的文本
    private func startSpeaking(from text: String) {
        // 【关键改动】在播放新 utterance 之前，先强制停止当前的，以清除暂停等状态
        synthesizer.stopSpeaking(at: .immediate)
        
        // 如果传入的文本为空，则直接停止
        if text.isEmpty {
            self.stop()
            return
        }

        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = currentRate
        utterance.voice = selectedVoice
        
        synthesizer.speak(utterance)
        
        // isPlaying 和 isPaused 由代理方法设置，以保证状态准确
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
            self.isPlaying = false
            self.isPaused = false
            self.currentPosition = 0
            self.currentTextOffset = 0
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
            self.currentPosition = 0
            self.currentTextOffset = 0
        }
    }
    
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, willSpeakRangeOfSpeechString characterRange: NSRange, utterance: AVSpeechUtterance) {
        // 【关键改动】正确更新在完整文本中的位置
        DispatchQueue.main.async {
            // 当前的绝对位置 = 偏移量 + 在当前 utterance 中的相对位置
            self.currentPosition = self.currentTextOffset + characterRange.location
        }
    }
}