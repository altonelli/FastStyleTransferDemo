/*
  Copyright (c) 2017 M.I. Hollemans
  Permission is hereby granted, free of charge, to any person obtaining a copy
  of this software and associated documentation files (the "Software"), to
  deal in the Software without restriction, including without limitation the
  rights to use, copy, modify, merge, publish, distribute, sublicense, and/or
  sell copies of the Software, and to permit persons to whom the Software is
  furnished to do so, subject to the following conditions:
  The above copyright notice and this permission notice shall be included in
  all copies or substantial portions of the Software.
  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
  FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS
  IN THE SOFTWARE.
*/

import Foundation
import Accelerate
import CoreImage

/**
  Creates a RGB pixel buffer of the specified width and height.
*/
public func createPixelBuffer(width: Int, height: Int) -> CVPixelBuffer? {
  var pixelBuffer: CVPixelBuffer?
  let status = CVPixelBufferCreate(nil, width, height,
                                   kCVPixelFormatType_32BGRA, nil,
                                   &pixelBuffer)
  if status != kCVReturnSuccess {
    print("Error: could not create pixel buffer", status)
    return nil
  }
  return pixelBuffer
}

/**
  First crops the pixel buffer, then resizes it.
  - Note: The new CVPixelBuffer is not backed by an IOSurface and therefore
    cannot be turned into a Metal texture.
*/
public func resizePixelBuffer(_ srcPixelBuffer: CVPixelBuffer,
                              cropX: Int,
                              cropY: Int,
                              cropWidth: Int,
                              cropHeight: Int,
                              scaleWidth: Int,
                              scaleHeight: Int) -> CVPixelBuffer? {
  let flags = CVPixelBufferLockFlags(rawValue: 0)
  guard kCVReturnSuccess == CVPixelBufferLockBaseAddress(srcPixelBuffer, flags) else {
    return nil
  }
  defer { CVPixelBufferUnlockBaseAddress(srcPixelBuffer, flags) }

  guard let srcData = CVPixelBufferGetBaseAddress(srcPixelBuffer) else {
    print("Error: could not get pixel buffer base address")
    return nil
  }
  let srcBytesPerRow = CVPixelBufferGetBytesPerRow(srcPixelBuffer)
  let offset = cropY*srcBytesPerRow + cropX*4
  var srcBuffer = vImage_Buffer(data: srcData.advanced(by: offset),
                                height: vImagePixelCount(cropHeight),
                                width: vImagePixelCount(cropWidth),
                                rowBytes: srcBytesPerRow)

  let destBytesPerRow = scaleWidth*4
  guard let destData = malloc(scaleHeight*destBytesPerRow) else {
    print("Error: out of memory")
    return nil
  }
  var destBuffer = vImage_Buffer(data: destData,
                                 height: vImagePixelCount(scaleHeight),
                                 width: vImagePixelCount(scaleWidth),
                                 rowBytes: destBytesPerRow)

  let error = vImageScale_ARGB8888(&srcBuffer, &destBuffer, nil, vImage_Flags(0))
  if error != kvImageNoError {
    print("Error:", error)
    free(destData)
    return nil
  }

  let releaseCallback: CVPixelBufferReleaseBytesCallback = { _, ptr in
    if let ptr = ptr {
      free(UnsafeMutableRawPointer(mutating: ptr))
    }
  }
    
//    let pixelBufferAttributes: CFDictionary = [
//      kCVPixelBufferMetalCompatibilityKey as String: true,
//      kCVPixelBufferOpenGLESTextureCacheCompatibilityKey as String: true,
//      kCVPixelBufferOpenGLCompatibilityKey as String: true,
//      kCVPixelBufferIOSurfacePropertiesKey as String: [
////      "IOSurfaceOpenGLESFBOCompatibility": true,
////      "IOSurfaceOpenGLESTextureCompatibility": true,
////      "IOSurfaceCoreAnimationCompatibility": true,
//      ]
//    ] as CFDictionary

  let pixelFormat = CVPixelBufferGetPixelFormatType(srcPixelBuffer)
  var dstPixelBuffer: CVPixelBuffer?
  let status = CVPixelBufferCreateWithBytes(nil, scaleWidth, scaleHeight,
                                            pixelFormat, destData,
                                            destBytesPerRow, releaseCallback,
                                            nil,
                                            nil,
//                                            pixelBufferAttributes,
                                            &dstPixelBuffer)
  if status != kCVReturnSuccess {
    print("Error: could not create new pixel buffer")
    free(destData)
    return nil
  }
 
  return dstPixelBuffer
}

