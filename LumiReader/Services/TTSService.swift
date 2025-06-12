import Foundation
import AVFoundation
import Combine
import SwiftUI

class TTSService: NSObject, ObservableObject {
    static let shared = TTSService()
    
    private let synthesizer = AVSpeechSynthesizer()
    
    @Published var isPlaying = false
    @Published var isPaused = false
    
    @Published var currentRate: Float {
        didSet {
            let clampedRate = max(AVSpeechUtteranceMinimumSpeechRate, min(AVSpeechUtteranceMaximumSpeechRate, currentRate))
            if currentRate != clampedRate {
                currentRate = clampedRate
            }
            UserDefaults.standard.set(self.currentRate, forKey: "ttsSpeechRate")
            // print("[TTSService - didSet] Speech rate updated and saved: \(self.currentRate)")
        }
    }
    
    @Published var totalCharacters: Int = 0
    @Published var spokenCharacters: Int = 0
    @Published var playbackProgress: Double = 0.0
    
    @Published var currentSpeakingSentenceIndex: Int? // 用于高亮显示
    // MARK: - sentencesWithRanges 现在将根据 enableHighlighting 参数来填充
    private var sentencesWithRanges: [(text: String, originalRange: NSRange)] = []

    private var currentText: String = "" 
    private var currentPosition: Int = 0
    private var currentTextOffset: Int = 0
    
    private let voiceIdentifier = "com.apple.ttsbundle.Mei-Jia-compact"
    private var selectedVoice: AVSpeechSynthesisVoice?
    
    override init() {
        _currentRate = Published(initialValue: AVSpeechUtteranceDefaultSpeechRate)
        super.init()
        
        let savedRate = UserDefaults.standard.float(forKey: "ttsSpeechRate")
        if savedRate > 0 {
            self.currentRate = savedRate
        } else {
            self.currentRate = AVSpeechUtteranceDefaultSpeechRate
        }

        synthesizer.delegate = self
        setupAudioSession()
        loadVoice()
    }
    
    private func loadVoice() {
        if let voice = AVSpeechSynthesisVoice(identifier: voiceIdentifier) {
            selectedVoice = voice
        } else {
            selectedVoice = AVSpeechSynthesisVoice(language: "zh-CN")
        }
    }

