//
//  RangeSlider.swift
//  VideoPlayer
//
//  Created by Amr Mohamed on 4/5/16.
//  Copyright © 2016 Amr Mohamed. All rights reserved.
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in all
//  copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
//  SOFTWARE.


import UIKit
import QuartzCore
import AVFoundation

internal class AMVideoRangeSliderThumbLayer: CAShapeLayer {
    var highlighted = false
    var isAtEnd = false {
        didSet {
            self.cornerRadius = self.isAtEnd ? 0 : self.bounds.width / 2
            self.setNeedsDisplay()
        }
    }
    weak var rangeSlider : AMVideoRangeSlider?

    override func contains(_ p: CGPoint) -> Bool {
        return self.isHidden ? false : super.contains(p)
    }

    override func layoutSublayers() {
        super.layoutSublayers()
        self.cornerRadius = self.isAtEnd ? 0 : self.bounds.width / 2
        self.setNeedsDisplay()
    }

    override func draw(in ctx: CGContext) {
        ctx.move(to: CGPoint(x: self.bounds.width/2, y: self.bounds.height/5))
        ctx.addLine(to: CGPoint(x: self.bounds.width/2, y: self.bounds.height - self.bounds.height/5))
        ctx.setStrokeColor(UIColor.white.cgColor)
        ctx.strokePath()
    }
}

internal class AMVideoRangeSliderTrackLayer: CAShapeLayer {

    weak var rangeSlider : AMVideoRangeSlider?

    override func draw(in ctx: CGContext) {
        guard let slider = self.rangeSlider else {
            return
        }
        let lowerValuePosition = CGFloat(slider.positionForValue(slider.lowerValue)) + slider.thumbWidth / 2
        let upperValuePosition = CGFloat(slider.positionForValue(slider.upperValue)) - slider.thumbWidth / 2
        let rect = CGRect(x: lowerValuePosition, y: 0.0,
                          width: upperValuePosition - lowerValuePosition,
                          height: bounds.height)
        guard rect.width > slider.thumbWidth else {
            return
        }
        ctx.setFillColor(UIColor.black.withAlphaComponent(0.95).cgColor)
        ctx.setStrokeColor(slider.sliderTintColor.cgColor)
        ctx.fill(rect)
        ctx.stroke(rect, width: 2)
    }
}

public protocol AMVideoRangeSliderDelegate: class {
    func rangeSliderLowerThumbValueChanged()
    func rangeSliderMiddleThumbValueChanged()
    func rangeSliderUpperThumbValueChanged()
}

open class AMVideoRangeSlider: UIControl {

    open var middleValue = 0.0 {
        didSet {
            self.updateLayerFrames()
        }
    }

    var minimumDelta: Double = 0
    var maximumDelta: Double = 1

    open var minimumValue: Double = 0.0 {
        didSet {
            self.updateLayerFrames()
        }
    }

    open var maximumValue: Double = 1.0 {
        didSet {
            self.updateLayerFrames()
        }
    }

    open var lowerValue: Double = 0 {
        didSet {
            self.updateLayerFrames()
        }
    }

    open var upperValue: Double = 1 {
        didSet {
            self.updateLayerFrames()
        }
    }

    open var videoAsset : AVAsset? {
        didSet {
            self.generateVideoImages()
        }
    }

    open var currentTime : CMTime {
        return CMTimeMakeWithSeconds(self.videoAsset!.duration.seconds * self.middleValue, self.videoAsset!.duration.timescale)
    }

    open var startTime : CMTime! {
        return CMTimeMakeWithSeconds(self.videoAsset!.duration.seconds * self.lowerValue, self.videoAsset!.duration.timescale)
    }

    open var stopTime : CMTime! {
        return CMTimeMakeWithSeconds(self.videoAsset!.duration.seconds * self.upperValue, self.videoAsset!.duration.timescale)
    }

    open var rangeTime : CMTimeRange! {
        let lower = self.videoAsset!.duration.seconds * self.lowerValue
        let upper = self.videoAsset!.duration.seconds * self.upperValue
        let duration = CMTimeMakeWithSeconds(upper - lower, 44100)
        return CMTimeRangeMake(self.startTime, duration)
    }

    open var sliderTintColor = UIColor(red:0.97, green:0.71, blue:0.19, alpha:1.00) {
        didSet {
            self.lowerThumbLayer.backgroundColor = self.sliderTintColor.cgColor
            self.upperThumbLayer.backgroundColor = self.sliderTintColor.cgColor

        }
    }

    open var middleThumbTintColor : UIColor! {
        didSet {
            self.middleThumbLayer.backgroundColor = self.middleThumbTintColor.cgColor
        }
    }

    open weak var delegate : AMVideoRangeSliderDelegate?

    var isSelectionEnabled: Bool = false {
        didSet {
            if self.isSelectionEnabled {
                self.lowerThumbLayer.isHidden = false
                self.upperThumbLayer.isHidden = false
                self.trackLayer.isHidden = false
                self.lowerValue = self.middleValue
                self.upperValue = min(self.middleValue + 0.2, 1)
            } else {
                self.lowerThumbLayer.isHidden = true
                self.upperThumbLayer.isHidden = true
                self.trackLayer.isHidden = true
            }
         }
    }