/**
  Resizes a CVPixelBuffer to a new width and height.
  - Note: The new CVPixelBuffer is not backed by an IOSurface and therefore
    cannot be turned into a Metal texture.
*/
public func resizePixelBufferArthur(_ pixelBuffer: CVPixelBuffer,
                                    width: Int, height: Int, ioSurface: IOSurface?) -> CVPixelBuffer? {
  return resizePixelBuffer(pixelBuffer, cropX: 0, cropY: 0,
                           cropWidth: CVPixelBufferGetWidth(pixelBuffer),
                           cropHeight: CVPixelBufferGetHeight(pixelBuffer),
                           scaleWidth: width, scaleHeight: height)
}

/**
  Resizes a CVPixelBuffer to a new width and height.
*/
public func resizePixelBuffer(_ pixelBuffer: CVPixelBuffer,
                              width: Int, height: Int,
                              output: CVPixelBuffer, context: CIContext) {
  let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
  let sx = CGFloat(width) / CGFloat(CVPixelBufferGetWidth(pixelBuffer))
  let sy = CGFloat(height) / CGFloat(CVPixelBufferGetHeight(pixelBuffer))
  let scaleTransform = CGAffineTransform(scaleX: sx, y: sy)
  let scaledImage = ciImage.transformed(by: scaleTransform)
  context.render(scaledImage, to: output)
}

/**
  Rotates CVPixelBuffer by the provided factor of 90 counterclock-wise.
  - Note: The new CVPixelBuffer is not backed by an IOSurface and therefore
    cannot be turned into a Metal texture.
*/
public func rotate90PixelBuffer(_ srcPixelBuffer: CVPixelBuffer, factor: UInt8) -> CVPixelBuffer? {
  let flags = CVPixelBufferLockFlags(rawValue: 0)
  guard kCVReturnSuccess == CVPixelBufferLockBaseAddress(srcPixelBuffer, flags) else {
    return nil
  }
  defer { CVPixelBufferUnlockBaseAddress(srcPixelBuffer, flags) }

  guard let srcData = CVPixelBufferGetBaseAddress(srcPixelBuffer) else {
    print("Error: could not get pixel buffer base address")
    return nil
  }
  let sourceWidth = CVPixelBufferGetWidth(srcPixelBuffer)
  let sourceHeight = CVPixelBufferGetHeight(srcPixelBuffer)
  var destWidth = sourceHeight
  var destHeight = sourceWidth
  var color = UInt8(0)

  if factor % 2 == 0 {
    destWidth = sourceWidth
    destHeight = sourceHeight
  }

  let srcBytesPerRow = CVPixelBufferGetBytesPerRow(srcPixelBuffer)
  var srcBuffer = vImage_Buffer(data: srcData,
                                height: vImagePixelCount(sourceHeight),
                                width: vImagePixelCount(sourceWidth),
                                rowBytes: srcBytesPerRow)

  let destBytesPerRow = destWidth*4
  guard let destData = malloc(destHeight*destBytesPerRow) else {
    print("Error: out of memory")
    return nil
  }
  var destBuffer = vImage_Buffer(data: destData,
                                 height: vImagePixelCount(destHeight),
                                 width: vImagePixelCount(destWidth),
                                 rowBytes: destBytesPerRow)

  let error = vImageRotate90_ARGB8888(&srcBuffer, &destBuffer, factor, &color, vImage_Flags(0))
  if error != kvImageNoError {
    print("Error:", error)
    free(destData)
    return nil
  }

  let releaseCallback: CVPixelBufferReleaseBytesCallback = { _, ptr in
    if let ptr = ptr {
      free(UnsafeMutableRawPointer(mutating: ptr))
    }
  }

  let pixelFormat = CVPixelBufferGetPixelFormatType(srcPixelBuffer)
  var dstPixelBuffer: CVPixelBuffer?
  let status = CVPixelBufferCreateWithBytes(nil, destWidth, destHeight,
                                            pixelFormat, destData,
                                            destBytesPerRow, releaseCallback,
                                            nil, nil, &dstPixelBuffer)
  if status != kCVReturnSuccess {
    print("Error: could not create new pixel buffer")
    free(destData)
    return nil
  }
  return dstPixelBuffer
}

