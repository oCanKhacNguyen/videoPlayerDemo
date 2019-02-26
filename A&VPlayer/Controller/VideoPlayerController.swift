//
//  VideoPlayerController.swift
//  A&VPlayer
//
//  Created by can.khac.nguyen on 2/21/19.
//  Copyright © 2019 can.khac.nguyen. All rights reserved.
//

import UIKit
import AVKit
import AVFoundation

class VideoPlayerController: UIViewController {
    @IBOutlet weak var minimizeButton: UIButton!
    @IBOutlet weak var previousButton: UIButton!
    @IBOutlet weak var playButton: UIButton!
    @IBOutlet weak var nextButton: UIButton!
    @IBOutlet weak var timeTrackingSlider: UISlider!
    @IBOutlet weak var playerView: UIView!
    @IBOutlet weak var bottomControlViewConstraint: NSLayoutConstraint!
    @IBOutlet weak var topToolbarConstraint: NSLayoutConstraint!
    @IBOutlet weak var bottomView: UIView!
    @IBOutlet weak var timeLabel: UILabel!
    @IBOutlet weak var speedSegment: UISegmentedControl!
    
    var urls: [URL]?
    var avPlayer: AVPlayer?
    var avPlayerLayer: AVPlayerLayer?
    var currentTrack: Track?
    var isShowingToolBar = true
    var timeObserver: Any?
    var progressView = UIProgressView()

    // BanNN: chưa có handle khi video chạy xong thì next item hoặc đổi button play <-> pause
    // BanNN: chưa xử lý enable button next và previous

