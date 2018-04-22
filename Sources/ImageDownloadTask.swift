//
//  ImageDownloadTask.swift
//  Shared
//
//  Created by Fengwei Liu on 2018/04/01.
//  Copyright © 2018 kAzec. All rights reserved.
//

import UIKit
import Foundation

public final class ImageDownloadTask {
    public typealias DecodingHandler = (_ data: Data, _ sourceURL: URL) -> UIImage?
    public typealias TransformHandler = (_ image: UIImage, _ sourceURL: URL) -> UIImage
    public typealias CompletionHandler = (_ result: ImageDownloadResult, _ sourceURL: URL) -> Void
    
    var data: NSMutableData?
    
    let decodingHandler: DecodingHandler?
    let transformHandler: TransformHandler?
    let completionHandler: CompletionHandler?
    
    public let dataTask: URLSessionDataTask
    
    init(
        decoding: DecodingHandler?,
        transform: TransformHandler?,
        completion: CompletionHandler?,
        dataTask: URLSessionDataTask
    ) {
        decodingHandler = decoding
        transformHandler = transform
        completionHandler = completion
        self.dataTask = dataTask
    }
    
    public func suspend() {
        dataTask.suspend()
    }
    
    public func resume() {
        dataTask.resume()
    }
    
    public func cancel() {
        dataTask.cancel()
    }
    
    func recevie(_ data: Data) {
        if let receivedData = self.data {
            receivedData.append(data)
        } else {
            self.data = NSMutableData(data: data)
        }
    }
}
