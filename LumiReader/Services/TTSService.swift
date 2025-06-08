import Foundation
import AVFoundation
import Combine

class TTSService: NSObject, ObservableObject {
    static let shared = TTSService()
    
    private let synthesizer = AVSpeechSynthesizer()
    
    @Published var isPlaying = false
    @Published var isPaused = false
    @Published var currentRate: Float = UserDefaults.standard.float(forKey: "ttsRate") > 0 ? UserDefaults.standard.float(forKey: "ttsRate") : 0.5
    
    @Published var totalCharacters: Int = 0
    @Published var spokenCharacters: Int = 0
    @Published var playbackProgress: Double = 0.0
    
    @Published var currentSpeakingSentenceIndex: Int?
    private var sentencesWithRanges: [(text: String, originalRange: NSRange)] = []

    private var currentText: String = ""
    private var currentPosition: Int = 0 // Represents the current character index in the full text
    private var currentTextOffset: Int = 0 // Represents the starting offset of the current utterance string within the full text
    
    private let voiceIdentifier = "com.apple.ttsbundle.Mei-Jia-compact"
    private var selectedVoice: AVSpeechSynthesisVoice?
    
    override init() {
        super.init()
        synthesizer.delegate = self
        loadVoice()
        setupAudioSession()
    }
    
