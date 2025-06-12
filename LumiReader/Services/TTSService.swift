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
            print("[TTSService - didSet] Speech rate updated and saved: \(self.currentRate)")
        }
    }
    
    @Published var totalCharacters: Int = 0
    @Published var spokenCharacters: Int = 0
    @Published var playbackProgress: Double = 0.0
    
    @Published var currentSpeakingSentenceIndex: Int?
    private var sentencesWithRanges: [(text: String, originalRange: NSRange)] = []

    // currentText 仍然用于追踪当前内容，但它的生命周期由 speak 方法主导
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
            print("[TTSService - init] Loaded saved rate: \(self.currentRate)")
        } else {
            self.currentRate = AVSpeechUtteranceDefaultSpeechRate
            print("[TTSService - init] No valid rate saved, using default: \(self.currentRate)")
        }

        synthesizer.delegate = self
        print("[TTSService - init] Synthesizer delegate set.")
        setupAudioSession()
        print("[TTSService - init] Audio session setup initiated.")
        loadVoice()
        print("[TTSService - init] Voice loading initiated.")
        
        if selectedVoice == nil {
            print("[TTSService - init] 警告：初始化结束时没有可用语音！")
        } else {
            print("[TTSService - init] TTSService 初始化完成，语音: \(selectedVoice?.identifier ?? "N/A").")
        }
    }
    
    private func loadVoice() {
        if let voice = AVSpeechSynthesisVoice(identifier: voiceIdentifier) {
            selectedVoice = voice
            print("[TTSService - loadVoice] 成功加载指定语音: \(voice.identifier)")
        } else {
            selectedVoice = AVSpeechSynthesisVoice(language: "zh-CN")
            print("[TTSService - loadVoice] 指定语音 '\(voiceIdentifier)' 未找到。尝试加载通用中文语音。")
        }
    }

    private func setupAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [])
            try AVAudioSession.sharedInstance().setActive(true)
            print("[TTSService - setupAudioSession] Audio session 设置成功.")
        } catch {
            print("[TTSService - setupAudioSession] 错误：设置音频会话失败: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Public Methods
    
    func speak(_ text: String) {
        print("[TTSService - speak] 调用 speak 方法，传入文本长度: \(text.count), 文本预览: \"\(text.prefix(50))...\"")
        
        // **1. 首先处理空文本情况，并清空所有状态**
        if text.isEmpty {
            print("[TTSService - speak] 警告：尝试朗读空文本。")
            // 停止硬件，并清空所有相关的 Published 状态和内部内容状态
            softStop() // 新增的软停止方法，仅重置播放状态
            self.currentText = ""
            self.sentencesWithRanges = []
            self.totalCharacters = 0
            self.spokenCharacters = 0
            self.playbackProgress = 0.0
            self.currentSpeakingSentenceIndex = nil
            return
        }

        // **2. 判断是否是新的朗读会话或需要从头开始**
        // 如果传入的文本与当前文本不同，或者当前状态是停止的
        let isNewContent = self.currentText != text
        let isCurrentlyStopped = (!isPlaying && !isPaused)
        
        if isNewContent || isCurrentlyStopped {
            print("[TTSService - speak] 检测到新内容或处于停止状态，准备开始新朗读。")

            // 停止任何正在进行的朗读（同步）
            if synthesizer.isSpeaking || synthesizer.isPaused {
                synthesizer.stopSpeaking(at: .immediate)
                print("[TTSService - speak] 停止之前的朗读以开始新的。")
            }
            
            // **同步设置内容相关的状态**
            self.currentText = text
            self.sentencesWithRanges = []
            (self.currentText as NSString).enumerateSubstrings(in: NSRange(location: 0, length: self.currentText.utf16.count), options: .bySentences) { (substring, substringRange, enclosingRange, stop) in
                if let sentence = substring, !sentence.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    self.sentencesWithRanges.append((text: sentence, originalRange: substringRange))
                }
            }
            self.totalCharacters = self.currentText.utf16.count
            
            // **异步重置播放相关的状态 (为了 UI 更新)**
            DispatchQueue.main.async {
                self.isPlaying = false
                self.isPaused = false
                self.spokenCharacters = 0
                self.currentPosition = 0
                self.currentTextOffset = 0
                self.playbackProgress = 0.0
                self.currentSpeakingSentenceIndex = nil
                print("[TTSService - speak] 播放状态已重置为停止。")
            }

            // **异步调度实际的朗读开始（给系统一个短暂的重置时间）**
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                print("[TTSService - speak] 延迟后调用 startSpeakingInternal。传入文本长度: \(self.currentText.count)")
                self.startSpeakingInternal(from: self.currentText)
            }
        } else if isPaused {
            // **3. 如果是相同文本且已暂停，则恢复**
            print("[TTSService - speak] 当前已暂停且文本相同，调用 resume。")
            resume()
        } else if isPlaying {
            // **4. 如果是相同文本且正在播放，则不采取任何操作**
            print("[TTSService - speak] 正在播放相同文本，不采取任何操作。")
        }
        else {
            // 这通常不应该发生，但作为安全网，可以记录或重置
            print("[TTSService - speak] 警告：未处理的 speak 调用场景。当前 isPlaying:\(isPlaying), isPaused:\(isPaused), currentText == text: \(self.currentText == text)")
        }
    }
    
    func pause() {
        print("[TTSService - pause] 调用 pause。")
        if synthesizer.isSpeaking {
            synthesizer.pauseSpeaking(at: .word) // 暂停到当前词语的末尾
            print("[TTSService - pause] 合成器已发出暂停指令。")
        } else {
            print("[TTSService - pause] 合成器未在说话，无需暂停。")
        }
        DispatchQueue.main.async {
            self.isPlaying = false
            self.isPaused = true
        }
    }
    
    func resume() {
        print("[TTSService - resume] 调用 resume。")
        if synthesizer.isPaused { // 检查合成器是否真的处于暂停状态
            synthesizer.continueSpeaking()
            print("[TTSService - resume] 合成器已发出恢复指令。")
        } else {
            print("[TTSService - resume] 合成器未处于暂停状态，无需恢复。")
            // 如果不是暂停状态，但 UI 错误地调用了 resume，为了避免混乱，我们清空播放状态
            softStop() // 仅重置播放状态
        }
        DispatchQueue.main.async {
            self.isPlaying = true
            self.isPaused = false
        }
    }
    
    /// 硬停止：停止硬件，并重置所有播放相关状态。不负责清空 content text。
    func stop() {
        print("[TTSService - stop] 调用 stop（硬停止）。")
        if synthesizer.isSpeaking || synthesizer.isPaused {
            synthesizer.stopSpeaking(at: .immediate)
            print("[TTSService - stop] 合成器已立即停止。")
        } else {
            print("[TTSService - stop] 合成器已停止或未初始化。")
        }
        
        // 其他 @Published 状态需要在主线程更新，因为它们会影响 UI
        DispatchQueue.main.async {
            self.isPlaying = false
            self.isPaused = false
            self.spokenCharacters = 0
            self.currentPosition = 0
            self.currentTextOffset = 0
            self.playbackProgress = 0.0
            self.currentSpeakingSentenceIndex = nil
            print("[TTSService - stop] 所有播放状态已重置。isPlaying:\(self.isPlaying), isPaused:\(self.isPaused)")
        }
    }

    /// 软停止：仅重置所有播放相关状态，不停止硬件（因为可能是自然停止）。
    // 主要用于 didFinish 或 resume 失败等场景，避免不必要的硬件停止调用。
    private func softStop() {
        print("[TTSService - softStop] 调用 softStop（软停止）。")
        DispatchQueue.main.async {
            self.isPlaying = false
            self.isPaused = false
            self.spokenCharacters = 0
            self.currentPosition = 0
            self.currentTextOffset = 0
            self.playbackProgress = 0.0
            self.currentSpeakingSentenceIndex = nil
            print("[TTSService - softStop] 所有播放状态已重置（软停止）。isPlaying:\(self.isPlaying), isPaused:\(self.isPaused)")
        }
    }
    
    func togglePlayPause() {
        print("[TTSService - togglePlayPause] 调用 togglePlayPause。当前 isPlaying: \(isPlaying), isPaused: \(isPaused)")
        if isPlaying {
            pause()
        } else if isPaused {
            resume()
        } else {
            // 如果处于停止状态，这个方法不应该直接触发播放，因为它只负责切换状态。
            // 应该由 UI 在这种情况下调用 `speak(processedMarkdown)`。
            print("[TTSService - togglePlayPause] 处于停止状态，UI 应调用 speak() 从头开始。")
        }
    }
    
    func updateRate(_ newRate: Float) {
        print("[TTSService - updateRate] 尝试更新语速到: \(newRate)")
        let clampedRate = max(AVSpeechUtteranceMinimumSpeechRate, min(AVSpeechUtteranceMaximumSpeechRate, newRate))
        
        if currentRate != clampedRate {
            print("[TTSService - updateRate] 语速实际改变为: \(clampedRate)")
            currentRate = clampedRate 
            
            if synthesizer.isSpeaking || synthesizer.isPaused {
                print("[TTSService - updateRate] 正在播放/暂停，需要停止并重新开始。")
                synthesizer.stopSpeaking(at: .immediate)
                
                self.currentTextOffset = self.currentPosition // 确保偏移量正确以恢复
                
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    print("[TTSService - updateRate] 延迟后调用 startSpeakingInternal 重新开始。")
                    let nsCurrentText = self.currentText as NSString
                    guard self.currentPosition < nsCurrentText.length else {
                        self.stop()
                        return
                    }
                    let textToContinueFrom = nsCurrentText.substring(from: self.currentPosition)
                    
                    if !textToContinueFrom.isEmpty {
                        self.startSpeakingInternal(from: textToContinueFrom)
                        print("[TTSService - updateRate] 语速已更新并从当前位置重新开始朗读。")
                    } else if self.currentPosition >= nsCurrentText.length {
                        self.stop()
                    }
                }
            }
        } else {
            print("[TTSService - updateRate] 语速未改变。")
        }
    }
    
    // MARK: - Private Methods
    
    private func startSpeakingInternal(from text: String) {
        guard !text.isEmpty else {
            print("[TTSService - startSpeakingInternal] 错误：接收到的文本片段为空，无法朗读。")
            DispatchQueue.main.async { self.softStop() } // 软停止
            return
        }
        
        guard let voice = selectedVoice else {
            print("[TTSService - startSpeakingInternal] 错误：没有选定语音，无法朗读。")
            DispatchQueue.main.async { self.softStop() } // 软停止
            return
        }
        
        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = currentRate
        utterance.voice = voice
        
        print("[TTSService - startSpeakingInternal] 准备朗读新的 Utterance。文本长度: \(text.count), 语速: \(utterance.rate), 语音: \(utterance.voice?.identifier ?? "N/A")")
        self.synthesizer.speak(utterance)
        print("[TTSService - startSpeakingInternal] 新的 Utterance 已排队。")
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
            print("[TTSService - Delegate] didStart speaking. Utterance text length: \(utterance.speechString.count). isPlaying: \(self.isPlaying), isPaused: \(self.isPaused)")
        }
    }
    
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        DispatchQueue.main.async {
            // 只有当 isPlaying 为 true 时才真正更新进度和停止，避免在被取消时重复操作
            if self.isPlaying { // 仅当是正常播放结束时才更新进度和停止
                self.spokenCharacters = self.totalCharacters
                self.playbackProgress = 1.0
                print("[TTSService - Delegate] didFinish speaking (full text completed). Progress: \(self.playbackProgress)")
                self.stop() // 这里调用硬停止，因为播放完成了
            } else {
                print("[TTSService - Delegate] didFinish speaking, but not in playing state (possibly cancelled).")
            }
        }
    }
    
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didPause utterance: AVSpeechUtterance) {
        DispatchQueue.main.async {
            self.isPlaying = false
            self.isPaused = true
            print("[TTSService - Delegate] didPause speaking. isPlaying: \(self.isPlaying), isPaused: \(self.isPaused)")
        }
    }
    
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didContinue utterance: AVSpeechUtterance) {
        DispatchQueue.main.async {
            self.isPlaying = true
            self.isPaused = false
            print("[TTSService - Delegate] didContinue speaking. isPlaying: \(self.isPlaying), isPaused: \(self.isPaused)")
        }
    }
    
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        DispatchQueue.main.async {
            self.stop() // 当取消时，执行硬停止并重置所有状态
            print("[TTSService - Delegate] didCancel speaking. States reset by stop().")
        }
    }
    
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, willSpeakRangeOfSpeechString characterRange: NSRange, utterance: AVSpeechUtterance) {
        DispatchQueue.main.async {
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
            }
        }
    }
}
