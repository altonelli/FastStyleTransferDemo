//
//  ViewController.swift
//  FastStyleTransferDemo
//
//  Created by Arthur Tonelli on 4/15/20.
//  Copyright © 2020 Arthur Tonelli. All rights reserved.
//

import AVFoundation
import UIKit
import Photos


class ViewController: UIViewController {
//    @IBOutlet weak var previewView: PreviewView!
    @IBOutlet weak var previewView: MetalPreviewView!
    @IBOutlet weak var cameraUnavailableLabel: UILabel!
    @IBOutlet weak var resumeButton: UIButton!
    @IBOutlet weak var recordButton: UIButton!
    @IBOutlet weak var bottomSheetView: CurvedView!
    
    @IBOutlet weak var bottomSheetViewBottomSpace: NSLayoutConstraint!
    @IBOutlet weak var bottomSheetStateImageView: UIImageView!
    
    private let animationDuration = 0.5
    private let collapseTransitionThreshold: CGFloat = -40.0
    private let expandTransitionThreshold: CGFloat = 40.0
    private let delayBetweenInferencesMs: Double = 1000
    
    private var recording = false
    
    private var result: Result?
    private var initialBottomSpace: CGFloat = 0.0
    private var previousInferenceTimeMs: TimeInterval = Date.distantPast.timeIntervalSince1970 * 1000
    
    private var cameraCapture: CameraFeedManager!
    
    private var modelDataHandler: ModelDataHandler? = ModelDataHandler(modelFileInfo: MobileNet.modelInfo, labelsFileInfo: MobileNet.labelsInfo)

    
//    private lazy var previewHeight = Int(previewView.bounds.size.height)
//    private lazy var previewWidth = Int(previewView.bounds.size.width)
    
    private lazy var previewHeight = Int(1900)
    private lazy var previewWidth = Int(1128)
    
    private lazy var modelHeight: Int? = modelDataHandler?.sketchInputHeight
    private lazy var modelWidth: Int? = modelDataHandler?.sketchInputWidth
    
    private var inferenceViewController: InferenceViewController?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        print(previewView)
        cameraCapture = CameraFeedManager(previewView: previewView)

        
//        previewHeight = previewView.bounds.size.height
//        previewWidth = previewView.bounds.size.width
        
        guard modelDataHandler != nil else {
            fatalError("Model set up failed")
        }
        
        #if targetEnvironment(simulator)
        previewView.shouldUseClipboardImage = true
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(classifyPasteboardImage),
                                               name: UIApplication.didBecomeActiveNotification,
                                               object: nil)
        #endif
        cameraCapture.delegate = self
        
        addPanGesture()
        

    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        changeBottomViewState()
        
        #if !targetEnvironment(simulator)
        cameraCapture.checkCameraConfigurationAndStartSession()
        #endif
        
        if PHPhotoLibrary.authorizationStatus() == PHAuthorizationStatus.notDetermined {
            PHPhotoLibrary.requestAuthorization({(status: PHAuthorizationStatus) -> Void in
                print("Access granted!")})
        }
    }
    
    #if !targetEnvironment(simulator)
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        cameraCapture.stopSession()
    }
    #endif
    
    func presentUnableToResumeSessionAlert() {
        let alert = UIAlertController(
            title: "Unable to Resume Session",
            message: "There was an error while attempting to resume session.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "OK", style: .default, handler: nil))
        
        self.present(alert, animated: true)
    }
    
    // MARK: Storyboard Segue Handlers
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        super.prepare(for: segue, sender: sender)
        
        if segue.identifier == "EMBED" {
            
            guard let tempModelDataHandler = modelDataHandler else {
                return
            }
            inferenceViewController = segue.destination as? InferenceViewController
            inferenceViewController?.wantedInputHeight = tempModelDataHandler.inputHeight
            inferenceViewController?.wantedInputWidth = tempModelDataHandler.inputWidth
            inferenceViewController?.maxResults = tempModelDataHandler.resultCount
            inferenceViewController?.threadCountLimit = tempModelDataHandler.threadCountLimit
            inferenceViewController?.delegate = self
            
        }
    }
    
    func saveVideoToLibrary(videoURL: URL) {

        PHPhotoLibrary.shared().performChanges({
            print("trying to save video")
            PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: videoURL)
        }) { saved, error in

            if let error = error {
                print("Error saving video to librayr: \(error.localizedDescription)")
            }
            if saved {
                print("Video save to library")

            }
        }
    }
    
    func handler() {
        print("FINISHED!!!!!")
        saveVideoToLibrary(videoURL: previewView.url)
    }
    
    @IBAction func recordButtonPushed(_ sender: UIButton) {
        if (recording == false) {
            print("start recording")
            previewView.recorder.startRecording()
//            recordButton.titleLabel?.text = "Stop"
            sender.setTitle("Stop", for: [])
            recording = true
        } else {
            print("stop recording")
            previewView.recorder.endRecording(handler)
//            recordButton.titleLabel?.text = "Record"
            sender.setTitle("Record", for: [])
            recording = false
        }
    }
    
    
    @objc func classifyPasteboardImage() {
        guard let image = UIPasteboard.general.images?.first else {
            return
        }
        
        guard let buffer = CVImageBuffer.buffer(from: image) else {
            return
        }
        
        previewView.pixelBuffer = buffer

    }
    
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}

