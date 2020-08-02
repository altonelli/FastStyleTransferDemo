//
//  StyleTransferInput.swift
//  FastStyleTransferDemo
//
//  Created by Arthur Tonelli on 5/2/20.
//  Copyright © 2020 Arthur Tonelli. All rights reserved.
//

//import CoreML
//
//class sketch_nonorm_256Input : MLFeatureProvider {
//    
//    var input: CVPixelBuffer
//    
//    var featureNames: Set<String> {
//        get {
//            return ["img_placeholder__0"]
//        }
//    }
//    
//    func featureValue(for featureName: String) -> MLFeatureValue? {
//        if (featureName == "img_placeholder__0") {
//            return MLFeatureValue(pixelBuffer: input)
//        }
//        return nil
//    }
//    
//    init(input: CVPixelBuffer) {
//        self.input = input
//    }
//}
