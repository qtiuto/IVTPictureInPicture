//
//  ContentView.swift
//  PipTest
//
//  Created by Osl on 2021/7/19.
//

import SwiftUI
import AVFoundation
import IVTPictureInPicture
import AVKit

var sVideoUrls = [Bundle.main.url(forResource: "trailer", withExtension: "mp4"), Bundle.main.url(forResource: "next", withExtension: "mp4"), Bundle.main.url(forResource: "three", withExtension: "mp4")]

class AVPlayerView :UIView {
    override class var layerClass: AnyClass {
        return AVPlayerLayer.self
    }
    
    func playerLayer() -> AVPlayerLayer {
        return layer as! AVPlayerLayer;
    }
}

struct PlayerViewContainer:UIViewRepresentable {
    typealias UIViewType = UIView
    @Binding fileprivate var playerView:UIView?
    
    func makeUIView(context: Context) -> UIView {
        UIView()
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {
        if playerView == nil {
           return
        }
        if !uiView.subviews.contains(playerView!) && playerView!.superview == nil {
            for view in uiView.subviews {
                view.removeFromSuperview()
            }
            playerView?.frame = uiView.bounds;
            uiView.addSubview(playerView!)
        }
    }
    
    
}

class PicDelegate : NSObject, IVTPictureInPictureControllerDelegate {
    var contentView: ContentView?
    
    func currentPlaybackTimeOfPicture(_ controller: IVTPictureInPictureController) -> TimeInterval {
        return contentView?.currentTime() ?? 0
    }
    
    func picture(_ controller: IVTPictureInPictureController, seekToTime: TimeInterval, completion: (() -> Void)? = nil) {
        contentView?.seekToTime(time: seekToTime, completion: completion);
    }
    
    func picture(_ controller: IVTPictureInPictureController, isPlaying playing: Bool) {
        if playing {
            contentView?.play()
        } else {
            contentView?.pause()
        }
    }
    
    func picture(_ controller: IVTPictureInPictureController, isPlaying : IVTPictureInPicturePlaybackStatus) {
        
    }
    func picture(_ controller: IVTPictureInPictureController, failedToStartWithError error: Error) {
        print("\(error)")
    }
    
    func picture(inPictureControllerWillStart controller: IVTPictureInPictureController) {
        contentView?.enablePipMode(enabled: true)
    }
    
    func picture(inPictureControllerDidStart controller: IVTPictureInPictureController) {
        
    }
    
    func picture(_ controller: IVTPictureInPictureController, didStopForRestore isRestore: Bool) {
        contentView?.restorePlayerView()
        contentView?.enablePipMode(enabled: false)
        print("pip did stop, recover view")
        UIApplication.shared.endReceivingRemoteControlEvents()
    }
    
}

struct ContentView: View {
    @State private var useSampleBuffer = true
    @State private var useLiveMode = false
    @State private var autoPlayNext = false
    @State private var hideControls = false
    @State private var useCustomControls = true
    @State private var playSpeed = 1.0
    @State private var customPlayerObToken:NSKeyValueObservation?
    @State private var avPlayer:AVPlayer?
    @State private var avPlayerObToken:NSObjectProtocol?
    @State private var playerControlView:PipPlayerControlView?
    @State private var playerView:UIView?
    @State private var autoStartPipWhenBackground = true;
    @State private var canPauseWhenExiting = false
    @State private var autoPauseWhenScreenLock = false
    @State private var autoPauseWhenPlayToEnd = false
    @State private var stalled = false
    @State private var picDelegate : PicDelegate?
    @State var pipController: IVTPictureInPictureController?
    @State var currentVideoUrl = sVideoUrls[0]
    
    
    
    func createAVPlayer() {
        avPlayer = AVPlayer(url: currentVideoUrl!);
        let view = AVPlayerView()
        view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.playerLayer().player = avPlayer
        playerView = view
        attachPlayerControl()
        avPlayerObToken = NotificationCenter.default.addObserver(forName:NSNotification.Name.AVPlayerItemDidPlayToEndTime, object: nil, queue: OperationQueue.main) { note in
            if note.object as? AVPlayerItem != avPlayer?.currentItem {
                return
            }
            if useLiveMode {
                avPlayer?.seek(to: CMTime.zero);
                avPlayer?.rate = Float(playSpeed)
            } else if (autoPlayNext) {
                switchVideo(true)
            }
        }
    }
    
    func restorePlayerView() {
        let view = playerView;
        playerView = nil;
        playerView = view;
    }
    
    func attachPlayerControl() {
        
        if let playerControlView = playerControlView {
            if (playerControlView.superview != playerView) {
                playerView?.addSubview(playerControlView)
            }
            return
        }
        let controlView = PipPlayerControlView()
        controlView.isHidden = hideControls;
        playerControlView = controlView
        controlView.previousCallback = {
            switchVideo(false)
        }
        controlView.nextCallback = {
            switchVideo(true)
        }
        controlView.playCallback = {
            play()
        }
        controlView.pauseCallback = {
            pause()
        }
        playerView?.addSubview(controlView)
        controlView.frame = playerView?.bounds ?? CGRectZero
    }
    
