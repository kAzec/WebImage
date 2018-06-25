//
//  ImageDownloaderDelegate.swift
//  Shared
//
//  Created by Fengwei Liu on 2018/04/01.
//  Copyright © 2018 kAzec. All rights reserved.
//

import UIKit
import Foundation

public protocol ImageDownloaderDelegate : class {
    func imageDownloader(
        _ downloader: ImageDownloader,
        shouldDownloadImageAt url: URL,
        with response: URLResponse,
        for task: ImageDownloadTask
    ) -> Bool
    
    func imageDownloader(
        _ downloader: ImageDownloader,
        didFinishDownloadingImageAt url: URL,
        with error: NSError?,
        for task: ImageDownloadTask
    )
    
    func imageDownloader(
        _ downloader: ImageDownloader,
        didDownload image: UIImage,
        at url: URL,
        for task: ImageDownloadTask
    )
}

// MARK: - Providing Default Implementations

public extension ImageDownloaderDelegate {
    func imageDownloader(
        _ downloader: ImageDownloader,
        shouldDownloadImageAt url: URL,
        with response: URLResponse,
        for task: ImageDownloadTask
    ) -> Bool {
        return true
    }
    
    func imageDownloader(
        _ downloader: ImageDownloader,
        didFinishDownloadingImageAt url: URL,
        with error: NSError?,
        for task: ImageDownloadTask
    ) { }
    
    func imageDownloader(
        _ downloader: ImageDownloader,
        didDownload image: UIImage,
        at url: URL,
        for task: ImageDownloadTask
    ) { }
}

