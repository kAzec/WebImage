//
//  ImageDownloader.swift
//  Shared
//
//  Created by Fengwei Liu on 28/03/2018.
//  Copyright © 2018 kAzec. All rights reserved.
//

import UIKit
import os.lock
import Foundation

public final class ImageDownloader {
    public typealias DownloadTask = ImageDownloadTask
    public typealias DownloadResult = ImageDownloadResult

    public let session: URLSession
    private(set) weak var delegate: ImageDownloaderDelegate?
    
    private var taskRegistry = TaskRegistry()
    private let delegateQueue: DispatchQueue
    private let processingQueue: DispatchQueue
    private let sessionDelegate: URLSessionDelegateProxy

    public init(
        sessionConfiguration: URLSessionConfiguration,
        delegate: ImageDownloaderDelegate? = nil,
        delegateQueue: DispatchQueue = .main
    ) {
        let sessionDelegate = URLSessionDelegateProxy()
        
        let delegateOperationQueue: OperationQueue
        if delegateQueue === DispatchQueue.main {
            delegateOperationQueue = .main
        } else {
            delegateOperationQueue = OperationQueue()
            delegateOperationQueue.underlyingQueue = delegateQueue
        }
        
        let session = URLSession(
            configuration: sessionConfiguration,
            delegate: sessionDelegate,
            delegateQueue: delegateOperationQueue
        )
        session.sessionDescription = "com.uncosmos.WebImage.ImageDownloader"

        let processingQueue = DispatchQueue(
            label: "com.uncosmos.WebImage.ImageDownloader.processing",
            attributes: .concurrent
        )

        self.session = session
        self.delegate = delegate
        self.delegateQueue = delegateQueue
        self.processingQueue = processingQueue
        self.sessionDelegate = sessionDelegate
        
        sessionDelegate.downloader = self
    }
    
    public func downloadImage(
        at url: URL,
        decoding decodingHandler: DownloadTask.DecodingHandler? = nil,
        transform transformHandler: DownloadTask.TransformHandler? = nil,
        completion completionHandler: DownloadTask.CompletionHandler? = nil
    ) -> URLSessionDataTask {
        let downloadTask = DownloadTask(
            decoding: decodingHandler,
            transform: transformHandler,
            completion: completionHandler,
            dataTask: session.dataTask(with: url)
        )
        
        taskRegistry.addTask(downloadTask)
        return downloadTask.dataTask
    }
    
    public func downloadImage(
        with urlRequest: URLRequest,
        decoding decodingHandler: DownloadTask.DecodingHandler? = nil,
        transform transformHandler: DownloadTask.TransformHandler? = nil,
        completion completionHandler: DownloadTask.CompletionHandler? = nil
    ) -> URLSessionDataTask {
        let downloadTask = DownloadTask(
            decoding: decodingHandler,
            transform: transformHandler,
            completion: completionHandler,
            dataTask: session.dataTask(with: urlRequest)
        )
        
        taskRegistry.addTask(downloadTask)
        return downloadTask.dataTask
    }

    public func invalidate(allowFinishingOutstandingTasks shouldAllow: Bool) {
        if shouldAllow {
            session.finishTasksAndInvalidate()
        } else {
            session.invalidateAndCancel()
            taskRegistry.removeAllTasks()
            
            if delegateQueue === DispatchQueue.main && Thread.isMainThread {
                sessionDelegate.downloader = nil
                delegate = nil
            } else {
                delegateQueue.sync {
                    sessionDelegate.downloader = nil
                    delegate = nil
                }
            }
        }
    }
    
    deinit {
        session.invalidateAndCancel()
    }
}

// MARK: - URLSessionDataDelegate
private extension ImageDownloader {
    class URLSessionDelegateProxy : NSObject, URLSessionDataDelegate {
        weak var downloader: ImageDownloader?
        
        func urlSession(_ session: URLSession, didBecomeInvalidWithError error: Error?) {
            if let downloader = downloader {
                downloader.taskRegistry.removeAllTasks()
                downloader.delegate = nil
                self.downloader = nil
            }
        }
        
        func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
            guard let task = downloader?.taskRegistry.task(forIdentifier: dataTask.taskIdentifier) else {
                return
            }
            
            task.recevie(data)
        }
        
        func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
            guard
                let downloader = downloader,
                let url = task.originalRequest?.url,
                let downloadTask = downloader.taskRegistry.removeTask(forIdentifier: task.taskIdentifier)
            else {
                return
            }
            
