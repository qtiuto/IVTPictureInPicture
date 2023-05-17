//
//  PipPlayerControlView.swift
//  PipTest
//
//  Created by Osl on 2023/1/11.
//

import UIKit

class PipPlayerControlView: UIView {
    
    var contentView = UIView()
    var playButton = UIButton()
    var nextButton = UIButton()
    var previousButton = UIButton()
    var playCallback : (() -> Void)?
    var pauseCallback : (() -> Void)?
    var nextCallback : (() -> Void)?
    var previousCallback : (() -> Void)?
    
    var paused: Bool {
        get{
            return playButton.isSelected
        }
        
        set {
            playButton.isSelected = newValue
        }
    }
    
    /*
    // Only override draw() if you perform custom drawing.
    // An empty implementation adversely affects performance during animation.
    override func draw(_ rect: CGRect) {
        // Drawing code
    }
    */
    override init(frame:CGRect) {
        super.init(frame: frame);
        contentView.frame = bounds;
        contentView.isHidden = true;
        contentView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        addSubview(contentView)
        self.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        self.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(onTap)))
        contentView.addSubview(playButton)
        contentView.addSubview(nextButton)
        contentView.addSubview(previousButton)
        playButton.setBackgroundImage(UIImage(named: "play"), for: .selected)
        playButton.setBackgroundImage(UIImage(named: "pause"), for: .normal)
        nextButton.setBackgroundImage(UIImage(named: "forward"), for: .normal)
        previousButton.setBackgroundImage(UIImage(named: "rewind"), for: .normal)
        playButton.addTarget(self, action: #selector(playButtonClicked), for: .touchUpInside)
        nextButton.addTarget(self, action: #selector(nextButtonClicked), for: .touchUpInside)
        previousButton.addTarget(self, action: #selector(previousButtonClicked), for: .touchUpInside)
        playButton.frame = CGRect(x: 0, y: 0, width: 30, height: 30);
        nextButton.frame = CGRect(x: 0, y: 0, width: 30, height: 30);
        previousButton.frame = CGRect(x: 0, y: 0, width: 30, height: 30);
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    @objc func nextButtonClicked()  {
        if let nextCallback = nextCallback {
            nextCallback()
        }
    }
    @objc func previousButtonClicked()  {
        if let previousCallback = previousCallback {
            previousCallback()
        }
    }
    @objc func playButtonClicked()  {
        if (paused) {
            if let playCallback = playCallback {
                playCallback()
            }
        } else {
            if let pauseCallback = pauseCallback {
                pauseCallback()
            }
        }
    }
    
    @objc func onTap()  {
        if (!contentView.isHidden) {
            return
        }
        contentView.isHidden = false
        DispatchQueue.main.asyncAfter(deadline: DispatchTime.now() + .seconds(3)) {
            self.contentView.isHidden = true;
        }
        
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        let size = self.bounds.size;
        playButton.center = CGPointMake(size.width / 2, size.height / 2);
        nextButton.center = CGPointMake(size.width / 2 + 50, size.height / 2);
        previousButton.center = CGPointMake(size.width / 2 - 50, size.height / 2);
    }
    
}
