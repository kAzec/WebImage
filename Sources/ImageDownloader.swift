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
    public let session: URLSession
    
    public var delegate: ImageDownloaderDelegate? {
        get {
            if delegateQueue == .main && Thread.isMainThread {
                return weakDelegate
            } else {
                return delegateQueue.sync { weakDelegate }
            }
        }
        
        set {
            if delegateQueue == .main && Thread.isMainThread {
                weakDelegate = newValue
            } else {
                delegateQueue.sync { weakDelegate = newValue }
            }
        }
    }
    
    private var taskRegistry = TaskRegistry()
    
    private let processQueue: DispatchQueue
    private let delegateQueue: DispatchQueue
    private let sessionDelegate: URLSessionDelegateProxy
    
    private weak var weakDelegate: ImageDownloaderDelegate?

    public init(
        sessionConfiguration: URLSessionConfiguration,
        delegate: ImageDownloaderDelegate? = nil,
        delegateQueue: DispatchQueue = .main
    ) {
        let delegateOperationQueue: OperationQueue
        
        if delegateQueue === DispatchQueue.main {
            delegateOperationQueue = .main
        } else {
            delegateOperationQueue = OperationQueue()
            delegateOperationQueue.underlyingQueue = delegateQueue
        }
        
        let sessionDelegate = URLSessionDelegateProxy()
        
        let session = URLSession(
            configuration: sessionConfiguration,
            delegate:      sessionDelegate,
            delegateQueue: delegateOperationQueue
        )
        session.sessionDescription = "com.uncosmos.WebImage.ImageDownloader"

        let processQueue = DispatchQueue(
            label: "com.uncosmos.WebImage.ImageDownloader.Process",
            attributes: .concurrent
        )

        self.session = session
        self.weakDelegate = delegate
        self.delegateQueue = delegateQueue
        self.processQueue = processQueue
        self.sessionDelegate = sessionDelegate
        
        sessionDelegate.downloader = self
    }
    
    deinit {
        session.invalidateAndCancel()
    }
}

// MARK: - Creating Image Download Tasks

public extension ImageDownloader {
    @_inlineable
    func downloadTask(
        with request: URLRequest,
        progress progressHandler: ImageDownloadTask.ProgressHandler? = nil,
        decoding decodingHandler: ImageDownloadTask.DecodingHandler? = nil,
        transform transformHandler: ImageDownloadTask.TransformHandler? = nil,
        completion completionHandler: ImageDownloadTask.CompletionHandler? = nil
    ) -> ImageDownloadTask {
        return AnyImageDownloadTask(
            request:    request,
            downloader: self,
            progress:   progressHandler,
            decoding:   decodingHandler,
            transform:  transformHandler,
            completion: completionHandler
        )
    }
    
    @_inlineable
    func downloadTask(
        at url: URL,
        progress progressHandler: ImageDownloadTask.ProgressHandler? = nil,
        decoding decodingHandler: ImageDownloadTask.DecodingHandler? = nil,
        transform transformHandler: ImageDownloadTask.TransformHandler? = nil,
        completion completionHandler: ImageDownloadTask.CompletionHandler? = nil
    ) -> ImageDownloadTask {
        return AnyImageDownloadTask(
            request:    URLRequest(url: url),
            downloader: self,
            progress:   progressHandler,
            decoding:   decodingHandler,
            transform:  transformHandler,
            completion: completionHandler
        )
    }
}

// MARK: - Internal Methods

extension ImageDownloader {
    func addTask(_ downloadTask: ImageDownloadTask) {
        taskRegistry.addTask(downloadTask)
    }
    
    func didFinishDownloadingImage(for downloadTask: ImageDownloadTask, with error: NSError?) {
        if let delegate = weakDelegate, let url = downloadTask.url {
            delegate.imageDownloader(self, didFinishDownloadingImageAt: url, with: error, for: downloadTask)
        }
        
        if let error = error {
            if error.domain == NSURLErrorDomain, error.code == NSURLErrorCancelled {
                downloadTask.complete(with: .cancelled)
            } else {
                downloadTask.complete(with: .failed(error))
            }
        } else if let imageData = downloadTask.imageData, !imageData.isEmpty {
            processQueue.async { [weak self] in
                self?.processImage(for: downloadTask, with: imageData)
            }
        } else {
            downloadTask.complete(with: .noData)
        }
    }
    
    func processImage(for downloadTask: ImageDownloadTask, with imageData: Data) {
        func cancelIfNeeded() -> Bool {
            if downloadTask.dataTask.state == .canceling {
                delegateQueue.async {
                    downloadTask.complete(with: .cancelled)
                }
                return true
            } else {
                return false
            }
        }
        
        if cancelIfNeeded() { return }
        
        guard var image = downloadTask.decode(imageData) else {
            if cancelIfNeeded() { return }
            
            return delegateQueue.async {
                downloadTask.complete(with: .badData(imageData))
            }
        }
        
        if cancelIfNeeded() { return }
        
        if let transformed = downloadTask.transform(image) {
            if cancelIfNeeded() { return }
            image = transformed
        }
        
        delegateQueue.async { [weak self] in
            if let sself = self, let delegate = sself.weakDelegate, let url = downloadTask.url {
                delegate.imageDownloader(sself, didDownload: image, at: url, for: downloadTask)
            }
            
            downloadTask.complete(with: .succeeded(image, from: imageData))
        }
    }
}

// MARK: - Conforming to URLSessionDataDelegate via Proxy

extension ImageDownloader {
    class URLSessionDelegateProxy : NSObject, URLSessionDataDelegate {
        weak var downloader: ImageDownloader?
        
        func urlSession(_ session: URLSession, didBecomeInvalidWithError error: Error?) {
            if let downloader = downloader {
                self.downloader = nil
                
                downloader.taskRegistry.removeAllTasks()
                downloader.weakDelegate = nil
            }
        }
        
        func urlSession(
            _ session: URLSession,
            dataTask: URLSessionDataTask,
            didReceive response: URLResponse,
            completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
        ) {
            guard let downloader = downloader else {
                return completionHandler(.cancel)
            }
            
            if
                let delegate = downloader.weakDelegate,
                let url = dataTask.originalRequest?.url,
                let downloadTask = downloader.taskRegistry.task(forIdentifier: dataTask.taskIdentifier),
                !delegate.imageDownloader(downloader, shouldDownloadImageAt: url, with: response, for: downloadTask)
            {
                return completionHandler(.cancel)
            } else {
                return completionHandler(.allow)
            }
        }
        
        func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
            if let downloadTask = downloader?.taskRegistry.task(forIdentifier: dataTask.taskIdentifier) {
                downloadTask.receive(data)
            }
        }
        
        func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
            guard
                let downloader = downloader,
                let downloadTask = downloader.taskRegistry.removeTask(forIdentifier: task.taskIdentifier)
            else {
                return
            }
            
            downloader.didFinishDownloadingImage(for: downloadTask, with: error as NSError?)
        }
    }
}

// MARK: - Supporting Types

extension ImageDownloader {
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
            let oldTask = tasks.updateValue(task, forKey: task.dataTask.taskIdentifier)
            endAccessing()
            
            assert(oldTask == nil, "Duplicate task.")
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
        
        @inline(__always)
        private mutating func beginAccessing() {
        #if DEBUG
            lock.lock()
        #else
            os_unfair_lock_lock(&lock)
        #endif
        }
        
        @inline(__always)
        private mutating func endAccessing() {
        #if DEBUG
            lock.unlock()
        #else
            os_unfair_lock_unlock(&lock)
        #endif
        }
    }
}
