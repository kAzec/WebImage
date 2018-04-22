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
        let expectation = self.expectation(description: "Should download image from valid image url: \(imageURL)")
        
        downloader.downloadImage(at: imageURL) { result, sourceURL in
            switch result {
            case .decoded(let image, from: _):
                print("Successfully downloaded image: \(image) from: \(sourceURL)")
                expectation.fulfill()
            case .cancelled:
                XCTAssert(false, "Task should not be cancelled.")
            default:
                XCTAssert(false, "Failed to download image from \(imageURL), result: \(result)")
            }
        }.resume()
        
        wait(for: [expectation], timeout: 5)
    }
    
    func testDownloadAtInvalidImageURL() {
        let imageURL = URL(string: "https://assets-cdn.github.com/images/icons/invalid.png")!
        let expectation = self.expectation(description: "Should not download image from invalid image url: \(imageURL)")
        
        downloader.downloadImage(at: imageURL) { result, sourceURL in
            switch result {
            case .decoded:
                XCTAssert(false, "Should not be able to download image from invalid image url: \(sourceURL)")
            case .cancelled:
                XCTAssert(false, "Task should not be cancelled.")
            default:
                expectation.fulfill()
            }
        }.resume()
        
        wait(for: [expectation], timeout: 5)
    }
}