extension ViewController: InferenceViewControllerDelegate {
    
    func didChangeThreadCount(to count: Int) {
        print("lol this don do shiiit. count at \(count) though")
//        if modelDataHandler?.threadCount == count { return }
//        modelDataHandler = ModelDataHandler(
//            modelFileInfo: MobileNet.modelInfo,
//            labelsFileInfo: MobileNet.labelsInfo,
//            threadCount: count
//        )
    }
}

extension ViewController: CameraFeedManagerDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        processVideo(sampleBuffer: sampleBuffer)
    }
    
    func processVideo(sampleBuffer: CMSampleBuffer) {
        
        guard let videoPixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return
        }
        
        guard modelWidth != nil, modelHeight != nil, let downsizedBuffer = resizePixelBufferArthur(videoPixelBuffer, width: modelWidth!, height: modelHeight!, ioSurface: nil) else {
            return
        }
        
        var finalVideoPixelBuffer = videoPixelBuffer
        
        if let handler = modelDataHandler {
            guard downsizedBuffer != nil, let res = handler.runModel(onFrame: downsizedBuffer) else {
                print("Run model failed.")
                return
            }
            
            finalVideoPixelBuffer = res.buffer
//            print(res.buffer.)
        }
        
//        let resizedFinalBuffer = resizePixelBufferArthur(finalVideoPixelBuffer, width: previewWidth, height: previewHeight, ioSurface: nil)
        
        let resizedFinalBuffer = finalVideoPixelBuffer
        
//        print("post model img - cgW: \(CVPixelBufferGetWidth(resizedFinalBuffer!)), cgH: \(CVPixelBufferGetHeight(resizedFinalBuffer!))")
        
        previewView.pixelBuffer = resizedFinalBuffer

    }

    
    func sessionWasInterrupted(canResumeManually resumeManually: Bool) {
        if resumeManually {
            self.resumeButton.isHidden = false
        } else {
            self.cameraUnavailableLabel.isHidden = false
        }
    }
    
    func sessionInterruptionEnded() {
        // Updates UI once session interruption has ended.
        if !self.cameraUnavailableLabel.isHidden {
            self.cameraUnavailableLabel.isHidden = true
        }
        
        if !self.resumeButton.isHidden {
            self.resumeButton.isHidden = true
        }
    }
    
    func sessionRunTimeErrorOccured() {
        // Handles session run time error by updating the UI and providing a button if session can be manually resumed.
        self.resumeButton.isHidden = false
        previewView.shouldUseClipboardImage = true
    }
    
    func presentCameraPermissionsDeniedAlert() {
        let alertController = UIAlertController(title: "Camera Permissions Denied", message: "Camera permissions have been denied for this app. You can change this by going to Settings", preferredStyle: .alert)
        
        let cancelAction = UIAlertAction(title: "Cancel", style: .cancel, handler: nil)
        let settingsAction = UIAlertAction(title: "Settings", style: .default) { (action) in
            UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!, options: [:], completionHandler: nil)
        }
        alertController.addAction(cancelAction)
        alertController.addAction(settingsAction)
        
        present(alertController, animated: true, completion: nil)
        
        previewView.shouldUseClipboardImage = true
    }
    
    func presentVideoConfigurationErrorAlert() {
        let alert = UIAlertController(title: "Camera Configuration Failed", message: "There was an error while configuring camera.", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default, handler: nil))
        
        self.present(alert, animated: true)
        previewView.shouldUseClipboardImage = true
    }
}

