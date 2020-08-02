//
//  MetalPreviewView.swift
//  FastStyleTransferDemo
//
//  Created by Arthur Tonelli on 5/8/20.
//  Copyright © 2020 Arthur Tonelli. All rights reserved.
//

import CoreMedia
import Metal
import MetalKit
import MetalPerformanceShaders

class MetalPreviewView: MTKView {
        
    var pixelBuffer: CVPixelBuffer? {
        didSet {
            syncQueue.sync {
                internalPixelBuffer = pixelBuffer
            }
        }
    }
    
    private var internalPixelBuffer: CVPixelBuffer?
    
    private let syncQueue = DispatchQueue(label: "PreviewViewSyncQueue", qos: .userInitiated, attributes: [], autoreleaseFrequency: .workItem)
    
    private var textureCache: CVMetalTextureCache?
    
    private var textureWidth: Int = 0
    
    private var textureHeight: Int = 0
    
    private var textureMirroring = false
        
    private var sampler: MTLSamplerState!
    
    private var renderPipelineState: MTLRenderPipelineState!
    
    private var computePipelineState: MTLComputePipelineState
    
//    private let metalDevice = MTLCreateSystemDefaultDevice()!
    
    private var commandQueue: MTLCommandQueue?
    
//    private var vertexCoordBuffer: MTLBuffer!
//
//    private var textCoordBuffer: MTLBuffer!
    
    private var internalBounds: CGRect!
    
    private var textureTranform: CGAffineTransform?
    
    var pipelineState: MTLComputePipelineState?
    
    let filter: MPSImageLanczosScale
    
    let url: URL
    public var recorder: MetalVideoRecorder
    
    // Prepare output texture
    var inW: Int
    var inH: Int
    
    var outW: Int
    var outH: Int
//    lazy var outW = Int(1128)
//    lazy var outH = Int(1504)
    
    var sf: Float
    lazy var bytesPerPixel = 2
    lazy var outP = self.outW * self.bytesPerPixel
    var outTextureDescriptor: MTLTextureDescriptor

    // Set constants
//    lazy var constants = MTLFunctionConstantValues()
    
    
    // MARK: - Dumb stuf for clipboard/no camera usage
    var shouldUseClipboardImage: Bool = false {
           didSet {
               if shouldUseClipboardImage {
                   if imageView.superview == nil {
                       addSubview(imageView)
                       let constraints = [
                           NSLayoutConstraint(item: imageView, attribute: .top,
                                              relatedBy: .equal,
                                              toItem: self, attribute: .top,
                                              multiplier: 1, constant: 0),
                           NSLayoutConstraint(item: imageView, attribute: .leading,
                                              relatedBy: .equal,
                                              toItem: self, attribute: .leading,
                                              multiplier: 1, constant: 0),
                           NSLayoutConstraint(item: imageView, attribute: .trailing,
                                              relatedBy: .equal,
                                              toItem: self, attribute: .trailing,
                                              multiplier: 1, constant: 0),
                           NSLayoutConstraint(item: imageView, attribute: .bottom,
                                              relatedBy: .equal,
                                              toItem: self, attribute: .bottom,
                                              multiplier: 1, constant: 0),
                       ]
                       addConstraints(constraints)
                   }
               } else {
                   imageView.removeFromSuperview()
               }
               
           }
       }
    
