//
//  PreviewView.swift
//  FastStyleTransferDemo
//
//  Created by Arthur Tonelli on 4/13/20.
//  Copyright © 2020 Arthur Tonelli. All rights reserved.
//

import UIKit
import AVFoundation

class PreviewView: MetalPreviewView {
    
//    var shouldUseClipboardImage: Bool = false {
//        didSet {
//            if shouldUseClipboardImage {
//                if imageView.superview == nil {
//                    addSubview(imageView)
//                    let constraints = [
//                        NSLayoutConstraint(item: imageView, attribute: .top,
//                                           relatedBy: .equal,
//                                           toItem: self, attribute: .top,
//                                           multiplier: 1, constant: 0),
//                        NSLayoutConstraint(item: imageView, attribute: .leading,
//                                           relatedBy: .equal,
//                                           toItem: self, attribute: .leading,
//                                           multiplier: 1, constant: 0),
//                        NSLayoutConstraint(item: imageView, attribute: .trailing,
//                                           relatedBy: .equal,
//                                           toItem: self, attribute: .trailing,
//                                           multiplier: 1, constant: 0),
//                        NSLayoutConstraint(item: imageView, attribute: .bottom,
//                                           relatedBy: .equal,
//                                           toItem: self, attribute: .bottom,
//                                           multiplier: 1, constant: 0),
//                    ]
//                    addConstraints(constraints)
//                }
//            } else {
//                imageView.removeFromSuperview()
//            }
//
//        }
//    }
    
    lazy private var imageView: UIImageView = {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFill
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()
    
    override var image: UIImage? {
        get {
            return imageView.image
        }
        set {
            imageView.image = newValue
        }
    }
    
//    var previewLayer: MetalPreviewView {
//        guard let layer = layer as? MetalPreviewView else {
//            fatalError("Layer expeected is of type MetalPreviewView")
//        }
//        return layer
//    }
    
//    var session: AVCaptureSession? {
//        get {
//            return previewLayer.session
//        }
//        set {
//            previewLayer.session = newValue
//        }
//    }
    
    override class var layerClass: AnyClass {
        return MetalPreviewView.self
    }
}
