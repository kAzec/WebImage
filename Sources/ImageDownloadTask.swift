//
//  ImageDownloadTask.swift
//  Shared
//
//  Created by Fengwei Liu on 2018/04/01.
//  Copyright © 2018 kAzec. All rights reserved.
//

import UIKit
import Foundation

open class ImageDownloadTask {
    public final let dataTask: URLSessionDataTask
    public final var imageData: Data?
    
    public final var url: URL? {
        return dataTask.originalRequest?.url
    }
    
    public init(request: URLRequest, downloader: ImageDownloader) {
        self.dataTask = downloader.session.dataTask(with: request)
        
        downloader.addTask(self)
    }
    
    public convenience init(url: URL, downloader: ImageDownloader) {
        self.init(request: URLRequest(url: url), downloader: downloader)
    }
    
    open func resume() {
        dataTask.resume()
    }
    
    open func cancel() {
        dataTask.cancel()
    }
    
    open func receive(_ data: Data) {
        if imageData?.append(data) == nil {
            let count = data.count
            imageData = data.withUnsafeBytes { bytes in
                Data(bytes: bytes, count: count)
            }
        }
    }
    
    open func decode(_ data: Data) -> UIImage? {
        return UIImage(data: data)
    }
    
    open func transform(_ image: UIImage) -> UIImage? {
        return nil
    }
    
    open func complete(with result: ImageDownloadResult) { }
}

@_versioned
final class AnyImageDownloadTask : ImageDownloadTask {
    let progressHandler: ProgressHandler?
    let decodingHandler: DecodingHandler?
    let transformHandler: TransformHandler?
    let completionHandler: CompletionHandler?
    
    @_versioned
    init(
        request: URLRequest,
        downloader: ImageDownloader,
        progress progressHandler: ProgressHandler?,
        decoding decodingHandler: DecodingHandler?,
        transform transformHandler: TransformHandler?,
        completion completionHandler: CompletionHandler?
    ) {
        self.progressHandler = progressHandler
        self.decodingHandler = decodingHandler
        self.transformHandler = transformHandler
        self.completionHandler = completionHandler
        
        super.init(request: request, downloader: downloader)
    }
    
    override func receive(_ data: Data) {
        super.receive(data)
        
        if let data = imageData, let handler = progressHandler {
            handler(data, url)
        }
    }
    
    override func decode(_ data: Data) -> UIImage? {
        return decodingHandler?(data, url) ?? super.decode(data)
    }
    
    override func transform(_ image: UIImage) -> UIImage? {
        return transformHandler?(image, url)
    }
    
    override func complete(with result: ImageDownloadResult) {
        completionHandler?(result, url)
    }
}

// MARK: - Type Aliases

public extension ImageDownloadTask {
    typealias ProgressHandler = (_ data: Data, _ url: URL?) -> Void
    typealias DecodingHandler = (_ data: Data, _ url: URL?) -> UIImage?
    typealias TransformHandler = (_ image: UIImage, _ url: URL?) -> UIImage
    typealias CompletionHandler = (_ result: ImageDownloadResult, _ url: URL?) -> Void
}
