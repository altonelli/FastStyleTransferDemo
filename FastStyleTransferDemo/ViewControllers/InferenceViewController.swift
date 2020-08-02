//
//  InferenceViewController.swift
//  FastStyleTransferDemo
//
//  Created by Arthur Tonelli on 4/18/20.
//  Copyright © 2020 Arthur Tonelli. All rights reserved.
//

import UIKit

protocol InferenceViewControllerDelegate {
    func didChangeThreadCount(to count: Int)
}

class InferenceViewController: UIViewController {
    private enum InferenceSections: Int, CaseIterable {
        case Results
        case InferenceInfo
    }
    
    private enum InferenceInfo: Int, CaseIterable {
        case Resolution
        case Crop
        case InferenceTime
        
        func displayString() -> String {
            var toReturn = ""
            
            switch self {
            case .Resolution:
                toReturn = "Resolution"
            case .Crop:
                toReturn = "Crop"
            case .InferenceTime:
                toReturn = "InferenceTime"
            }
            return toReturn
        }
    }
    
    @IBOutlet weak var tableView: UITableView!
    @IBOutlet weak var threadStepper: UIStepper!
    @IBOutlet weak var stepperValueLabel: UILabel!
    
    private let normalCellHeight: CGFloat = 27.0
    private let separatorCellHeight: CGFloat = 42.0
    private let bottomSpacing: CGFloat = 21.0
    private let minThreadCount = 1
    private let bottomSheetButtonDisplayHeight: CGFloat = 44.0
    private let lightTextInfoColor = UIColor(displayP3Red: 117.0/255.0, green: 117.0/255.0, blue: 117.0/255.0, alpha: 1.0)
    private let infoFont = UIFont.systemFont(ofSize: 14.0, weight: .regular)
    private let highlightedFont = UIFont.systemFont(ofSize: 14.0, weight: .medium)
    
    var inferenceResult: Result? = nil
    var wantedInputWidth: Int = 0
    var wantedInputHeight: Int = 0
    var resolution: CGSize = CGSize.zero
    var maxResults: Int = 0
    var threadCountLimit: Int = 0
    private var currentThreadCount: Int = 0
    private var infoTextColor = UIColor.black
    
    var delegate: InferenceViewControllerDelegate?
    var collapsedHeight: CGFloat {
        return normalCellHeight * CGFloat(maxResults - 1) + separatorCellHeight + bottomSheetButtonDisplayHeight
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        threadStepper.isUserInteractionEnabled = true
        threadStepper.maximumValue = Double(threadCountLimit)
        threadStepper.minimumValue = Double(minThreadCount)
        threadStepper.value = Double(currentThreadCount)
        
        if #available(iOS 11, *) {
            infoTextColor = UIColor(named: "darkOrLight")!
        }
    }
    
    @IBAction func onClickThreadStepper(_ sender: Any) {
        delegate?.didChangeThreadCount(to: Int(threadStepper.value))
        currentThreadCount = Int(threadStepper.value)
        stepperValueLabel.text = "\(currentThreadCount)"
    }
}

extension InferenceViewController: UITableViewDelegate, UITableViewDataSource {
    func numberOfSections(in tableView: UITableView) -> Int {
        return InferenceSections.allCases.count
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        guard let inferenceSection = InferenceSections(rawValue: section) else {
            return 0
        }
        
        var rowCount = 0
        switch inferenceSection {
        case .Results:
            rowCount = maxResults
        case .InferenceInfo:
            rowCount = InferenceInfo.allCases.count
        }
        return rowCount
    }
    
    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        
        var height: CGFloat = 0.0
        
        guard let inferenceSection = InferenceSections(rawValue: indexPath.section) else {
            return height
        }
        
        switch inferenceSection {
        case .Results:
            if indexPath.row == maxResults - 1 {
                height = separatorCellHeight + bottomSpacing
            }
            else {
                height = normalCellHeight
            }
        case .InferenceInfo:
            if indexPath.row == InferenceInfo.allCases.count - 1 {
                height = separatorCellHeight + bottomSpacing
            }
            else {
                height = normalCellHeight
            }
        }
        return height
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        
        let cell = tableView.dequeueReusableCell(withIdentifier: "INFO_CELL") as! InfoCell
        
        guard let inferenceSection = InferenceSections(rawValue: indexPath.section) else {
            return cell
        }
        
        var fieldName = ""
        var info = ""
        var font = infoFont
        var color = infoTextColor
        
        switch inferenceSection {
        case .Results:
            
            let tuple = displayStringsForResults(atRow: indexPath.row)
            fieldName = tuple.0
            info = tuple.1
            
            if indexPath.row == 0 {
                font = highlightedFont
                color = infoTextColor
            }
            else {
                font = infoFont
                color = lightTextInfoColor
            }
            
        case .InferenceInfo:
            let tuple = displayStringsForInferenceInfo(atRow: indexPath.row)
            fieldName = tuple.0
            info = tuple.1
            
        }
        cell.fieldNameLabel.font = font
        cell.fieldNameLabel.textColor = color
        cell.fieldNameLabel.text = fieldName
        cell.infoLabel.text = info
        return cell
    }
    
    // MARK: Format Display of information in the bottom sheet
    /**
     This method formats the display of the inferences for the current frame.
     */
    func displayStringsForResults(atRow row: Int) -> (String, String) {
        
        var fieldName: String = ""
        var info: String = ""
        
        guard let tempResult = inferenceResult, tempResult.inferences.count > 0 else {
            
            if row == 1 {
                fieldName = "No Results"
                info = ""
            }
            else {
                fieldName = ""
                info = ""
            }
            return (fieldName, info)
        }
        
        if row < tempResult.inferences.count {
            let inference = tempResult.inferences[row]
            fieldName = inference.label
            info =  String(format: "%.2f", inference.confidence * 100.0) + "%"
        }
        else {
            fieldName = ""
            info = ""
        }
        
        return (fieldName, info)
    }
    
    /**
     This method formats the display of additional information relating to the inferences.
     */
    func displayStringsForInferenceInfo(atRow row: Int) -> (String, String) {
        
        var fieldName: String = ""
        var info: String = ""
        
        guard let inferenceInfo = InferenceInfo(rawValue: row) else {
            return (fieldName, info)
        }
        
        fieldName = inferenceInfo.displayString()
        
        switch inferenceInfo {
        case .Resolution:
            info = "\(Int(resolution.width))x\(Int(resolution.height))"
        case .Crop:
            info = "\(wantedInputWidth)x\(wantedInputHeight)"
        case .InferenceTime:
            guard let finalResults = inferenceResult else {
                info = "0ms"
                break
            }
            info = String(format: "%.2fms", finalResults.inferenceTime)
        }
        
        return(fieldName, info)
    }
}

