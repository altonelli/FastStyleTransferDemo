//
//  ModelDataHandler.swift
//  FastStyleTransferDemo
//
//  Created by Arthur Tonelli on 4/15/20.
//  Copyright © 2020 Arthur Tonelli. All rights reserved.
//

import CoreImage
//import TensorFlowLite
import UIKit
import Accelerate
import CoreML

struct Result {
    let inferenceTime: Double
    let inferences: [Inference]
    let buffer: CVPixelBuffer
}

struct Inference {
    let confidence: Float
    let label: String
}

typealias FileInfo = (name: String, extension: String)

enum MobileNet {
//    static let modelInfo: FileInfo = (name: "mobilenet_quant_v1_224", extension: "tflite")
    static let modelInfo: FileInfo = (name: "mobilenet_v1_224", extension: "tflite")
//    static let modelInfo: FileInfo = (name: "sketch_fst_nonorm_256", extension: "tflite")
//    static let modelInfo: FileInfo = (name: "sketch_fst_512", extension: "tflite")
    static let labelsInfo: FileInfo = (name: "labels", extension: "txt")
}

class ModelDataHandler {
    let threadCount: Int
    let resultCount = 3
    let threadCountLimit = 10
    let batchSize = 1
    let inputChannels = 3
    let inputWidth = 224
    let inputHeight = 224
//    let inputWidth = 256
//    let inputHeight = 256
//    let sketchInputWidth = 175
//    let sketchInputHeight = 380
//    let sketchInputWidth = 360
//    let sketchInputHeight = 640
//    let sketchInputWidth = 525 // 350
//    let sketchInputHeight = 1140 // 760
    let sketchInputWidth = 480 // 360
    let sketchInputHeight = 853 // 640
//    let sketchModel: SketchResComp176
//    let sketchModel_mlarr: fst_batch_3_res_quant
    let sketchModel: HouseSketchFinal
    
    private var labels: [String] = []
//    private var interpreter: Interpreter
//    private let coreMLDelegate: CoreMLDelegate?
//    private let coreMLDelegate = CoreMLDelegate()
    
    private let alphaComponent = (baseOffSet: 4, ModuloRemainder: 3)
    
    init?(modelFileInfo: FileInfo, labelsFileInfo: FileInfo, threadCount: Int = 1) {
        let modelFilename = modelFileInfo.name
//        guard let modelPath = Bundle.main.path(forResource: modelFilename, ofType: modelFileInfo.extension) else {
//            print("Failed to load the modelwith name \(modelFilename).")
//            return nil
//        }
        
//        var delegateOptions = CoreMLDelegate.Options()
////        delegateOptions.enabledDevices = .allDevices
////        delegateOptions.maxDelegatedPartitions = 16
//        coreMLDelegate = CoreMLDelegate(options: delegateOptions)

        self.threadCount = threadCount
//        var options = Interpreter.Options()
//        options.threadCount = threadCount
        do {
//            if coreMLDelegate != nil {
//                interpreter = try Interpreter(modelPath: modelPath, options: options, delegates: [coreMLDelegate!])
//                print("Using interpretor with Core ML delegate")
//            } else {
//                interpreter = try Interpreter(modelPath: modelPath, options: options)
//                print("Using default interpretor")
//            }

//            try interpreter.allocateTensors()

//            try self.sketchModel = SketchResComp176()
//            try self.sketchModel_mlarr = fst_batch_3_res_quant()

            
            try self.sketchModel = HouseSketchFinal()
            ()
//            let config = MLModelConfiguration()
//            config.computeUnits = .all
//            try self.sketchModel = Udnie360Res3N10347(configuration: config)
            print(self.sketchModel.model.modelDescription)
            
//
//
        } catch let error {
            print("Failed to create the interpreter with error: \(error.localizedDescription)")
            return nil
        }
//        loadLabels(fileInfo: labelsFileInfo)
    }
    
    func run_test(_ pixelBuffer: CVPixelBuffer) {
        let res1 = Res4xNet480()
        var s = Date()
        var resPixBuffer: CVPixelBuffer
        var i: TimeInterval = Date().timeIntervalSince(s) * 1000
        var results: [TimeInterval] = []
        
        for n in 0...101 {
            s = Date()
            do {
                let pred = try res1.prediction(input_1: pixelBuffer)
                resPixBuffer = pred.upsample
            } catch let error {
                print("Error on  invocation: \(error)")
//                return nil
            }
            i = Date().timeIntervalSince(s) * 1000
    //        print("interval:  \(i)")
            results.append(i)
        }
        print(results)
        
    }
    
//    func runModel(onFrame pixelBuffer: CVPixelBuffer) -> CVPixelBuffer? {
    func runModel(onFrame pixelBuffer: CVPixelBuffer) -> Result? {
        let sourcePixelFormat = CVPixelBufferGetPixelFormatType(pixelBuffer)
        assert(sourcePixelFormat == kCVPixelFormatType_32ARGB ||
            sourcePixelFormat == kCVPixelFormatType_32BGRA ||
            sourcePixelFormat == kCVPixelFormatType_32RGBA)
        // this feels dumb
        let imageChannels = 4
        assert(imageChannels >= inputChannels)
        
//        run_test(pixelBuffer)
        

//        let input = MosaicBigInput(inputs: pixelBuffer)

        let interval: TimeInterval
//        let outputTensor: Tensor
        var resBuffer: CVPixelBuffer
//            print("pixel buffer type 11111 \(resBuffer.pixelFormatName())")
        
        do {
            

            let startDate = Date()
            
//            print("pixel buffer type \(pixelBuffer.pixelFormatName())")
            do {
//                try interpreter.invoke()
                let pred = try self.sketchModel.prediction(inputs: pixelBuffer)
                resBuffer = pred.upsample
                print(CVPixelBufferGetHeight(resBuffer))

            } catch let error {
                print("Error on  invocation: \(error)")
                return nil
            }
            interval = Date().timeIntervalSince(startDate) * 1000
            print("interval:  \(interval)")
            
//            outputTensor = try interpreter.output(at: 0)
            
            
        } catch let error {
            print("Failed to invoke the interrper with error: \(error.localizedDescription)")
            return nil
        }
        
        let results: [Float]

        let stubInferences = [Inference(confidence: 0.99, label: "First"), Inference(confidence: 0.98, label: "Second"), Inference(confidence: 0.97, label: "Third")]
        
        return Result(inferenceTime: interval, inferences: stubInferences, buffer: resBuffer)
//        return resBuffer
    }
    