    lazy private var imageView: UIImageView = {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFill
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()
    
    var image: UIImage? {
        get {
            return imageView.image
        }
        set {
            imageView.image = newValue
        }
    }
    
    func viewPointForTexture(point: CGPoint) -> CGPoint? {
        var result: CGPoint?
        guard let transform = textureTranform?.inverted() else {
            return result
        }
        let transformPoint = point.applying(transform)
        
        if internalBounds.contains(transformPoint) {
            result = transformPoint
        } else {
            print("Invalid point \(point) result point \(transformPoint)")
        }
        
        return result
    }
    
    func flushTextureCache() {
        textureCache = nil
    }
    
    required init(coder: NSCoder) {

        let metalDevice = MTLCreateSystemDefaultDevice()!
        let mFilter = MPSImageLanczosScale(device: metalDevice)
        
        let bundle = Bundle.main
        let url = bundle.url(forResource: "default", withExtension: "metallib")
        let library = try! metalDevice.makeLibrary(filepath: url!.path)
        
        let function = library.makeFunction(name: "colorKernel")!
        self.computePipelineState = try! metalDevice.makeComputePipelineState(function: function)
    
        
        var pinW = Int(375)
        var pinH = Int(754)
        
        var poutW = Int(1128)
        var poutH = Int(1504)
        
//        poutW = pinW * 2
//        poutH = pinH * 2
        
        var psf = Float(poutH) / Float(pinH)
        psf = Float(1)
        var pbytesPerPixel = 2
        var poutP = poutW * pbytesPerPixel
        var outTextureDescriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: MTLPixelFormat.rgba8Unorm, width: poutW, height: poutH, mipmapped: false)
        var constants = MTLFunctionConstantValues()
        
        constants.setConstantValue(&psf,   type: MTLDataType.float, index: 0)
        constants.setConstantValue(&pinW,  type: MTLDataType.uint,  index: 1)
        constants.setConstantValue(&pinH,  type: MTLDataType.uint,  index: 2)
        constants.setConstantValue(&poutW, type: MTLDataType.uint,  index: 3)
        constants.setConstantValue(&poutH, type: MTLDataType.uint,  index: 4)
        constants.setConstantValue(&poutP, type: MTLDataType.uint,  index: 5)
        
        let sampleMain = try! library.makeFunction(name: "BicubicMain", constantValues: constants)
        let pipeline = try! metalDevice.makeComputePipelineState(function: sampleMain)
        
        self.filter = mFilter
        self.outTextureDescriptor = outTextureDescriptor
        
        self.inW = pinW
        self.inH = pinH
        self.outW = poutW
        self.outH = poutH
        self.sf = psf
        
//        var purl = URL(string: "com/arthur.fst.videos")!
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        var purl = paths[0].appendingPathComponent("output.mp4")
        print(purl.absoluteString)
        
        if FileManager.default.fileExists(atPath: purl.path) {
            do {
                try FileManager.default.removeItem(atPath: purl.path)
            } catch {
                fatalError("Unable to delete file: \(error) : \(#function).")
            }
        }
//        print(FileManager.default.createFile(atPath: purl.path, contents: nil, attributes: nil))
        print(FileManager.default.fileExists(atPath: purl.path))
        self.url = purl
        
        self.recorder = MetalVideoRecorder(outputURL: purl, size: CGSize(width: 1080, height: 1920))!

        super.init(coder: coder)

        self.preferredFramesPerSecond = 15
        
        self.device = metalDevice
        print("Should have created Metal Device")
        print(self.device)
        
        self.commandQueue = {
            return self.device!.makeCommandQueue()
        }()
        
        configureMetal()
        
        createTextureCache()
        
        self.pipelineState = pipeline
        
        colorPixelFormat = .bgra8Unorm
        
        self.framebufferOnly = false
        self.autoResizeDrawable = true
        self.contentMode = .scaleToFill
//        self.contentMode = .center
        self.contentScaleFactor = UIScreen.main.scale
    }
    
    func configureMetal() {
        let defaultLibrary = device!.makeDefaultLibrary()!
        let pipelineDescriptor = MTLRenderPipelineDescriptor()
        pipelineDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        pipelineDescriptor.vertexFunction = defaultLibrary.makeFunction(name: "vertexPassThrough")
        pipelineDescriptor.fragmentFunction = defaultLibrary.makeFunction(name: "fragmentPassThrough")
        
        // To determine how textures are sampled, create a sampler descriptor to query for a sampler state from the device.
        let samplerDescriptor = MTLSamplerDescriptor()
        samplerDescriptor.sAddressMode = .clampToZero
        samplerDescriptor.tAddressMode = .clampToZero
        samplerDescriptor.minFilter = .linear
        samplerDescriptor.magFilter = .linear
        sampler = device!.makeSamplerState(descriptor: samplerDescriptor)
        
        do {
            renderPipelineState = try device!.makeRenderPipelineState(descriptor: pipelineDescriptor)
        } catch {
            fatalError("Unable to create preview Metal view pipeline state. (\(error))")
        }
        
        commandQueue = device!.makeCommandQueue()
    }
    