    func play() {
       
        if avPlayer == nil {
            createAVPlayer()
        }
        if (currentTime() - duration() > -0.001 && !autoPlayNext) {
            if let pipController = pipController {
                pipController.seek(toTime: 0)
            }
            seekToTime(time: 0)
        }
        avPlayer?.rate = Float(playSpeed)
        
        pipController?.play();
        playerControlView?.paused = false
    }
    
    func pause() {
        avPlayer?.pause()
        pipController?.pause();
        playerControlView?.paused = true
    }
    
    func paused() ->Bool {
        return avPlayer?.rate == 0
        
    }
    
    func setSpeed(speed:Double) {
        if (speed <= 0) {
            return
        }
        avPlayer?.rate = paused() ? 0 : Float(speed)
        
        pipController?.speed = speed;
    }
    
    func seekToTime(time:Double, completion: (() -> Void)? = nil)   {
        if (time > CMTimeGetSeconds(avPlayer?.currentItem?.duration ?? CMTime.zero)) {
            play();
        }
        avPlayer?.seek(to: CMTimeMakeWithSeconds(time, preferredTimescale: 600), toleranceBefore: CMTime.zero, toleranceAfter: CMTime.zero, completionHandler: { _ in
            if let completion = completion {
                completion();
            }
        })
    }
    
    func duration() -> Double {
        return CMTimeGetSeconds(avPlayer?.currentItem?.duration ?? CMTime.zero)
        
    }
    
    func videoSize() -> CGSize {
        return avPlayer?.currentItem?.presentationSize ?? CGSize.zero
    }
    
    func currentTime() -> Double {
        return CMTimeGetSeconds(avPlayer?.currentItem?.currentTime() ?? CMTime.zero)
        
    }
    
    func setLoopMode(looped:Bool)  {
        if looped {
            avPlayer?.rate = Float(playSpeed)
        }
    }
    func resetDuration() {
        pipController?.videoSize = videoSize()
        pipController?.duration = useLiveMode ? 0 :duration()
        pipController?.enableSeek = !useLiveMode
        pipController?.resetVideo(completion: { err in
            if (err != nil) {
                return
            }
            pause()
            play()
        })
    }
    
    func switchVideo(_ forward: Bool) {
        var index : Int;
        if (currentVideoUrl != nil) {
            index =  sVideoUrls.firstIndex(of: currentVideoUrl) ?? 0
            index += forward ? 1 : -1
        } else {
            index = forward ? 1 : -1;
        }
        if (index < 0) {
            index = sVideoUrls.count - 1;
        } else if (index >= sVideoUrls.count) {
            index = 0;
        }
        let newURL = sVideoUrls[index]
        currentVideoUrl = newURL
        
        let newItem = AVPlayerItem(url: newURL!)
        avPlayer?.replaceCurrentItem(with: newItem)
        play()
        var token: NSKeyValueObservation?
        token = newItem.observe(\AVPlayerItem.status, changeHandler: { item, change in
            if (item.status == .readyToPlay) {
                token?.invalidate()
                token = nil
                resetDuration()
            }
        })
    }
    
    fileprivate func preparePic() {
        var controller = pipController
        if (controller == nil){
            controller = IVTPictureInPictureController()
        }
        guard let controller = controller else {
            return
        }
        if controller.contentView == playerView {
            return
        }
        guard let playerView = playerView else {
            return
        }
        controller.contentView = playerView;
        controller.duration = useLiveMode ? 0 : duration();
        controller.enableSeek = !useLiveMode
        controller.videoSize = videoSize()
        controller.rate = paused() ? 0 : playSpeed
        controller.targetBackgroundRestoreArea = playerView.frame;
        controller.targetForegroundRestoreArea = playerView.frame;
        let delegate = PicDelegate()
        delegate.contentView = self
        controller.delegate = delegate
        picDelegate = delegate
        controller.backBySampleBuffer = useSampleBuffer
        controller.canStartAutomaticallyFromInline = autoStartPipWhenBackground
        controller.controlsHidden = hideControls;
        controller.canPauseWhenExiting = canPauseWhenExiting;
        controller.autoPauseWhenScreenLocked = autoPauseWhenScreenLock
        controller.notifyStopWhenTerminated = true
        controller.stalled = stalled
        controller.autoPauseWhenPlayToEndTime = autoPauseWhenPlayToEnd
        
        controller.sourceContainerView = playerView.superview;

        controller.preparePictureInPicture()
        pipController = controller
        
        
//        if #available(iOS 15.0, *) {
//            let view = UIView(frame: CGRect(x: 0, y: 0, width: 200, height: 200));
//            let controller = AVPictureInPictureVideoCallViewController()
//            UIApplication.shared.keyWindow?.addSubview(view)
//            let pip = AVPictureInPictureController(contentSource: AVPictureInPictureController.ContentSource(activeVideoCallSourceView: view, contentViewController: controller))
//            avPipController = pip
//            DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(100), execute: {
//                pip.startPictureInPicture();
//                view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
//                view.backgroundColor = UIColor.yellow
//                controller.view.addSubview(view)
//            })
//        } else {
//            // Fallback on earlier versions
//        }
        
    }
    