    var middleThumbLayer = AMVideoRangeSliderThumbLayer()
    var lowerThumbLayer = AMVideoRangeSliderThumbLayer()
    var upperThumbLayer = AMVideoRangeSliderThumbLayer()

    var trackLayer = AMVideoRangeSliderTrackLayer()

    var previousLocation = CGPoint()

    var thumbWidth : CGFloat {
        return 16
    }

    var thumbHeight : CGFloat {
        return self.bounds.height + 4
    }

    open override var frame: CGRect {
        didSet {
            self.updateLayerFrames()
        }
    }

    public override init(frame: CGRect) {
        super.init(frame: frame)
        self.commonInit()
    }

    public required init(coder : NSCoder) {
        super.init(coder: coder)!
        self.commonInit()
    }

    open override func layoutSubviews() {
        self.updateLayerFrames()
    }

    func commonInit() {
        self.trackLayer.rangeSlider = self
        self.middleThumbLayer.rangeSlider = self
        self.lowerThumbLayer.rangeSlider = self
        self.upperThumbLayer.rangeSlider = self

        self.layer.addSublayer(self.trackLayer)
        self.layer.addSublayer(self.lowerThumbLayer)
        self.layer.addSublayer(self.upperThumbLayer)
        self.layer.addSublayer(self.middleThumbLayer)

        self.middleThumbLayer.backgroundColor = UIColor.green.cgColor
        self.lowerThumbLayer.backgroundColor = self.sliderTintColor.cgColor
        self.upperThumbLayer.backgroundColor = self.sliderTintColor.cgColor

        self.trackLayer.contentsScale = UIScreen.main.scale
        self.lowerThumbLayer.contentsScale = UIScreen.main.scale
        self.upperThumbLayer.contentsScale = UIScreen.main.scale

        self.updateLayerFrames()
    }

    func updateLayerFrames() {
        guard !self.disableFrameUpdates else {
            return
        }

        CATransaction.begin()
        CATransaction.setDisableActions(true)

        self.trackLayer.frame = self.bounds
        self.trackLayer.setNeedsDisplay()

        let y = (self.bounds.height - self.thumbHeight) / 2
        self.middleThumbLayer.frame = CGRect(x: CGFloat(self.positionForValue(self.middleValue, width: 4)) - 2,
                                             y: y, width: 4, height: self.thumbHeight)
        var lowerX = CGFloat(self.positionForValue(self.lowerValue))
        var upperX = CGFloat(self.positionForValue(self.upperValue)) - self.thumbWidth
        if upperX - lowerX < self.thumbWidth {
            let nudge = (self.thumbWidth - (upperX - lowerX)) / 4
            lowerX -= nudge
            upperX += nudge
        }
        self.lowerThumbLayer.frame = CGRect(x: lowerX, y: y, width: self.thumbWidth, height: self.thumbHeight)
        self.upperThumbLayer.frame = CGRect(x: upperX, y: y, width: self.thumbWidth, height: self.thumbHeight)
        // Square corners on thumb if it's at an end.
        self.lowerThumbLayer.isAtEnd = (self.lowerValue == self.minimumValue)
        self.upperThumbLayer.isAtEnd = (self.upperValue == self.maximumValue)
        CATransaction.commit()
    }

    func positionForValue(_ value: Double, width: CGFloat = 0) -> Double {
        return Double(self.bounds.width - width) * (value - self.minimumValue) / (self.maximumValue - self.minimumValue) + Double(width / 2)
    }

    open override func beginTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
        let location = touch.location(in: self)
        self.previousLocation = location
        let value = self.previousLocation.x / self.frame.width