    private func getTopN(results: [Float]) -> [Inference] {
        let zippedResults = zip(labels.indices, results)
        
        let sortedResults = zippedResults.sorted { $0.1 > $1.1}.prefix(resultCount)
        return sortedResults.map {result in Inference(confidence: result.1, label: labels[result.0])}
    }
    
    private func loadLabels(fileInfo: FileInfo) {
        let filename = fileInfo.name
        let fileExtension = fileInfo.extension
        guard let fileURL = Bundle.main.url(forResource: filename, withExtension: fileExtension) else {
            fatalError("Labels file not found in bundle. Please add a labels file with name " +
                "\(filename).\(fileExtension) and try again.")
        }
        do {
            let contents = try String(contentsOf: fileURL, encoding: .utf8)
            labels = contents.components(separatedBy: .newlines)
        } catch {
            fatalError("Labels file named \(filename).\(fileExtension) cannot be read. Please add a " +
                "valid labels file and try again.")
        }
    }
    
    private func rgbDataFromBuffer(
        _ buffer: CVPixelBuffer,
        byteCount: Int,
        isModelQuantized: Bool
    ) -> Data? {
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer {
            CVPixelBufferUnlockBaseAddress(buffer, .readOnly)
        }
        guard let sourceData = CVPixelBufferGetBaseAddress(buffer) else {
            return nil
        }
        
        let width = CVPixelBufferGetWidth(buffer)
        let height = CVPixelBufferGetHeight(buffer)
        let sourceBytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
        let destinationChannelCount = 3
        let destinationBytesPerRow = destinationChannelCount * width
        
        var sourceBuffer = vImage_Buffer(data: sourceData,
                                         height: vImagePixelCount(height),
                                         width: vImagePixelCount(width),
                                         rowBytes: sourceBytesPerRow)
        
        guard let destinationData = malloc(height * destinationBytesPerRow) else {
            print("Error: out of memory")
            return nil
        }
        defer {
            free(destinationData)
        }
        
        var destinationBuffer = vImage_Buffer(data: destinationData,
                                              height: vImagePixelCount(height),
                                              width: vImagePixelCount(width),
                                              rowBytes: destinationBytesPerRow)
        
        let pixelBufferFormat = CVPixelBufferGetPixelFormatType(buffer)
        
        switch (pixelBufferFormat) {
        case kCVPixelFormatType_32BGRA:
            vImageConvert_BGRA8888toRGB888(&sourceBuffer, &destinationBuffer, UInt32(kvImageNoFlags))
        case kCVPixelFormatType_32ARGB:
            vImageConvert_ARGB8888toRGB888(&sourceBuffer, &destinationBuffer, UInt32(kvImageNoFlags))
        case kCVPixelFormatType_32RGBA:
            vImageConvert_RGBA8888toRGB888(&sourceBuffer, &destinationBuffer, UInt32(kvImageNoFlags))
        default:
            return nil
        }
        
        let byteData = Data(bytes: destinationBuffer.data, count:destinationBuffer.rowBytes * height)
        
        if isModelQuantized {
            return byteData
        }
        
        let bytes = Array<UInt8>(unsafeData: byteData)!
        var floats = [Float]()
        for i in 0..<bytes.count {
            floats.append(Float(bytes[i]) / 255.0)
        }
        return Data(copyingBufferOf: floats)
    }
    
}

extension Data {
    init<T>(copyingBufferOf array:[T]) {
        self = array.withUnsafeBufferPointer(Data.init)
    }
}

extension Array {
    init?(unsafeData: Data) {
        guard unsafeData.count % MemoryLayout<Element>.stride == 0 else {
            return nil
        }
        #if swift(>=5.0)
        self = unsafeData.withUnsafeBytes {
            .init(UnsafeBufferPointer<Element>(
                start: $0,
                count: unsafeData.count / MemoryLayout<Element>.stride
            ))
        }
        #endif  // swift(>=5.0)e
    }
}


