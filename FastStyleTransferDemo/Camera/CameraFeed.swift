//
//  CameraFeed.swift
//  FastStyleTransferDemo
//
//  Created by Arthur Tonelli on 4/13/20.
//  Copyright © 2020 Arthur Tonelli. All rights reserved.
//

import AVFoundation
import UIKit

// interface in normal programming
protocol CameraFeedManagerDelegate: AVCaptureVideoDataOutputSampleBufferDelegate {
    override func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection)
        
    func presentCameraPermissionsDeniedAlert()
    
    func presentVideoConfigurationErrorAlert()
    
    func sessionRunTimeErrorOccured()
    
    func sessionWasInterrupted(canResumeManually resumeManually: Bool)
    
    func sessionInterruptionEnded()
}

enum CameraConfiguration {
    case success
    case failed
    case permissionDenied
}

class CameraFeedManager: NSObject {
        
    private var videoDeviceInput: AVCaptureDeviceInput!
    
    private let dataOutputQueue = DispatchQueue(label: "VideoDataQueue", qos: .userInitiated, attributes: [], autoreleaseFrequency: .workItem)
        
    private let session: AVCaptureSession = AVCaptureSession()
    private let previewView: MetalPreviewView
    private let viewWidth: CGFloat
    private let viewHeight: CGFloat
    // Communicate with the session and other session objects on this queue.
    private let sessionQueue = DispatchQueue(label: "sessionQueue")
    private var cameraConfiguration: CameraConfiguration = .failed
    private lazy var videoDataOutput = AVCaptureVideoDataOutput()

    private var isSessionRunning = false
    
    weak var delegate: CameraFeedManagerDelegate?
    
//    init(previewView: PreviewView) {
    init(previewView: MetalPreviewView) {
        self.previewView = previewView
        self.viewWidth = previewView.bounds.size.width
        self.viewHeight = previewView.bounds.size.height

        super.init()
        
        session.sessionPreset = .high
//        self.previewView.session = session
//        self.previewView.previewLayer.connection?.videoOrientation = .portrait
//        self.previewView.previewLayer.videoGravity = .resizeAspectFill
        self.attemptToConfigureSession()
    }
    
    func checkCameraConfigurationAndStartSession() {
        sessionQueue.async {
            switch self.cameraConfiguration {
            case .success:
                self.addObservers()
                self.startSession()
            case .failed:
                DispatchQueue.main.async {
                    self.delegate?.presentVideoConfigurationErrorAlert()
                }
            case .permissionDenied:
                DispatchQueue.main.async {
                    self.delegate?.presentCameraPermissionsDeniedAlert()
                }
            }
        }
    }
    
    func stopSession() {
        self.removeObservers()
        sessionQueue.async {
            if self.session.isRunning {
                self.session.stopRunning()
                self.isSessionRunning = self.session.isRunning
            }
        }
    }
    
    func resumeInterruptedSession(withCompletion completion: @escaping (Bool) -> ()) {
        sessionQueue.async {
            self.startSession()
            
            DispatchQueue.main.async {
                completion(self.isSessionRunning)
            }
        }
    }
    
    private func startSession() {
        self.session.startRunning()
        self.isSessionRunning = self.session.isRunning
    }
    
    
    private func attemptToConfigureSession() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            self.cameraConfiguration = .success
        case .notDetermined:
            self.sessionQueue.suspend()
            self.requestCameraAccess(completion: { (granted) in
                self.sessionQueue.resume()
            })
        case .denied:
            self.cameraConfiguration = .permissionDenied
        default:
            break
        }
        
        self.sessionQueue.async {
            self.configureSession()
        }
    }
    
    private func requestCameraAccess(completion: @escaping (Bool) -> ()) {
        AVCaptureDevice.requestAccess(for: .video) { (granted) in
            if !granted {
                self.cameraConfiguration = .permissionDenied
            } else {
                self.cameraConfiguration = .success
            }
            completion(granted)
        }
    }
    
    private func configureSession() {
        guard cameraConfiguration == .success else {
            return
        }
        session.beginConfiguration()
        
        guard addVideoDeviceInput() else {
            self.session.commitConfiguration()
            self.cameraConfiguration = .failed
            return
        }
        guard addVideoDataOutput() else {
            self.session.commitConfiguration()
            self.cameraConfiguration = .failed
            return
        }
        session.commitConfiguration()
        self.cameraConfiguration = .success
    }
    
    private func addVideoDeviceInput() -> Bool {
        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
            return false
        }
        
        do {
            try camera.lockForConfiguration()
            camera.activeVideoMaxFrameDuration = CMTimeMake(value: 1, timescale: Int32(15))
            camera.activeVideoMinFrameDuration = CMTimeMake(value: 1, timescale: Int32(10))
            camera.unlockForConfiguration()
        } catch let error {
            print("Oops could not set frame rate: \(error)")
        }