        if !self.isSelectionEnabled || value < CGFloat(self.lowerValue) || value > CGFloat(self.upperValue) {
            self.middleThumbLayer.highlighted = true
        } else if self.lowerThumbLayer.frame.insetBy(dx: -5, dy: 0).offsetBy(dx: -5, dy: 0).contains(location) {
            self.lowerThumbLayer.highlighted = true
        } else if self.upperThumbLayer.frame.insetBy(dx: -5, dy: 0).offsetBy(dx: 5, dy: 0).contains(location) {
            self.upperThumbLayer.highlighted = true
        } else {
            self.isMoving = true
        }
        return true
    }

    func boundValue(_ value: Double, toLowerValue lowerValue: Double, upperValue: Double) -> Double {
        return min(max(value, lowerValue), upperValue)
    }

    open override func continueTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
        let location = touch.location(in: self)
        let deltaLocation = Double(location.x - self.previousLocation.x)
        let deltaValue = (self.maximumValue - self.minimumValue) * deltaLocation / Double(self.bounds.width)

        let newMiddle = Double(self.previousLocation.x / self.bounds.width)
        self.previousLocation = location

        // Avoid rerendering all the moving about we perform below.
        self.disableFrameUpdates = true

        if self.lowerThumbLayer.highlighted {
            self.lowerValue += deltaValue
        } else if self.middleThumbLayer.highlighted {
            self.middleValue = newMiddle
        } else if self.upperThumbLayer.highlighted {
            self.upperValue += deltaValue
        } else if self.isMoving {
            self.lowerValue += deltaValue
            self.upperValue += deltaValue
        }

        // Ensure that lower/upper values are in valid positions.
        self.lowerValue = self.boundValue(self.lowerValue, toLowerValue: self.minimumValue, upperValue: self.maximumValue)
        self.upperValue = self.boundValue(self.upperValue, toLowerValue: self.minimumValue, upperValue: self.maximumValue)

        // Ensure that range is at least minimumDelta.
        if self.upperValue - self.lowerValue < self.minimumDelta {
            if deltaValue > 0 {
                self.lowerValue = self.upperValue - self.minimumDelta
            } else {
                self.upperValue = self.lowerValue + self.minimumDelta
            }
        }

        // Ensure that range is at most maximumDelta.
        if self.upperValue - self.lowerValue > self.maximumDelta {
            if deltaValue > 0 {
                self.lowerValue = self.upperValue - self.maximumDelta
            } else {
                self.upperValue = self.lowerValue + self.maximumDelta
            }
        }

        // Ensure that middleValue is in a valid position.
        if !self.isSelectionEnabled {
            self.middleValue = self.boundValue(self.middleValue, toLowerValue: self.minimumValue, upperValue: self.maximumValue)
        } else if self.middleValue < (self.lowerValue + self.upperValue) / 2 && self.lowerValue > self.minimumValue || self.upperValue == self.maximumValue {
            self.middleValue = self.boundValue(self.middleValue, toLowerValue: self.minimumValue, upperValue: self.lowerValue)
        } else {
            self.middleValue = self.boundValue(self.middleValue, toLowerValue: self.upperValue, upperValue: self.maximumValue)
        }

        // Notify delegate now that values have settled.
        if self.lowerThumbLayer.highlighted {
            self.delegate?.rangeSliderLowerThumbValueChanged()
        } else if self.middleThumbLayer.highlighted {
            self.delegate?.rangeSliderMiddleThumbValueChanged()
        } else if self.upperThumbLayer.highlighted {
            self.delegate?.rangeSliderUpperThumbValueChanged()
        } else if self.isMoving {
            self.delegate?.rangeSliderLowerThumbValueChanged()
        }

        // Render everything now that it's settled.
        self.disableFrameUpdates = false
        self.updateLayerFrames()

        self.sendActions(for: .valueChanged)
        return true
    }

    open override func endTracking(_ touch: UITouch?, with event: UIEvent?) {
        self.lowerThumbLayer.highlighted = false
        self.middleThumbLayer.highlighted = false
        self.upperThumbLayer.highlighted = false
        self.isMoving = false
    }

    func generateVideoImages() {
        guard
            let asset = self.videoAsset,
            let track = asset.tracks(withMediaType: .video).first
            else { return }
        DispatchQueue.main.async {
            for subview in self.subviews {
                if subview is UIImageView {
                    subview.removeFromSuperview()
                }
            }

            let duration = asset.duration.seconds
            let videoSize = track.naturalSize.applying(track.preferredTransform)

            guard videoSize.width != 0 && videoSize.height != 0 else {
                NSLog("%@", "WARNING: Video dimension was 0 after transform (\(track.naturalSize) -> \(videoSize))")
                return
            }

            let ratio = abs(videoSize.width) / abs(videoSize.height)
            let imageHeight = self.frame.height
            let imageWidth = imageHeight * ratio
            let numberOfImages = Int(ceil(self.frame.width / imageWidth))
            var imageFrame = CGRect(x: 0, y: (self.frame.height - imageHeight) / 2,
                                    width: self.frame.width / CGFloat(numberOfImages),
                                    height: imageHeight)

            let frameDuration = duration / Double(numberOfImages)

            var times = [NSValue]()
            for i in 0..<numberOfImages {
                let point = CMTime(seconds: frameDuration * Double(i), preferredTimescale: 44100)
                times += [NSValue(time: point)]
            }

            let scale = UIScreen.main.scale
            let g = AVAssetImageGenerator(asset: asset)
            g.appliesPreferredTrackTransform = true
            g.maximumSize = CGSize(width: imageWidth * scale,
                                   height: imageHeight * scale)
            g.generateCGImagesAsynchronously(forTimes: times) { (requestedTime, image, actualTime, result, error) in
                guard error == nil else {
                    print("Error at generating images : \(error?.localizedDescription ?? "[ERROR NOT AVAILABLE]")")
                    return
                }
                guard result == .succeeded else {
                    print("Failed to generate frame")
                    return
                }
                DispatchQueue.main.async {
                    let imageView = UIImageView(image: UIImage(cgImage: image!))
                    imageView.contentMode = .scaleAspectFill
                    imageView.clipsToBounds = true
                    imageView.frame = imageFrame
                    imageFrame.origin.x += imageFrame.width
                    self.insertSubview(imageView, at: 0)
                }
            }
        }
    }

    private var disableFrameUpdates = false
    private var isMoving = false
}
