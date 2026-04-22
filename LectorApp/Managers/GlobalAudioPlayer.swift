import Foundation
import AVFoundation
import MediaPlayer
import Combine

class GlobalAudioPlayer: NSObject, ObservableObject, AVAudioPlayerDelegate {
    static let shared = GlobalAudioPlayer()
    
    @Published var isPlaying = false
    @Published var currentLectureTitle: String?
    @Published var duration: TimeInterval = 0.0
    @Published var playingLecture: LectureDTO?
    @Published var isRecordingActive = false
    
    @Published var isMicActive = false
    @Published var isRecordingSessionActive = false
    
    private var audioPlayer: AVAudioPlayer?
    
    var currentTime: TimeInterval {
        return audioPlayer?.currentTime ?? 0
    }

    override private init() {
        super.init()
        setupRemoteTransportControls()
    }

    func play(lecture: LectureDTO) {
        guard !isMicActive else { return }
        
        stop()
        audioPlayer = nil
        
        guard let path = lecture.localAudioPath, !path.isEmpty else { return }
        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                .appendingPathComponent(path)
        
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
            
            audioPlayer = try AVAudioPlayer(contentsOf: url)
            audioPlayer?.delegate = self
            audioPlayer?.prepareToPlay()
            audioPlayer?.play()
            
            self.playingLecture = lecture
            self.currentLectureTitle = lecture.title
            self.duration = audioPlayer?.duration ?? 0
            self.isPlaying = true
            
            updateNowPlaying(title: lecture.title)
            
        } catch {
            print("--- [GLOBAL PLAYER ERROR] \(error) ---")
        }
    }

    func pause() {
        audioPlayer?.pause()
        isPlaying = false
        updateNowPlayingState()
    }

    func resume() {
        guard !isMicActive else { return }
        
        audioPlayer?.play()
        isPlaying = true
        updateNowPlayingState()
    }

    func stop() {
        audioPlayer?.stop()
        audioPlayer?.currentTime = 0
        isPlaying = false
        
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }
    
    func close() {
        stop()
        currentLectureTitle = nil
        playingLecture = nil
    }

    func seek(to percentage: Double) {
        guard let player = audioPlayer else { return }

        let newTime = max(0, min(percentage * player.duration, player.duration))
        player.currentTime = newTime
        
        updateNowPlayingState()
    }
    
    private func setupRemoteTransportControls() {
        let commandCenter = MPRemoteCommandCenter.shared()
        
        commandCenter.playCommand.addTarget { [unowned self] _ in
            self.resume(); return .success
        }
        commandCenter.pauseCommand.addTarget { [unowned self] _ in
            self.pause(); return .success
        }
        
        commandCenter.changePlaybackPositionCommand.addTarget { [unowned self] event in
            guard let positionEvent = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            self.audioPlayer?.currentTime = positionEvent.positionTime
            self.updateNowPlayingState()
            return .success
        }
    }

    private func updateNowPlaying(title: String) {
        var nowPlayingInfo = [String: Any]()
        nowPlayingInfo[MPMediaItemPropertyTitle] = title
        nowPlayingInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] = audioPlayer?.currentTime
        nowPlayingInfo[MPMediaItemPropertyPlaybackDuration] = audioPlayer?.duration
        nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate] = 1.0
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
    }

    private func updateNowPlayingState() {
        var nowPlayingInfo = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
        nowPlayingInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] = audioPlayer?.currentTime
        nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? 1.0 : 0.0
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
    }
    
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        DispatchQueue.main.async {
            self.stop()
        }
    }
}