//        camera.activeFormat.videoSupportedFrameRateRanges
        
        do {
            let videoDeviceInput = try AVCaptureDeviceInput(device: camera)
            if session.canAddInput(videoDeviceInput) {
                session.addInput(videoDeviceInput)
                return true
            } else {
                return false
            }
        }
        catch {
            fatalError("Cannot create video device input")
        }
    }
    
    private func addVideoDataOutput() -> Bool {
//        let sampleBufferQueue = DispatchQueue(label: "sampleBufferQueue")
//        videoDataOutput.setSampleBufferDelegate(self.delegate, queue: sampleBufferQueue)
        videoDataOutput.setSampleBufferDelegate(self.delegate, queue: dataOutputQueue)
        videoDataOutput.alwaysDiscardsLateVideoFrames = true
        videoDataOutput.videoSettings = [
            String(kCVPixelBufferPixelFormatTypeKey) : kCMPixelFormat_32BGRA
        ]
        
        if session.canAddOutput(videoDataOutput) {
            session.addOutput(videoDataOutput)
            videoDataOutput.connection(with: .video)?.videoOrientation = .portrait
            return true
        }
        return false
    }
    
    private func addObservers() {
        NotificationCenter.default.addObserver(self, selector: #selector(CameraFeedManager.sessionRuntimeErrorOccured(notification:)), name: NSNotification.Name.AVCaptureSessionRuntimeError, object: session)
        NotificationCenter.default.addObserver(self, selector: #selector(CameraFeedManager.sessionWasInterrupted(notification:)), name: NSNotification.Name.AVCaptureSessionWasInterrupted, object: session)
        NotificationCenter.default.addObserver(self, selector: #selector(CameraFeedManager.sessionInterruptionEnded(notification:)), name: NSNotification.Name.AVCaptureSessionInterruptionEnded, object: session)
    }
    
    private func removeObservers() {
        NotificationCenter.default.removeObserver(self, name: NSNotification.Name.AVCaptureSessionRuntimeError, object: session)
        NotificationCenter.default.removeObserver(self, name: NSNotification.Name.AVCaptureSessionWasInterrupted, object: session)
        NotificationCenter.default.removeObserver(self, name: NSNotification.Name.AVCaptureSessionInterruptionEnded, object: session)
    }
    
    @objc func sessionWasInterrupted(notification: Notification) {
        if let userInfoValue = notification.userInfo?[AVCaptureSessionInterruptionReasonKey] as AnyObject?,
            let reasonIntegerValue = userInfoValue.integerValue,
            let reason = AVCaptureSession.InterruptionReason(rawValue: reasonIntegerValue) {
            print("Capture session was interrupted with reason: \(reason)")
            
            var canResumeManually = false
            if reason == .videoDeviceInUseByAnotherClient {
                canResumeManually = true
            } else if reason == .videoDeviceNotAvailableWithMultipleForegroundApps {
                canResumeManually = false
            }
            self.delegate?.sessionWasInterrupted(canResumeManually: canResumeManually)
        }
    }
    
    @objc func sessionInterruptionEnded(notification: Notification) {
        self.delegate?.sessionInterruptionEnded()
    }
    
    @objc func sessionRuntimeErrorOccured(notification: Notification) {
        guard let error = notification.userInfo?[AVCaptureSessionErrorKey] as? AVError else {
            return
        }
        print("Capturesession runtime Error: \(error)")
        if error.code == .mediaServicesWereReset {
            sessionQueue.async {
                if self.isSessionRunning {
                    self.startSession()
                } else {
                    DispatchQueue.main.async {
                        self.delegate?.sessionRunTimeErrorOccured()
                    }
                }
            }
        } else {
            self.delegate?.sessionRunTimeErrorOccured()
        }
    }
    
}

//extension CameraFeedManager: AVCaptureVideoDataOutputSampleBufferDelegate {
//
//    func captureOutput(_ output:AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
//        let pixelBuffer: CVPixelBuffer? = CMSampleBufferGetImageBuffer(sampleBuffer)
//
//        guard let imagePixelBuffer = pixelBuffer else {
//            return
//        }
//
//        delegate?.didOutput(pixelBuffer: imagePixelBuffer)
//    }
//}