public extension CVPixelBuffer {
  /**
    Copies a CVPixelBuffer to a new CVPixelBuffer that is compatible with Metal.
    - Tip: If CVMetalTextureCacheCreateTextureFromImage is failing, then call
      this method first!
  */
  func copyToMetalCompatible() -> CVPixelBuffer? {
    // Other possible options:
    //   String(kCVPixelBufferOpenGLCompatibilityKey): true,
    //   String(kCVPixelBufferIOSurfacePropertiesKey): [
    //     "IOSurfaceOpenGLESFBOCompatibility": true,
    //     "IOSurfaceOpenGLESTextureCompatibility": true,
    //     "IOSurfaceCoreAnimationCompatibility": true
    //   ]
    let attributes: [String: Any] = [
      String(kCVPixelBufferMetalCompatibilityKey): true,
    ]
    return deepCopy(withAttributes: attributes)
  }

  /**
    Copies a CVPixelBuffer to a new CVPixelBuffer.
    This lets you specify new attributes, such as whether the new CVPixelBuffer
    must be IOSurface-backed.
    See: https://developer.apple.com/library/archive/qa/qa1781/_index.html
  */
  func deepCopy(withAttributes attributes: [String: Any] = [:]) -> CVPixelBuffer? {
    let srcPixelBuffer = self
    let srcFlags: CVPixelBufferLockFlags = .readOnly
    guard kCVReturnSuccess == CVPixelBufferLockBaseAddress(srcPixelBuffer, srcFlags) else {
      return nil
    }
    defer { CVPixelBufferUnlockBaseAddress(srcPixelBuffer, srcFlags) }

    var combinedAttributes: [String: Any] = [:]

    // Copy attachment attributes.
    if let attachments = CVBufferGetAttachments(srcPixelBuffer, .shouldPropagate) as? [String: Any] {
      for (key, value) in attachments {
        combinedAttributes[key] = value
      }
    }

    // Add user attributes.
    combinedAttributes = combinedAttributes.merging(attributes) { $1 }

    var maybePixelBuffer: CVPixelBuffer?
    let status = CVPixelBufferCreate(kCFAllocatorDefault,
                                     CVPixelBufferGetWidth(srcPixelBuffer),
                                     CVPixelBufferGetHeight(srcPixelBuffer),
                                     CVPixelBufferGetPixelFormatType(srcPixelBuffer),
                                     combinedAttributes as CFDictionary,
                                     &maybePixelBuffer)

    guard status == kCVReturnSuccess, let dstPixelBuffer = maybePixelBuffer else {
      return nil
    }

    let dstFlags = CVPixelBufferLockFlags(rawValue: 0)
    guard kCVReturnSuccess == CVPixelBufferLockBaseAddress(dstPixelBuffer, dstFlags) else {
      return nil
    }
    defer { CVPixelBufferUnlockBaseAddress(dstPixelBuffer, dstFlags) }

    for plane in 0...max(0, CVPixelBufferGetPlaneCount(srcPixelBuffer) - 1) {
      if let srcAddr = CVPixelBufferGetBaseAddressOfPlane(srcPixelBuffer, plane),
         let dstAddr = CVPixelBufferGetBaseAddressOfPlane(dstPixelBuffer, plane) {
        let srcBytesPerRow = CVPixelBufferGetBytesPerRowOfPlane(srcPixelBuffer, plane)
        let dstBytesPerRow = CVPixelBufferGetBytesPerRowOfPlane(dstPixelBuffer, plane)

        for h in 0..<CVPixelBufferGetHeightOfPlane(srcPixelBuffer, plane) {
          let srcPtr = srcAddr.advanced(by: h*srcBytesPerRow)
          let dstPtr = dstAddr.advanced(by: h*dstBytesPerRow)
          dstPtr.copyMemory(from: srcPtr, byteCount: srcBytesPerRow)
        }
      }
    }
    return dstPixelBuffer
  }
}