    func createTextureCache() {
        var newTextureCache: CVMetalTextureCache?
        if CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, device!, nil, &newTextureCache) == kCVReturnSuccess {
            textureCache = newTextureCache
        } else {
            assertionFailure("Unable to allocate texture cache")
        }
    }
    
    
    /// - Tag: DrawMetalTexture
    override func draw(_ rect: CGRect) {
//        print(rect)
        
        var pBuffer: CVPixelBuffer?
        
        syncQueue.sync {
            pBuffer = internalPixelBuffer
        }
        
        guard let drawable = currentDrawable,
            let currentRenderPassDescriptor = currentRenderPassDescriptor,
            let previewPixelBuffer = pBuffer else {
                print("did not get drawable")
                return
        }
                
        // Create a Metal texture from the image buffer.
        let width = CVPixelBufferGetWidth(previewPixelBuffer)
        let height = CVPixelBufferGetHeight(previewPixelBuffer)
        
//        let width = Int(self.frame.size.width)
//        let height = Int(self.frame.size.height)
        
        if textureCache == nil {
            createTextureCache()
        }
        var cvTextureOut: CVMetalTexture?

        
        guard let ioSurfaceBacked = previewPixelBuffer.copyToMetalCompatible() else {
            print("could not back pixel buffer with iosurface")
            return
        }


        let res = CVMetalTextureCacheCreateTextureFromImage(kCFAllocatorDefault,
                                                  textureCache!,
//                                                  previewPixelBuffer,
                                                  ioSurfaceBacked,
                                                  nil,
                                                  .bgra8Unorm,
//                                                  outW,
//                                                  outH,
                                                  width,
                                                  height,
                                                  0,
                                                  &cvTextureOut)

        guard let cvTexture = cvTextureOut else {
            print("Failed to set cvTexture from - \(cvTextureOut)")
            
            CVMetalTextureCacheFlush(textureCache!, 0)
            return
        }
        
        guard var texture = CVMetalTextureGetTexture(cvTexture) else {
            print("Failed to create preview texture from \(cvTexture)")
            
            CVMetalTextureCacheFlush(textureCache!, 0)
            return
        }
        
        
//        print("texuter - w: \(texture.width), h: \(texture.height)")
        
        // Set up command buffer and encoder
        guard let commandQueue = commandQueue else {
            print("Failed to create Metal command queue")
            CVMetalTextureCacheFlush(textureCache!, 0)
            return
        }
        
        guard let commandBuffer = commandQueue.makeCommandBuffer() else {
            print("Failed to create Metal command buffer")
            CVMetalTextureCacheFlush(textureCache!, 0)
            return
        }
        
        guard let sizeCommandBuffer = commandQueue.makeCommandBuffer() else {
            print("Failed to create Metal sizer command buffer")
            CVMetalTextureCacheFlush(textureCache!, 0)
            return
        }
        
        guard let computeCommandEncoder = commandBuffer.makeComputeCommandEncoder() else {
            print("Falied to make command encoder from command buffer")
            return
        }
        
        commandBuffer.addCompletedHandler { commandBuffer in
            self.recorder.writeFrame(forTexture: texture)
        }
    
        
        // TOGGGLE
//        // Set the compute pipeline state for the command encoder.
        computeCommandEncoder.setComputePipelineState(computePipelineState)
        
        // Set the compute pipeline state for the command encoder.
//        computeCommandEncoder.setComputePipelineState(pipelineState!)
        
        // Set the input and output textures for the compute shader.
//        computeCommandEncoder.setTexture(destTexture, index: 0)
        computeCommandEncoder.setTexture(texture, index: 0)
        computeCommandEncoder.setTexture(drawable.texture, index: 1)
        


        // Encode a threadgroup's execution of a compute function
        computeCommandEncoder.dispatchThreadgroups(texture.threadGroups(), threadsPerThreadgroup: texture.threadGroupCount())

        // End the encoding of the command.
        computeCommandEncoder.endEncoding()
        
        // Draw to the screen.
//        print("drawable size: w - \(drawable.texture.width) h - \(drawable.texture.height)")
        
//        let textDesc = texture2DDescriptor(pixelFormat: MTLPixelFormat.bgra8Unorm, width: outW, height: outH, mipmapped: Bool)
        commandBuffer.present(drawable)
        commandBuffer.commit()

    }
}

