import Flutter
import UIKit
import AVFoundation

@main
@objc class AppDelegate: FlutterAppDelegate {
  
  var backgroundTask: UIBackgroundTaskIdentifier = .invalid
  var audioEngine: AVAudioEngine?
  var silencePlayer: AVAudioPlayerNode?
  var methodChannel: FlutterMethodChannel?
  
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    
    // Setup method channel for Flutter communication
    if let controller = window?.rootViewController as? FlutterViewController {
      methodChannel = FlutterMethodChannel(
        name: "com.roadmate/audio",
        binaryMessenger: controller.binaryMessenger
      )
      
      methodChannel?.setMethodCallHandler { [weak self] (call, result) in
        switch call.method {
        case "startBackgroundAudio":
          self?.startBackgroundAudio()
          result(true)
        case "stopBackgroundAudio":
          self?.stopBackgroundAudio()
          result(true)
        default:
          result(FlutterMethodNotImplemented)
        }
      }
    }
    
    // Configure audio session for background playback and recording
    configureAudioSession()
    
    // Keep audio session active when app goes to background
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(handleInterruption),
      name: AVAudioSession.interruptionNotification,
      object: nil
    )
    
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
  
  private func configureAudioSession() {
    do {
      let audioSession = AVAudioSession.sharedInstance()
      try audioSession.setCategory(
        .playAndRecord,
        mode: .voiceChat,
        options: [.defaultToSpeaker, .allowBluetooth, .allowBluetoothA2DP, .mixWithOthers]
      )
      try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
      print("Audio session configured successfully")
    } catch {
      print("Failed to configure audio session: \(error)")
    }
  }
  
  /// Start playing silence to keep audio session alive in background
  private func startBackgroundAudio() {
    print("Starting background audio to keep session alive...")
    
    // Stop existing engine if any
    stopBackgroundAudio()
    
    do {
      audioEngine = AVAudioEngine()
      silencePlayer = AVAudioPlayerNode()
      
      guard let engine = audioEngine, let player = silencePlayer else { return }
      
      engine.attach(player)
      
      // Create a silent buffer
      let sampleRate: Double = 44100
      let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
      let frameCount = AVAudioFrameCount(sampleRate) // 1 second of silence
      
      guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
        print("Failed to create audio buffer")
        return
      }
      
      buffer.frameLength = frameCount
      // Buffer is already zeroed (silence)
      
      // Connect player to main mixer
      engine.connect(player, to: engine.mainMixerNode, format: format)
      
      // Set volume very low (effectively silent but keeps session alive)
      player.volume = 0.01
      
      try engine.start()
      
      // Schedule buffer to loop
      player.scheduleBuffer(buffer, at: nil, options: .loops)
      player.play()
      
      print("Background audio started successfully")
    } catch {
      print("Failed to start background audio: \(error)")
    }
  }
  
  private func stopBackgroundAudio() {
    silencePlayer?.stop()
    audioEngine?.stop()
    silencePlayer = nil
    audioEngine = nil
    print("Background audio stopped")
  }
  
  @objc private func handleInterruption(notification: Notification) {
    guard let userInfo = notification.userInfo,
          let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
          let type = AVAudioSession.InterruptionType(rawValue: typeValue) else {
      return
    }
    
    switch type {
    case .began:
      print("Audio session interrupted")
    case .ended:
      print("Audio session interruption ended, reactivating...")
      configureAudioSession()
      // Restart background audio if it was playing
      if audioEngine != nil {
        startBackgroundAudio()
      }
    @unknown default:
      break
    }
  }
  
  override func applicationDidBecomeActive(_ application: UIApplication) {
    super.applicationDidBecomeActive(application)
    configureAudioSession()
    endBackgroundTask()
  }
  
  override func applicationWillEnterForeground(_ application: UIApplication) {
    super.applicationWillEnterForeground(application)
    configureAudioSession()
  }
  
  override func applicationDidEnterBackground(_ application: UIApplication) {
    super.applicationDidEnterBackground(application)
    
    // Start a background task to keep the app alive for audio
    startBackgroundTask()
    
    // Ensure audio session is active in background
    configureAudioSession()
  }
  
  private func startBackgroundTask() {
    backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "VoiceAssistantTask") {
      // Called when time expires
      self.endBackgroundTask()
    }
    print("Background task started: \(backgroundTask)")
  }
  
  private func endBackgroundTask() {
    if backgroundTask != .invalid {
      print("Background task ended: \(backgroundTask)")
      UIApplication.shared.endBackgroundTask(backgroundTask)
      backgroundTask = .invalid
    }
  }
}