    private func loadVoice() {
        if let voice = AVSpeechSynthesisVoice(identifier: voiceIdentifier) {
            selectedVoice = voice
        } else {
            selectedVoice = AVSpeechSynthesisVoice(language: "zh-CN")
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
        // Determine if this is a new playback session (different text or starting from scratch)
        let isStartingNewFromStopped = self.currentText != text || (!isPlaying && !isPaused && currentPosition == 0 && totalCharacters == 0)

        if isStartingNewFromStopped {
            // In case of a new start, ensure everything is stopped and reset
            stop() // This will also handle synthesizer.stopSpeaking() and reset published states
            
            self.currentText = text
            self.currentPosition = 0
            self.currentTextOffset = 0
            self.isPaused = false
            
            // Segment sentences for highlighting
            self.sentencesWithRanges = []
            (text as NSString).enumerateSubstrings(in: NSRange(location: 0, length: text.utf16.count), options: .bySentences) { (substring, substringRange, enclosingRange, stop) in
                if let sentence = substring, !sentence.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    self.sentencesWithRanges.append((text: sentence, originalRange: substringRange))
                }
            }
            
            // Reset progress and highlighting states (already done by stop(), but for clarity/initial setup)
            self.totalCharacters = text.utf16.count
            self.spokenCharacters = 0
            self.updatePlaybackProgress()
            self.currentSpeakingSentenceIndex = nil
            
            if text.isEmpty {
                print("[TTSService] Attempted to speak empty text.")
                DispatchQueue.main.async {
                    self.isPlaying = false
                    self.isPaused = false
                    self.totalCharacters = 0
                    self.spokenCharacters = 0
                    self.playbackProgress = 0.0
                }
                return
            }

            // Introduce a small delay to allow synthesizer to fully reset
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                self.startSpeakingInternal(from: self.currentText)
            }
        } else if isPaused {
            resume() // If already paused, resume
        } else if isPlaying {
            // Already playing the same text, no action.
            print("[TTSService] Already playing the same text, no action.")
        }
    }
    
    func pause() {
        if synthesizer.isSpeaking {
            synthesizer.pauseSpeaking(at: .word)
            print("[TTSService] Paused speaking.")
        }
    }
    
    func resume() {
        if isPaused {
            let nsCurrentText = currentText as NSString
            guard currentPosition < nsCurrentText.length else {
                // If we've reached the end, implicitly act as if it finished
                // Make sure to reset states as if finished
                stop() // Use stop() to reset all states cleanly
                return
            }
            let remainingText = nsCurrentText.substring(from: currentPosition)
            
            self.currentTextOffset = self.currentPosition
            
            // Resume with a small delay for smoother transition
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                self.startSpeakingInternal(from: remainingText)
            }
            print("[TTSService] Resumed speaking.")
        }
    }
    
    // MARK: - stop() method to cleanly stop and reset all states
    func stop() {
        // 1. Immediately stop speech on the synthesizer
        if synthesizer.isSpeaking || synthesizer.isPaused {
            synthesizer.stopSpeaking(at: .immediate)
            print("[TTSService] Synthesizer stopped immediately by stop() call.")
        }
        
        // 2. Immediately reset all @Published states on the main thread for UI update
        DispatchQueue.main.async {
            self.isPlaying = false
            self.isPaused = false
            self.spokenCharacters = 0
            self.currentPosition = 0 // Reset internal playback position
            self.currentTextOffset = 0 // Reset internal text offset
            self.playbackProgress = 0.0 // Reset progress bar
            self.currentSpeakingSentenceIndex = nil // Clear highlighting
            print("[TTSService] All UI-related states reset to stopped.")
        }
        // didCancel delegate method will also be called, but states are already reset here.
    }
    
    func togglePlayPause() {
        if isPlaying { // If currently playing, pause
            pause()
        } else if isPaused { // If currently paused, resume
            resume()
        } else {
            // This state (neither playing nor paused) implies stopped.
            // The UI should handle calling speak() from the beginning when this occurs.
            print("[TTSService] togglePlayPause called in stopped state. UI should initiate speak().")
        }
    }
    
    func updateRate(_ newRate: Float) {
        let clampedRate = max(AVSpeechUtteranceMinimumSpeechRate, min(AVSpeechUtteranceMaximumSpeechRate, newRate))
        currentRate = clampedRate
        UserDefaults.standard.set(currentRate, forKey: "ttsRate")
        
        if isPlaying || isPaused {
            synthesizer.stopSpeaking(at: .immediate) // Stop current utterance to apply new rate
            
            self.currentTextOffset = self.currentPosition // Ensure offset is correct for resume
            
            // Re-start speaking with the new rate after a short delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                let nsCurrentText = self.currentText as NSString
                guard self.currentPosition < nsCurrentText.length else {
                    // If we were at the end, just finish and reset states
                    self.stop() // Use stop() to reset all states cleanly
                    return
                }
                let textToContinueFrom = nsCurrentText.substring(from: self.currentPosition)
                
                if !textToContinueFrom.isEmpty {
                    self.startSpeakingInternal(from: textToContinueFrom)
                } else if self.currentPosition >= nsCurrentText.length {
                    self.stop() // Use stop() to reset all states cleanly
                }
            }
        }
    }
    
    // MARK: - Private Methods
    
    private func startSpeakingInternal(from text: String) {
        // This check ensures that a new utterance is only spoken if the synthesizer is idle.
        // It's less critical now that `speak()` calls `stop()` explicitly.
        if synthesizer.isSpeaking || synthesizer.isPaused {
            synthesizer.stopSpeaking(at: .immediate)
            print("[TTSService] startSpeakingInternal: Synthesizer stopping before new utterance (should be rare).")
        }

        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = currentRate
        utterance.voice = selectedVoice
        
        DispatchQueue.main.async {
            self.synthesizer.speak(utterance)
            print("[TTSService] startSpeakingInternal: New utterance queued.")
        }
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
            print("[TTSService] Delegate didStart speaking.")
        }
    }
    
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        DispatchQueue.main.async {
            // Only reset if the entire text has finished
            if self.spokenCharacters >= self.totalCharacters {
                self.stop() // Use stop() to ensure all states are reset to "stopped"
                print("[TTSService] Delegate didFinish speaking (full text). All states reset by stop().")
            } else {
                print("[TTSService] Delegate didFinish speaking (partial utterance, or already stopped).")
            }
        }
    }
    
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didPause utterance: AVSpeechUtterance) {
        DispatchQueue.main.async {
            self.isPlaying = false
            self.isPaused = true
            print("[TTSService] Delegate didPause speaking.")
        }
    }
    
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didContinue utterance: AVSpeechUtterance) {
        DispatchQueue.main.async {
            self.isPlaying = true
            self.isPaused = false
            print("[TTSService] Delegate didContinue speaking.")
        }
    }
    
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        // This delegate method is also triggered when `stop()` is called.
        // Calling stop() here ensures all states are reset, regardless of how cancellation occurred.
        stop() // Use stop() to ensure all states are reset
        print("[TTSService] Delegate didCancel speaking. States reset by stop().")
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
