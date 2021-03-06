//
//  WebImageTests.swift
//  WebImageTests
//
//  Created by Fengwei Liu on 2018/04/01.
//  Copyright © 2018 kAzec. All rights reserved.
//

import XCTest
import Foundation
@testable import WebImage

class WebImageTests: XCTestCase {
    var downloader: ImageDownloader!
    
    override func setUp() {
        super.setUp()
        downloader = ImageDownloader(sessionConfiguration: .ephemeral, delegateQueue: DispatchQueue(label: "test"))
    }
    
    override func tearDown() {
        downloader = nil
        super.tearDown()
    }
    
    func testDownloadAtValidImageURL() {
        let imageURL = URL(string: "https://assets-cdn.github.com/images/icons/twitter.png")!
        let expectation = self.expectation(description: "Should download image at \(imageURL)")
        
        downloader.downloadTask(at: imageURL) { result, url in
            switch result {
            case .succeeded(let image, _):
                print("Successfully downloaded image: \(image) from: \(url)")
                expectation.fulfill()
            case .cancelled:
                XCTAssert(false, "Task should not be cancelled.")
            default:
                XCTAssert(false, "Failed to download image from \(imageURL), result: \(result)")
            }
        }.resume()
        
        wait(for: [expectation], timeout: 20.0)
    }
    
    func testDownloadAtInvalidImageURL() {
        let imageURL = URL(string: "https://invalid-host/invalid-image.png")!
        let expectation = self.expectation(description: "Should not download image at \(imageURL)")
        
        downloader.downloadTask(at: imageURL) { result, url in
            switch result {
            case .succeeded(let image, _):
                XCTAssert(false, "Should not be able to download image from invalid image url: \(image), \(url)")
            case .cancelled:
                XCTAssert(false, "Task should not be cancelled.")
            default:
                expectation.fulfill()
            }
        }.resume()
        
        wait(for: [expectation], timeout: 20.0)
    }
}