public func CVPixelBufferGetPixelFormatName(pixelBuffer: CVPixelBuffer) -> String {
    let p = CVPixelBufferGetPixelFormatType(pixelBuffer)
    switch p {
    case kCVPixelFormatType_1Monochrome:                   return "kCVPixelFormatType_1Monochrome"
    case kCVPixelFormatType_2Indexed:                      return "kCVPixelFormatType_2Indexed"
    case kCVPixelFormatType_4Indexed:                      return "kCVPixelFormatType_4Indexed"
    case kCVPixelFormatType_8Indexed:                      return "kCVPixelFormatType_8Indexed"
    case kCVPixelFormatType_1IndexedGray_WhiteIsZero:      return "kCVPixelFormatType_1IndexedGray_WhiteIsZero"
    case kCVPixelFormatType_2IndexedGray_WhiteIsZero:      return "kCVPixelFormatType_2IndexedGray_WhiteIsZero"
    case kCVPixelFormatType_4IndexedGray_WhiteIsZero:      return "kCVPixelFormatType_4IndexedGray_WhiteIsZero"
    case kCVPixelFormatType_8IndexedGray_WhiteIsZero:      return "kCVPixelFormatType_8IndexedGray_WhiteIsZero"
    case kCVPixelFormatType_16BE555:                       return "kCVPixelFormatType_16BE555"
    case kCVPixelFormatType_16LE555:                       return "kCVPixelFormatType_16LE555"
    case kCVPixelFormatType_16LE5551:                      return "kCVPixelFormatType_16LE5551"
    case kCVPixelFormatType_16BE565:                       return "kCVPixelFormatType_16BE565"
    case kCVPixelFormatType_16LE565:                       return "kCVPixelFormatType_16LE565"
    case kCVPixelFormatType_24RGB:                         return "kCVPixelFormatType_24RGB"
    case kCVPixelFormatType_24BGR:                         return "kCVPixelFormatType_24BGR"
    case kCVPixelFormatType_32ARGB:                        return "kCVPixelFormatType_32ARGB"
    case kCVPixelFormatType_32BGRA:                        return "kCVPixelFormatType_32BGRA"
    case kCVPixelFormatType_32ABGR:                        return "kCVPixelFormatType_32ABGR"
    case kCVPixelFormatType_32RGBA:                        return "kCVPixelFormatType_32RGBA"
    case kCVPixelFormatType_64ARGB:                        return "kCVPixelFormatType_64ARGB"
    case kCVPixelFormatType_48RGB:                         return "kCVPixelFormatType_48RGB"
    case kCVPixelFormatType_32AlphaGray:                   return "kCVPixelFormatType_32AlphaGray"
    case kCVPixelFormatType_16Gray:                        return "kCVPixelFormatType_16Gray"
    case kCVPixelFormatType_30RGB:                         return "kCVPixelFormatType_30RGB"
    case kCVPixelFormatType_422YpCbCr8:                    return "kCVPixelFormatType_422YpCbCr8"
    case kCVPixelFormatType_4444YpCbCrA8:                  return "kCVPixelFormatType_4444YpCbCrA8"
    case kCVPixelFormatType_4444YpCbCrA8R:                 return "kCVPixelFormatType_4444YpCbCrA8R"
    case kCVPixelFormatType_4444AYpCbCr8:                  return "kCVPixelFormatType_4444AYpCbCr8"
    case kCVPixelFormatType_4444AYpCbCr16:                 return "kCVPixelFormatType_4444AYpCbCr16"
    case kCVPixelFormatType_444YpCbCr8:                    return "kCVPixelFormatType_444YpCbCr8"
    case kCVPixelFormatType_422YpCbCr16:                   return "kCVPixelFormatType_422YpCbCr16"
    case kCVPixelFormatType_422YpCbCr10:                   return "kCVPixelFormatType_422YpCbCr10"
    case kCVPixelFormatType_444YpCbCr10:                   return "kCVPixelFormatType_444YpCbCr10"
    case kCVPixelFormatType_420YpCbCr8Planar:              return "kCVPixelFormatType_420YpCbCr8Planar"
    case kCVPixelFormatType_420YpCbCr8PlanarFullRange:     return "kCVPixelFormatType_420YpCbCr8PlanarFullRange"
    case kCVPixelFormatType_422YpCbCr_4A_8BiPlanar:        return "kCVPixelFormatType_422YpCbCr_4A_8BiPlanar"
    case kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange:  return "kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange"
    case kCVPixelFormatType_420YpCbCr8BiPlanarFullRange:   return "kCVPixelFormatType_420YpCbCr8BiPlanarFullRange"
    case kCVPixelFormatType_422YpCbCr8_yuvs:               return "kCVPixelFormatType_422YpCbCr8_yuvs"
    case kCVPixelFormatType_422YpCbCr8FullRange:           return "kCVPixelFormatType_422YpCbCr8FullRange"
    case kCVPixelFormatType_OneComponent8:                 return "kCVPixelFormatType_OneComponent8"
    case kCVPixelFormatType_TwoComponent8:                 return "kCVPixelFormatType_TwoComponent8"
    case kCVPixelFormatType_30RGBLEPackedWideGamut:        return "kCVPixelFormatType_30RGBLEPackedWideGamut"
    case kCVPixelFormatType_OneComponent16Half:            return "kCVPixelFormatType_OneComponent16Half"
    case kCVPixelFormatType_OneComponent32Float:           return "kCVPixelFormatType_OneComponent32Float"
    case kCVPixelFormatType_TwoComponent16Half:            return "kCVPixelFormatType_TwoComponent16Half"
    case kCVPixelFormatType_TwoComponent32Float:           return "kCVPixelFormatType_TwoComponent32Float"
    case kCVPixelFormatType_64RGBAHalf:                    return "kCVPixelFormatType_64RGBAHalf"
    case kCVPixelFormatType_128RGBAFloat:                  return "kCVPixelFormatType_128RGBAFloat"
    case kCVPixelFormatType_14Bayer_GRBG:                  return "kCVPixelFormatType_14Bayer_GRBG"
    case kCVPixelFormatType_14Bayer_RGGB:                  return "kCVPixelFormatType_14Bayer_RGGB"
    case kCVPixelFormatType_14Bayer_BGGR:                  return "kCVPixelFormatType_14Bayer_BGGR"
    case kCVPixelFormatType_14Bayer_GBRG:                  return "kCVPixelFormatType_14Bayer_GBRG"
    default: return "UNKNOWN"
    }
}

