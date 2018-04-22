//
//  ImageDownloadResult.swift
//  Shared
//
//  Created by Fengwei Liu on 2018/04/01.
//  Copyright © 2018 kAzec. All rights reserved.
//

import UIKit
import Foundation

public enum ImageDownloadResult {
    case cancelled
    case networkError(NSError)
    
    case missingData
    case undecodableData(Data)
    
    case decoded(UIImage, from: Data)
}