    override func viewDidLoad() {
        super.viewDidLoad()
        configControlView()
        configSpeedSegment()
        configPlayer()
        configSeeker()
    }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)

        guard let avPlayerLayer = avPlayerLayer else {
            return
        }
        let deviceOrientation = Utilities.getDeviceOrientation(screenSize: size)
        avPlayerLayer.videoGravity = deviceOrientation == .portrait ? .resizeAspect : .resizeAspectFill
        avPlayerLayer.frame = CGRect(x: 0, y: 0, width: size.width, height: size.height)

        coordinator.animate(alongsideTransition: { [weak self] _ in
            self?.setHiddenToolbar(isHidden: deviceOrientation == .landscape)
        }, completion: nil)
    }

    deinit {
        stopObserver()
    }

    // MARK: Observer
    override func observeValue(forKeyPath keyPath: String?, of object: Any?,
                               change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
        if keyPath == #keyPath(AVPlayerItem.status) {
            var status: AVPlayerItem.Status = .unknown
            if let statusNumber = change?[.newKey] as? NSNumber,
                let newStatus = AVPlayerItem.Status(rawValue: statusNumber.intValue) {
                status = newStatus
            }
            switch status {
            case .readyToPlay:
                currentTrack?.state = .readyToPlay
                play()
            default:
                break
            }
        } else if keyPath == Constant.loadTimeRangedKey {
            let duration = avPlayer?.currentItem?.asset.duration
            let durationSeconds = CMTimeGetSeconds(duration ?? .zero)
            onLoadedTimeRangedChanged(newValue: avPlayer?.currentItem?.loadedTimeRanges, duration: CGFloat(durationSeconds))
        }
    }

    private func startObserver() {
        let interval = CMTime(seconds: 1.0, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        guard let avPlayer = avPlayer, let durationCMTimeFormat = avPlayer.currentItem?.asset.duration else {
            return
        }
        let duration = CMTimeGetSeconds(durationCMTimeFormat)
        timeObserver = avPlayer.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            guard let currentTrack = self?.currentTrack else { return }
            if currentTrack.state != .seeking {
                self?.timeTrackingSlider.setValue(Float(time.seconds / Double(duration)), animated: true)
            }
            if Float(time.seconds / Double(duration)) >= 1 {
                self?.currentTrack?.state = .playedToTheEnd
                self?.playButton.setImage(#imageLiteral(resourceName: "playButton"), for: .normal)
            }
            self?.setTimeLabel(withDuration: duration, currentTime: time.seconds)
        }
        // add KVO
        avPlayer.currentItem?.addObserver(self, forKeyPath: #keyPath(AVPlayerItem.status), options: .new, context: nil)
        avPlayer.currentItem?.addObserver(self, forKeyPath: Constant.loadTimeRangedKey, options: .new, context: nil)
    }

    private func stopObserver() {
        if let timeObserver = timeObserver {
            avPlayer?.removeTimeObserver(timeObserver)
            avPlayer?.currentItem?.removeObserver(self, forKeyPath: #keyPath(AVPlayerItem.status))
            avPlayer?.currentItem?.removeObserver(self, forKeyPath: Constant.loadTimeRangedKey)
            self.timeObserver = nil
        }
    }

    // MARK: Private func
    private func setTimeLabel(withDuration duration: Double, currentTime: Double) {
        timeLabel.text = Utilities.formatDurationTime(time: Int(currentTime)) + "/" +
            Utilities.formatDurationTime(time: Int(duration))
    }

    private func configPlayer() {
        guard let urls = urls else { return }
        currentTrack = Track(url: urls[0], index: 0)
        avPlayer = AVPlayer()
        avPlayerLayer = AVPlayerLayer(player: avPlayer)
        avPlayerLayer?.videoGravity = .resizeAspect
        if let layer = avPlayerLayer {
            playerView.layer.addSublayer(layer)
            layer.frame = CGRect(x: 0, y: 0, width: UIScreen.main.bounds.width,
                                 height: UIScreen.main.bounds.height)
        }
        prepareForPlay()
    }

    private func onLoadedTimeRangedChanged(newValue: [NSValue]?, duration: CGFloat) {
        // BanNN: không nên dùng [0] nên dùng .first và có guard let đầy đủ. thử link: https://devimages-cdn.apple.com/samplecode/avfoundationMedia/AVFoundationQueuePlayer_HLS2/master.m3u8 này sẽ thấy crash sml chỗ này =))
        guard let timeRange = newValue?.first?.timeRangeValue else {
            return
        }
        let loadedValue = CMTimeGetSeconds(timeRange.duration)
        progressView.setProgress(Float(CGFloat(loadedValue) / duration), animated: true)
    }

    private func configSeeker() {
        // time slider
        timeTrackingSlider.setThumbImage(#imageLiteral(resourceName: "seekIcon"), for: .normal)
        timeTrackingSlider.setValue(0, animated: false)
        timeTrackingSlider.addTarget(self, action: #selector(handleSliderChangeValue(sender:event:)), for: .allEvents)
        // progress View
        progressView.tintColor = .white
        progressView.trackTintColor = UIColor(red: 1, green: 1, blue: 1, alpha: 0.3)
        bottomView.insertSubview(progressView, belowSubview: timeTrackingSlider)
        progressView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
                progressView.leftAnchor.constraint(equalTo: timeTrackingSlider.leftAnchor),
                progressView.rightAnchor.constraint(equalTo: timeTrackingSlider.rightAnchor),
                progressView.centerYAnchor.constraint(equalTo: timeTrackingSlider.centerYAnchor, constant: 1),
                progressView.heightAnchor.constraint(equalToConstant: 1)
            ])
        // time label
        setTimeLabel(withDuration: CMTimeGetSeconds(avPlayer?.currentItem?.asset.duration ?? .zero), currentTime: 0)
    }

    private func configControlView() {
        let downArrowImage = #imageLiteral(resourceName: "minimizeButton").withRenderingMode(.alwaysTemplate)
        let previousImage = #imageLiteral(resourceName: "previousButton").withRenderingMode(.alwaysTemplate)
        let nextImage = #imageLiteral(resourceName: "nextButton").withRenderingMode(.alwaysTemplate)
        nextButton.setImage(nextImage, for: .normal)
        previousButton.setImage(previousImage, for: .normal)
        minimizeButton.setImage(downArrowImage, for: .normal)
        nextButton.tintColor = .white
        previousButton.tintColor = .white
        minimizeButton.tintColor = .white
    }

    private func configSpeedSegment() {
        speedSegment.selectedSegmentIndex = 1
    }

    private func resetSeeker() {
        setTimeLabel(withDuration: CMTimeGetSeconds(avPlayer?.currentItem?.asset.duration ?? .zero), currentTime: 0)
        timeTrackingSlider.setValue(0, animated: false)
        progressView.setProgress(0, animated: false)
    }

    private func setHiddenToolbar(isHidden: Bool) {
        isShowingToolBar = !isHidden
        let toolbarHeight: CGFloat = 30
        let controlViewHeight: CGFloat = 60

        /* BanNN: animation ẩn đi bằng cách cho constraint top với bottom về âm? nhưng sao lại là 300, 600?
        Với cả sửa constant thế này sẽ không có animation đâu. nó sẽ đổi ngay lập tức.
        Để có animation cần thêm: self.view.layoutIfNeeded() vào trong animation
        */
        UIView.animate(withDuration: 0.5) { [weak self] in
            self?.topToolbarConstraint.constant = isHidden ? -toolbarHeight * 2 : 0
            self?.bottomControlViewConstraint.constant = isHidden ? -controlViewHeight : 0
            self?.view.layoutIfNeeded()
        }
    }

    private func setHiddenControlButton() {
        guard let count = urls?.count else { return }
        if currentTrack?.index == 0 {
            nextButton.isEnabled = count == 0 ? false : true 
            previousButton.isEnabled = false
        } else if currentTrack?.index == count - 1 {
            nextButton.isEnabled = false
            previousButton.isEnabled = true
        }
    }

    private func getNextItem() -> Track? {
        guard let urls = urls, let trackIndex = currentTrack?.index, trackIndex >= 0 else { return nil}
        let nextIndex = trackIndex + 1 >= urls.count ? 0 : trackIndex + 1
        return Track(url: urls[nextIndex], index: nextIndex)
    }

    private func getPreviousItem() -> Track? {
        guard let urls = urls, let trackIndex = currentTrack?.index, trackIndex >= 0 else { return nil }
        let previousIndex = trackIndex - 1 < 0 ? 0 : trackIndex - 1
        return Track(url: urls[previousIndex], index: previousIndex)
    }

    // call first at all when open new song
    private func prepareForPlay() {
        stopObserver()
        currentTrack?.playerItem.canUseNetworkResourcesForLiveStreamingWhilePaused = true
        avPlayer?.replaceCurrentItem(with: currentTrack?.playerItem)
        startObserver()
        setHiddenControlButton()
    }

    private func play() {
        guard let avPlayer = avPlayer, currentTrack?.state != .playedToTheEnd else { return }
        avPlayer.play()
        playButton.setImage(#imageLiteral(resourceName: "pauseButton"), for: .normal)
    }

    private func pause() {
        guard let avPlayer = avPlayer else { return }
        avPlayer.pause()
        playButton.setImage(#imageLiteral(resourceName: "playButton"), for: .normal)
    }

    private func playNextItem() {
        configSpeedSegment()
        resetSeeker()
        currentTrack = getNextItem()
        prepareForPlay()
    }

    private func playPreviousItem() {
        configSpeedSegment()
        resetSeeker()
        currentTrack = getPreviousItem()
        prepareForPlay()
    }

    @objc private func handleSliderChangeValue(sender: AnyObject, event: UIEvent) {
        guard let handleEvent = event.allTouches?.first else { return }
        switch handleEvent.phase {
        case .began:
            currentTrack?.state = .seeking
        case .ended:
            currentTrack?.state = .readyToPlay
            guard let duration = avPlayer?.currentItem?.asset.duration, let item = avPlayer?.currentItem else { return }
            let valueChanged = Double(timeTrackingSlider.value) * duration.seconds
            let timeIntervalChanged = CMTime(seconds: valueChanged, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
            item.seek(to: timeIntervalChanged, completionHandler: nil)
        default:
            break
        }
    }

    // MARK: Handle ibAction
    @IBAction func onPlayerViewDidTap(_ sender: UITapGestureRecognizer) {
        setHiddenToolbar(isHidden: isShowingToolBar)
    }

    @IBAction func onPlayPauseClicked(_ sender: Any) {
        guard let avPlayer = avPlayer else {
            return
        }
        avPlayer.isPlaying ? pause() : play()
    }

    @IBAction func onNextButtonClicked(_ sender: UIButton) {
        pause()
        playNextItem()
    }

    @IBAction func onPreviousButtonClicked(_ sender: UIButton) {
        pause()
        playPreviousItem()
    }

    @IBAction func onMinimizeButtonClicked(_ sender: UIButton) {
        dismiss(animated: true, completion: nil)
    }

    @IBAction func onSpeedSegmentClicked(_ sender: Any) {
        let speed = speedSegment.selectedSegmentIndex == 0 ? 0.5 : Double(speedSegment.selectedSegmentIndex)
        avPlayer?.rate = Float(speed)
    }
}