    func enablePipMode(enabled:Bool) {
        playerControlView?.isHidden = !useCustomControls || enabled;
        let view = playerView as! AVPlayerView
            view.playerLayer().pictureInPictureModeEnabled = enabled
        
    }
    
    func startPic() {
        if (pipController?.contentView == nil) {
            preparePic()
        }
        pipController?.startPictureInPicture()

    }
    
    func stopPic() {
        pipController?.stopPictureInPicture()
    }
    
    func hidePic() {
        pipController?.hideAndPause()
        try? AVAudioSession.sharedInstance().setCategory(.ambient)
    }
    
    func resumePic() {
        pipController?.resume()
    }
    
    var body: some View {
        
        VStack(alignment:.leading) {
            PlayerViewContainer(playerView:$playerView).frame(width: 320, height: 180, alignment: .center)
            HStack(alignment: .center, spacing: 20, content: {
                Button("播放") {
                    if (playerView?.superview == nil) {
                        restorePlayerView()
                    }
                    play()
                }
                Button("暂停") {
                    pause()
                }
                
                Button("下一集") {
                    switchVideo(true)
                }
                Button("上一集") {
                    switchVideo(false)
                }
            })
            //LazyVGrid()
            HStack(alignment: .center, spacing: 20) {
                Button("预创建小窗"){
                    preparePic()
                }
                Button("开启小窗") {
                    startPic()
                }
                Button("关闭小窗") {
                    stopPic()
                }
            }
            HStack(alignment: .center, spacing: 20) {
                Button("恢复小窗") {
                    resumePic()
                }
                Button("隐藏小窗") {
                    hidePic()
                }
            }
            ScrollView() {
                VStack (alignment:.leading) {
                    Toggle("iOS15使用sampleBuffer", isOn: $useSampleBuffer).onAppear {
                        if #available(iOS 15, *) {
                            useSampleBuffer = true
                        }
                    };
                    
                    Toggle("退出后台自动打开小窗", isOn:$autoStartPipWhenBackground).onChange(of: autoStartPipWhenBackground) { newValue in
                        pipController?.canStartAutomaticallyFromInline = newValue
                    }
                    Toggle("使用直播模式", isOn:$useLiveMode).onChange(of: useLiveMode) { newValue in
                        if newValue {
                            autoPlayNext = false
                        }
                        setLoopMode(looped: newValue)
                    }
                    VStack (alignment:.leading) {
                        Toggle("小窗使用隐藏播控", isOn:$hideControls).onChange(of: hideControls) { newValue in
                            pipController?.controlsHidden = newValue;
                        }
                        
                        Toggle("添加自定义播控", isOn:$useCustomControls).onChange(of: useCustomControls) { newValue in
                            playerControlView?.isHidden = newValue && !IVTPictureInPictureController.isActive();
                        }
                        
                        Toggle("退出小窗自动暂停", isOn:$canPauseWhenExiting).onChange(of: canPauseWhenExiting) { newValue in
                            pipController?.canPauseWhenExiting = newValue;
                        }
                        Toggle("自动播放下一集", isOn:$autoPlayNext)
                        
                        Toggle("播放器卡顿", isOn:$stalled).onChange(of: stalled) { newValue in
                            pipController?.stalled = newValue;
                        }
                        
                        Toggle("锁屏自动暂停", isOn:$autoPauseWhenScreenLock).onChange(of: autoPauseWhenScreenLock) { newValue in
                            pipController?.autoPauseWhenScreenLocked = newValue;
                        }
                        
                        Toggle("小窗播完自动暂停", isOn:$autoPauseWhenPlayToEnd).onChange(of: autoPauseWhenPlayToEnd) { newValue in
                            pipController?.autoPauseWhenPlayToEndTime = newValue;
                        }
                        
                    }
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 0, alignment: .leading), GridItem(.flexible(), spacing: 0, alignment: .trailing)]) {
                        Text("播放速率:")
                        Picker("播放速率", selection:$playSpeed) {
                            Text("0.75").tag(0.75);
                            Text("1.0").tag(1.0);
                            Text("2.0").tag(2.0);
                            Text("3.0").tag(3.0);
                        }.pickerStyle(.menu).onChange(of: playSpeed) { newValue in
                            setSpeed(speed: newValue)
                        }
                    }
                }.padding(5)
            }
        }.fixedSize().offset(x:0, y: 20)
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