            switch (error, downloadTask.data) {
            case (.some(let error as NSError), _):
                let completionHandler = downloadTask.completionHandler
                
                downloader.delegateQueue.async { [weak downloader, completionHandler, url, error] in
                    guard let downloader = downloader else { return }
                    
                    if error.domain == NSURLErrorDomain && error.code == NSURLErrorCancelled {
                        downloader.delegate?.imageDownloader(downloader, didCancelDownloadingImageAt: url)
                        completionHandler?(.cancelled, url)
                    } else {
                        downloader.delegate?.imageDownloader(downloader, didFailToDownloadImageAt: url, with: error)
                        completionHandler?(.networkError(error), url)
                    }
                }
            case (.none, .some):
                downloader.processingQueue.async { [weak downloader, downloadTask] in
                    guard
                        let downloader = downloader,
                        let url = downloadTask.dataTask.originalRequest?.url
                    else { return }
                    
                    let completionHandler = downloadTask.completionHandler
                    
                    // Guard that the data task is not cancelled during decoding/transforming process.
                    func notifyCancellationIfNeeded() -> Bool {
                        if downloadTask.dataTask.state == .canceling {
                            downloader.delegateQueue.async { [weak downloader, completionHandler, url] in
                                guard let downloader = downloader else { return }
                                
                                downloader.delegate?.imageDownloader(downloader, didCancelDownloadingImageAt: url)
                                completionHandler?(.cancelled, url)
                            }
                            return true
                        } else {
                            return false
                        }
                    }
                    
                    if notifyCancellationIfNeeded() { return }
                    
                    // Decode image data
                    let imageData = downloadTask.data! as Data
                    
                    var imageIfDecoded: UIImage?
                    if let decodingHandler = downloadTask.decodingHandler {
                        imageIfDecoded = decodingHandler(imageData, url)
                    } else {
                        imageIfDecoded = UIImage(data: imageData)
                    }
                    
                    if notifyCancellationIfNeeded() { return }
                    
                    // Failed to decode image data
                    guard var image = imageIfDecoded else {
                        return downloader.delegateQueue.async { [weak downloader, completionHandler, url, imageData] in
                            guard let downloader = downloader else { return }
                            
                            downloader.delegate?.imageDownloader(
                                downloader,
                                didFailToDecodeImageDataAt: url,
                                with: imageData
                            )
                            completionHandler?(.undecodableData(imageData), url)
                        }
                    }
                    
                    // Transform image if needed
                    if let transformHandler = downloadTask.transformHandler {
                        image = transformHandler(image, url)
                        
                        if notifyCancellationIfNeeded() { return }
                    }
                    
                    // Notify delegate and completion handler
                    return downloader.delegateQueue.async {
                        [weak downloader, completionHandler, url, image, imageData] in
                        guard let downloader = downloader else { return }
                        
                        downloader.delegate?.imageDownloader(
                            downloader,
                            didDownload: image,
                            decodedFrom: imageData,
                            at: url
                        )
                        completionHandler?(.decoded(image, from: imageData), url)
                    }
                }
            default:
                let completionHandler = downloadTask.completionHandler
                
                downloader.delegateQueue.async { [weak downloader, completionHandler, url] in
                    guard let downloader = downloader else { return }
                    
                    downloader.delegate?.imageDownloader(downloader, didFailToDecodeImageDataAt: url, with: nil)
                    completionHandler?(.missingData, url)
                }
            }
        }
    }
}

// MARK: - TaskRegistry
private extension ImageDownloader {
    struct TaskRegistry {
        private var tasks = [Int : ImageDownloadTask]()
        
    #if DEBUG
        private var lock = NSLock()
    #else
        private var lock = os_unfair_lock()
    #endif
        
        init() {
        #if DEBUG
            lock.name = "com.uncosmos.WebImage.ImageDownloader.taskRegistry"
        #endif
        }
        
        mutating func addTask(_ task: ImageDownloadTask) {
            beginAccessing()
            tasks[task.dataTask.taskIdentifier] = task
            endAccessing()
        }
        
        mutating func removeTask(forIdentifier taskIdentifier: Int) -> ImageDownloadTask? {
            beginAccessing()
            defer { endAccessing() }
            return tasks.removeValue(forKey: taskIdentifier)
        }
        
        mutating func removeAllTasks() {
            beginAccessing()
            defer { endAccessing() }
            tasks.removeAll()
        }
        
        mutating func task(forIdentifier taskIdentifier: Int) -> ImageDownloadTask? {
            beginAccessing()
            defer { endAccessing() }
            return tasks[taskIdentifier]
        }
        
        private mutating func beginAccessing() {
        #if DEBUG
            lock.lock()
        #else
            os_unfair_lock_lock(&lock)
        #endif
        }
        
        private mutating func endAccessing() {
        #if DEBUG
            lock.unlock()
        #else
            os_unfair_lock_unlock(&lock)
        #endif
        }
    }
}