extension ViewController {
    
    private func addPanGesture() {
        let panGesture = UIPanGestureRecognizer(target: self, action: #selector(ViewController.didPan(panGesture:)))
        bottomSheetView.addGestureRecognizer(panGesture)
    }
    
    
    private func changeBottomViewState() {
        
        guard let inferenceVC = inferenceViewController else {
            return
        }
        
        if bottomSheetViewBottomSpace.constant == inferenceVC.collapsedHeight - bottomSheetView.bounds.size.height {
            bottomSheetViewBottomSpace.constant = 0.0
        }
        else {
            bottomSheetViewBottomSpace.constant = inferenceVC.collapsedHeight - bottomSheetView.bounds.size.height
        }
        setImageBasedOnBottomViewState()
    }
    
    /**
     Set image of the bottom sheet icon based on whether it is expanded or collapsed
     */
    private func setImageBasedOnBottomViewState() {
        
        if bottomSheetViewBottomSpace.constant == 0.0 {
            bottomSheetStateImageView.image = UIImage(named: "down_icon")
        }
        else {
            bottomSheetStateImageView.image = UIImage(named: "up_icon")
        }
    }
    
    /**
     This method responds to the user panning on the bottom sheet.
     */
    @objc func didPan(panGesture: UIPanGestureRecognizer) {
        
        // Opens or closes the bottom sheet based on the user's interaction with the bottom sheet.
        let translation = panGesture.translation(in: view)
        
        switch panGesture.state {
        case .began:
            initialBottomSpace = bottomSheetViewBottomSpace.constant
            translateBottomSheet(withVerticalTranslation: translation.y)
        case .changed:
            translateBottomSheet(withVerticalTranslation: translation.y)
        case .cancelled:
            setBottomSheetLayout(withBottomSpace: initialBottomSpace)
        case .ended:
            translateBottomSheetAtEndOfPan(withVerticalTranslation: translation.y)
            setImageBasedOnBottomViewState()
            initialBottomSpace = 0.0
        default:
            break
        }
    }
    
    /**
     This method sets bottom sheet translation while pan gesture state is continuously changing.
     */
    private func translateBottomSheet(withVerticalTranslation verticalTranslation: CGFloat) {
        
        let bottomSpace = initialBottomSpace - verticalTranslation
        guard bottomSpace <= 0.0 && bottomSpace >= inferenceViewController!.collapsedHeight - bottomSheetView.bounds.size.height else {
            return
        }
        setBottomSheetLayout(withBottomSpace: bottomSpace)
    }
    
    /**
     This method changes bottom sheet state to either fully expanded or closed at the end of pan.
     */
    private func translateBottomSheetAtEndOfPan(withVerticalTranslation verticalTranslation: CGFloat) {
        
        // Changes bottom sheet state to either fully open or closed at the end of pan.
        let bottomSpace = bottomSpaceAtEndOfPan(withVerticalTranslation: verticalTranslation)
        setBottomSheetLayout(withBottomSpace: bottomSpace)
    }
    
    /**
     Return the final state of the bottom sheet view (whether fully collapsed or expanded) that is to be retained.
     */
    private func bottomSpaceAtEndOfPan(withVerticalTranslation verticalTranslation: CGFloat) -> CGFloat {
        
        // Calculates whether to fully expand or collapse bottom sheet when pan gesture ends.
        var bottomSpace = initialBottomSpace - verticalTranslation
        
        var height: CGFloat = 0.0
        if initialBottomSpace == 0.0 {
            height = bottomSheetView.bounds.size.height
        }
        else {
            height = inferenceViewController!.collapsedHeight
        }
        
        let currentHeight = bottomSheetView.bounds.size.height + bottomSpace
        
        if currentHeight - height <= collapseTransitionThreshold {
            bottomSpace = inferenceViewController!.collapsedHeight - bottomSheetView.bounds.size.height
        }
        else if currentHeight - height >= expandTransitionThreshold {
            bottomSpace = 0.0
        }
        else {
            bottomSpace = initialBottomSpace
        }
        
        return bottomSpace
    }
    
    /**
     This method layouts the change of the bottom space of bottom sheet with respect to the view managed by this controller.
     */
    func setBottomSheetLayout(withBottomSpace bottomSpace: CGFloat) {
        
        view.setNeedsLayout()
        bottomSheetViewBottomSpace.constant = bottomSpace
        view.setNeedsLayout()
    }
    
}