extension CVPixelBuffer {
    
    func pixelFormatName() -> String {
        let p = CVPixelBufferGetPixelFormatType(self)
        switch p {
        case kCVPixelFormatType_1Monochrome:                   return "kCVPixelFormatType_1Monochrome"
        case kCVPixelFormatType_2Indexed:                      return "kCVPixelFormatType_2Indexed"
        case kCVPixelFormatType_4Indexed:                      return "kCVPixelFormatType_4Indexed"
        case kCVPixelFormatType_8Indexed:                      return "kCVPixelFormatType_8Indexed"
        case kCVPixelFormatType_1IndexedGray_WhiteIsZero:      return "kCVPixelFormatType_1IndexedGray_WhiteIsZero"
        case kCVPixelFormatType_2IndexedGray_WhiteIsZero:      return "kCVPixelFormatType_2IndexedGray_WhiteIsZero"
        case kCVPixelFormatType_4IndexedGray_WhiteIsZero:      return "kCVPixelFormatType_4IndexedGray_WhiteIsZero"
        case kCVPixelFormatType_8IndexedGray_WhiteIsZero:      return "kCVPixelFormatType_8IndexedGray_WhiteIsZero"
        case kCVPixelFormatType_16BE555:                       return "kCVPixelFormatType_16BE555"
        case kCVPixelFormatType_16LE555:                       return "kCVPixelFormatType_16LE555"
        case kCVPixelFormatType_16LE5551:                      return "kCVPixelFormatType_16LE5551"
        case kCVPixelFormatType_16BE565:                       return "kCVPixelFormatType_16BE565"
        case kCVPixelFormatType_16LE565:                       return "kCVPixelFormatType_16LE565"
        case kCVPixelFormatType_24RGB:                         return "kCVPixelFormatType_24RGB"
        case kCVPixelFormatType_24BGR:                         return "kCVPixelFormatType_24BGR"
        case kCVPixelFormatType_32ARGB:                        return "kCVPixelFormatType_32ARGB"
        case kCVPixelFormatType_32BGRA:                        return "kCVPixelFormatType_32BGRA"
        case kCVPixelFormatType_32ABGR:                        return "kCVPixelFormatType_32ABGR"
        case kCVPixelFormatType_32RGBA:                        return "kCVPixelFormatType_32RGBA"
        case kCVPixelFormatType_64ARGB:                        return "kCVPixelFormatType_64ARGB"
        case kCVPixelFormatType_48RGB:                         return "kCVPixelFormatType_48RGB"
        case kCVPixelFormatType_32AlphaGray:                   return "kCVPixelFormatType_32AlphaGray"
        case kCVPixelFormatType_16Gray:                        return "kCVPixelFormatType_16Gray"
        case kCVPixelFormatType_30RGB:                         return "kCVPixelFormatType_30RGB"
        case kCVPixelFormatType_422YpCbCr8:                    return "kCVPixelFormatType_422YpCbCr8"
        case kCVPixelFormatType_4444YpCbCrA8:                  return "kCVPixelFormatType_4444YpCbCrA8"
        case kCVPixelFormatType_4444YpCbCrA8R:                 return "kCVPixelFormatType_4444YpCbCrA8R"
        case kCVPixelFormatType_4444AYpCbCr8:                  return "kCVPixelFormatType_4444AYpCbCr8"
        case kCVPixelFormatType_4444AYpCbCr16:                 return "kCVPixelFormatType_4444AYpCbCr16"
        case kCVPixelFormatType_444YpCbCr8:                    return "kCVPixelFormatType_444YpCbCr8"
        case kCVPixelFormatType_422YpCbCr16:                   return "kCVPixelFormatType_422YpCbCr16"
        case kCVPixelFormatType_422YpCbCr10:                   return "kCVPixelFormatType_422YpCbCr10"
        case kCVPixelFormatType_444YpCbCr10:                   return "kCVPixelFormatType_444YpCbCr10"
        case kCVPixelFormatType_420YpCbCr8Planar:              return "kCVPixelFormatType_420YpCbCr8Planar"
        case kCVPixelFormatType_420YpCbCr8PlanarFullRange:     return "kCVPixelFormatType_420YpCbCr8PlanarFullRange"
        case kCVPixelFormatType_422YpCbCr_4A_8BiPlanar:        return "kCVPixelFormatType_422YpCbCr_4A_8BiPlanar"
        case kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange:  return "kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange"
        case kCVPixelFormatType_420YpCbCr8BiPlanarFullRange:   return "kCVPixelFormatType_420YpCbCr8BiPlanarFullRange"
        case kCVPixelFormatType_422YpCbCr8_yuvs:               return "kCVPixelFormatType_422YpCbCr8_yuvs"
        case kCVPixelFormatType_422YpCbCr8FullRange:           return "kCVPixelFormatType_422YpCbCr8FullRange"
        case kCVPixelFormatType_OneComponent8:                 return "kCVPixelFormatType_OneComponent8"
        case kCVPixelFormatType_TwoComponent8:                 return "kCVPixelFormatType_TwoComponent8"
        case kCVPixelFormatType_30RGBLEPackedWideGamut:        return "kCVPixelFormatType_30RGBLEPackedWideGamut"
        case kCVPixelFormatType_OneComponent16Half:            return "kCVPixelFormatType_OneComponent16Half"
        case kCVPixelFormatType_OneComponent32Float:           return "kCVPixelFormatType_OneComponent32Float"
        case kCVPixelFormatType_TwoComponent16Half:            return "kCVPixelFormatType_TwoComponent16Half"
        case kCVPixelFormatType_TwoComponent32Float:           return "kCVPixelFormatType_TwoComponent32Float"
        case kCVPixelFormatType_64RGBAHalf:                    return "kCVPixelFormatType_64RGBAHalf"
        case kCVPixelFormatType_128RGBAFloat:                  return "kCVPixelFormatType_128RGBAFloat"
        case kCVPixelFormatType_14Bayer_GRBG:                  return "kCVPixelFormatType_14Bayer_GRBG"
        case kCVPixelFormatType_14Bayer_RGGB:                  return "kCVPixelFormatType_14Bayer_RGGB"
        case kCVPixelFormatType_14Bayer_BGGR:                  return "kCVPixelFormatType_14Bayer_BGGR"
        case kCVPixelFormatType_14Bayer_GBRG:                  return "kCVPixelFormatType_14Bayer_GBRG"
        default: return "UNKNOWN"
        }
    }
}
