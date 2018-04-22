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
    func imageDownloader(_ downloader: ImageDownloader, didCancelDownloadingImageAt url: URL)
    func imageDownloader(_ downloader: ImageDownloader, didFailToDownloadImageAt url: URL, with error: NSError)
    func imageDownloader(_ downloader: ImageDownloader, didFailToDecodeImageDataAt url: URL, with data: Data?)
    func imageDownloader(
        _ downloader: ImageDownloader,
        didDownload image: UIImage,
        decodedFrom data: Data,
        at url: URL
    )
}

extension ImageDownloaderDelegate {
    func imageDownloader(_ downloader: ImageDownloader, didCancelDownloadingImageAt url: URL) { }
    func imageDownloader(_ downloader: ImageDownloader, didFailToDownloadImageAt url: URL, with error: NSError) { }
}