    private func setupAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [])
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
        }
    }
    
    // MARK: - Public Methods
    
    // MARK: - 修改：speak 方法新增 enableHighlighting 参数
    func speak(_ text: String, enableHighlighting: Bool = false) { // 默认为 false
        // print("[TTSService - speak] 调用 speak 方法，传入文本长度: \(text.count), enableHighlighting: \(enableHighlighting)")
        
        if text.isEmpty {
            // print("[TTSService - speak] 警告：尝试朗读空文本。")
            softStop() 
            self.currentText = ""
            self.sentencesWithRanges = [] // 清空以确保无高亮
            self.totalCharacters = 0
            self.spokenCharacters = 0
            self.playbackProgress = 0.0
            self.currentSpeakingSentenceIndex = nil
            return
        }

        let isNewContent = self.currentText != text
        let isCurrentlyStopped = (!isPlaying && !isPaused)
        
        if isNewContent || isCurrentlyStopped {
            // print("[TTSService - speak] 检测到新内容或处于停止状态，准备开始新朗读。")

            if synthesizer.isSpeaking || synthesizer.isPaused {
                synthesizer.stopSpeaking(at: .immediate)
                // print("[TTSService - speak] 停止之前的朗读以开始新的。")
            }
            
            self.currentText = text
            self.sentencesWithRanges = [] // 每次开始新朗读时，先清空句子数据

            // MARK: - 仅当 enableHighlighting 为 true 时才进行句子分割
            if enableHighlighting {
                (self.currentText as NSString).enumerateSubstrings(in: NSRange(location: 0, length: self.currentText.utf16.count), options: .bySentences) { (substring, substringRange, enclosingRange, stop) in
                    if let sentence = substring, !sentence.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        self.sentencesWithRanges.append((text: sentence, originalRange: substringRange))
                    }
                }
            } else {
                // 如果不启用高亮，确保 currentSpeakingSentenceIndex 在开始时是 nil
                self.currentSpeakingSentenceIndex = nil
            }

            self.totalCharacters = self.currentText.utf16.count
            self.spokenCharacters = 0
            self.currentPosition = 0
            self.currentTextOffset = 0
            self.playbackProgress = 0.0
            
            // 异步重置播放相关的状态 (为了 UI 更新)
            DispatchQueue.main.async {
                self.isPlaying = false
                self.isPaused = false
                // currentSpeakingSentenceIndex 会在 speak 内部条件性设置
                // print("[TTSService - speak] 播放状态已重置为停止。")
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                // print("[TTSService - speak] 延迟后调用 startSpeakingInternal。传入文本长度: \(self.currentText.count)")
                self.startSpeakingInternal(from: self.currentText)
            }
        } else if isPaused {
            // print("[TTSService - speak] 当前已暂停且文本相同，调用 resume。")
            resume()
        } else if isPlaying {
            // print("[TTSService - speak] 正在播放相同文本，不采取任何操作。")
        }
        else {
            // print("[TTSService - speak] 警告：未处理的 speak 调用场景。当前 isPlaying:\(isPlaying), isPaused:\(isPaused), currentText == text: \(self.currentText == text)")
        }
    }
    
    func pause() {
        // print("[TTSService - pause] 调用 pause。")
        if synthesizer.isSpeaking {
            synthesizer.pauseSpeaking(at: .word) 
            // print("[TTSService - pause] 合成器已发出暂停指令。")
        } else {
            // print("[TTSService - pause] 合成器未在说话，无需暂停。")
        }
        DispatchQueue.main.async {
            self.isPlaying = false
            self.isPaused = true
        }
    }
    
    func resume() {
        // print("[TTSService - resume] 调用 resume。")
        if synthesizer.isPaused { 
            synthesizer.continueSpeaking()
            // print("[TTSService - resume] 合成器已发出恢复指令。")
        } else {
            // print("[TTSService - resume] 合成器未处于暂停状态，无需恢复。")
            softStop() 
        }
        DispatchQueue.main.async {
            self.isPlaying = true
            self.isPaused = false
        }
    }
    
    func stop() {
        // print("[TTSService - stop] 调用 stop（硬停止）。")
        if synthesizer.isSpeaking || synthesizer.isPaused {
            synthesizer.stopSpeaking(at: .immediate)
            // print("[TTSService - stop] 合成器已立即停止。")
        } else {
            // print("[TTSService - stop] 合成器已停止或未初始化。")
        }
        
        self.currentText = "" 
        self.sentencesWithRanges = [] // 硬停止时清空句子数据
        
        DispatchQueue.main.async {
            self.isPlaying = false
            self.isPaused = false
            self.spokenCharacters = 0
            self.currentPosition = 0
            self.currentTextOffset = 0
            self.playbackProgress = 0.0
            self.currentSpeakingSentenceIndex = nil // 停止时清空高亮索引
            // print("[TTSService - stop] 所有播放状态已重置。isPlaying:\(self.isPlaying), isPaused:\(self.isPaused)")
        }
    }

    private func softStop() {
        // print("[TTSService - softStop] 调用 softStop（软停止）。")
        // sentencesWithRanges 不在这里清空，因为它可能被 `speak` 方法重新用于下一个朗读
        DispatchQueue.main.async {
            self.isPlaying = false
            self.isPaused = false
            self.spokenCharacters = 0
            self.currentPosition = 0
            self.currentTextOffset = 0
            self.playbackProgress = 0.0
            self.currentSpeakingSentenceIndex = nil // 软停止时清空高亮索引
            // print("[TTSService - softStop] 所有播放状态已重置（软停止）。isPlaying:\(self.isPlaying), isPaused:\(self.isPaused)")
        }
    }
    
    func togglePlayPause() {
        // print("[TTSService - togglePlayPause] 调用 togglePlayPause。当前 isPlaying: \(isPlaying), isPaused: \(isPaused)")
        if isPlaying {
            pause()
        } else if isPaused {
            resume()
        } else {
            // print("[TTSService - togglePlayPause] 处于停止状态，UI 应调用 speak() 从头开始。")
        }
    }
    
    func updateRate(_ newRate: Float) {
        // print("[TTSService - updateRate] 尝试更新语速到: \(newRate)")
        let clampedRate = max(AVSpeechUtteranceMinimumSpeechRate, min(AVSpeechUtteranceMaximumSpeechRate, newRate))
        
        if currentRate != clampedRate {
            // print("[TTSService - updateRate] 语速实际改变为: \(clampedRate)")
            currentRate = clampedRate 
            
            if synthesizer.isSpeaking || synthesizer.isPaused {
                // print("[TTSService - updateRate] 正在播放/暂停，需要停止并重新开始。")
                synthesizer.stopSpeaking(at: .immediate)
                
                self.currentTextOffset = self.currentPosition 
                
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    // print("[TTSService - updateRate] 延迟后调用 startSpeakingInternal 重新开始。")
                    let nsCurrentText = self.currentText as NSString
                    guard self.currentPosition < nsCurrentText.length else {
                        self.stop()
                        return
                    }
                    let textToContinueFrom = nsCurrentText.substring(from: self.currentPosition)
                    
                    if !textToContinueFrom.isEmpty {
                        self.startSpeakingInternal(from: textToContinueFrom)
                        // print("[TTSService - updateRate] 语速已更新并从当前位置重新开始朗读。")
                    } else if self.currentPosition >= nsCurrentText.length {
                        self.stop()
                    }
                }
            }
        } else {
            // print("[TTSService - updateRate] 语速未改变。")
        }
    }
    
    // MARK: - Private Methods
    
    private func startSpeakingInternal(from text: String) {
        guard !text.isEmpty else {
            // print("[TTSService - startSpeakingInternal] 错误：接收到的文本片段为空，无法朗读。") 
            DispatchQueue.main.async { self.softStop() } 
            return
        }
        
        guard let voice = selectedVoice else {
            // print("[TTSService - startSpeakingInternal] 错误：没有选定语音，无法朗读。") 
            DispatchQueue.main.async { self.softStop() } 
            return
        }
        
        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = currentRate
        utterance.voice = voice
        
        // print("[TTSService - startSpeakingInternal] 准备朗读新的 Utterance。文本长度: \(text.count), 语速: \(utterance.rate), 语音: \(utterance.voice?.identifier ?? "N/A")")
        self.synthesizer.speak(utterance)
        // print("[TTSService - startSpeakingInternal] 新的 Utterance 已排队。")
    }
    
    private func updatePlaybackProgress() {
        guard totalCharacters > 0 else {
            playbackProgress = 0.0
            return
        }
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
            // print("[TTSService - Delegate] didStart speaking. Utterance text length: \(utterance.speechString.count). isPlaying: \(self.isPlaying), isPaused: \(self.isPaused)")
        }
    }
    
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        DispatchQueue.main.async {
            if self.isPlaying { 
                self.spokenCharacters = self.totalCharacters
                self.playbackProgress = 1.0
                // print("[TTSService - Delegate] didFinish speaking (full text completed). Progress: \(self.playbackProgress)")
                self.stop() 
            } else {
                // print("[TTSService - Delegate] didFinish speaking, but not in playing state (possibly cancelled).")
            }
        }
    }
    
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didPause utterance: AVSpeechUtterance) {
        DispatchQueue.main.async {
            self.isPlaying = false
            self.isPaused = true
            // print("[TTSService - Delegate] didPause speaking. isPlaying: \(self.isPlaying), isPaused: \(self.isPaused)")
        }
    }
    
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didContinue utterance: AVSpeechUtterance) {
        DispatchQueue.main.async {
            self.isPlaying = true
            self.isPaused = false
            // print("[TTSService - Delegate] didContinue speaking. isPlaying: \(self.isPlaying), isPaused: \(self.isPaused)")
        }
    }
    
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        DispatchQueue.main.async {
            self.stop() 
            // print("[TTSService - Delegate] didCancel speaking. States reset by stop().")
        }
    }
    
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, willSpeakRangeOfSpeechString characterRange: NSRange, utterance: AVSpeechUtterance) {
        DispatchQueue.main.async {
            // MARK: - 仅当 sentencesWithRanges 被填充时才尝试更新高亮索引
            guard !self.sentencesWithRanges.isEmpty else {
                self.currentSpeakingSentenceIndex = nil // 确保在不启用高亮时为 nil
                return
            }

            let absoluteLocationInFullText = self.currentTextOffset + characterRange.location
            let absoluteRangeInFullText = NSRange(location: absoluteLocationInFullText, length: characterRange.length)

            self.currentPosition = absoluteLocationInFullText
            self.spokenCharacters = self.currentPosition
            self.updatePlaybackProgress()
            
            var matchedIndex: Int?
            for (index, sentenceData) in self.sentencesWithRanges.enumerated() {
                let intersection = NSIntersectionRange(absoluteRangeInFullText, sentenceData.originalRange)
                if intersection.length > 0 {
                    matchedIndex = index
                    break
                }
            }
            
            if self.currentSpeakingSentenceIndex != matchedIndex {
                self.currentSpeakingSentenceIndex = matchedIndex
                // print("[TTSService - Delegate] willSpeakRangeOfSpeechString. Current sentence index: \(matchedIndex ?? -1)") 
            }
        }
    }
}