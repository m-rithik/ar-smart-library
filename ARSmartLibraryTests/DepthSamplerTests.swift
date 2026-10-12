import CoreVideo
import XCTest
@testable import ARSmartLibrary

final class DepthSamplerTests: XCTestCase {
    func testNeighborhoodRecoversInvalidCenterAndIsolatedDepthOutlier() throws {
        for center in [Float.nan, 4.8] {
            var depths = Array(repeating: Float(2), count: 9)
            depths[4] = center
            let sample = try XCTUnwrap(DepthSampler.sample(
                in: depthMap(depths), confidenceMap: confidenceMap(Array(repeating: 2, count: 9)),
                at: CGPoint(x: 0.5, y: 0.5)
            ))

            XCTAssertEqual(sample.depth, 2, accuracy: 0.001)
            XCTAssertEqual(sample.quality, .high)
        }
    }

    func testLowConfidenceAndInsufficientReliableSupportAreRejected() throws {
        let depth = try depthMap(Array(repeating: 2, count: 9))
        for confidence in [Array(repeating: UInt8(0), count: 9), [0, 0, 0, 0, 2, 0, 0, 0, 0]] {
            XCTAssertNil(DepthSampler.sample(
                in: depth, confidenceMap: try confidenceMap(confidence), at: CGPoint(x: 0.5, y: 0.5)
            ))
        }
    }

    func testForegroundBackgroundDiscontinuityIsRejected() throws {
        XCTAssertNil(DepthSampler.sample(
            in: try depthMap([1, 1, 1, 1, 1, 3, 3, 3, 3]),
            confidenceMap: try confidenceMap(Array(repeating: 2, count: 9)),
            at: CGPoint(x: 0.5, y: 0.5)
        ))
    }

    func testMissingOrMediumConfidenceNeverClaimsHighQuality() throws {
        let depth = try depthMap(Array(repeating: 2, count: 9))
        for confidence in [nil, try confidenceMap(Array(repeating: 1, count: 9))] {
            let sample = try XCTUnwrap(DepthSampler.sample(
                in: depth, confidenceMap: confidence, at: CGPoint(x: 0.5, y: 0.5)
            ))

            XCTAssertEqual(sample.depth, 2, accuracy: 0.001)
            XCTAssertEqual(sample.quality, .medium)
        }
    }

    func testInvalidAndOffscreenCoordinatesCannotClampToAnUnrelatedSurface() throws {
        let depth = try depthMap(Array(repeating: 2, count: 9))
        for point in [CGPoint(x: -0.01, y: 0.5), CGPoint(x: 1.01, y: 0.5),
                      CGPoint(x: 0.5, y: -0.01), CGPoint(x: 0.5, y: 1.01),
                      CGPoint(x: CGFloat.nan, y: 0.5), CGPoint(x: 0.5, y: CGFloat.infinity)] {
            XCTAssertNil(DepthSampler.sample(in: depth, confidenceMap: nil, at: point))
        }
        for point in [CGPoint.zero, CGPoint(x: 1, y: 1)] {
            XCTAssertNotNil(DepthSampler.sample(in: depth, confidenceMap: nil, at: point))
        }
    }

    func testMismatchedConfidenceDimensionsAreRejected() throws {
        XCTAssertNil(DepthSampler.sample(
            in: try depthMap(Array(repeating: 2, count: 9)),
            confidenceMap: try confidenceMap([2, 2, 2, 2], width: 2), at: CGPoint(x: 0.5, y: 0.5)
        ))
    }

    private func depthMap(_ values: [Float]) throws -> CVPixelBuffer {
        let buffer = try makeBuffer(width: 3, height: 3, format: kCVPixelFormatType_DepthFloat32)
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        let address = try XCTUnwrap(CVPixelBufferGetBaseAddress(buffer))
        for y in 0..<3 {
            let row = address.advanced(by: y * CVPixelBufferGetBytesPerRow(buffer)).assumingMemoryBound(to: Float32.self)
            for x in 0..<3 { row[x] = values[y * 3 + x] }
        }
        return buffer
    }

    private func confidenceMap(_ values: [UInt8], width: Int = 3) throws -> CVPixelBuffer {
        let height = values.count / width
        let buffer = try makeBuffer(width: width, height: height, format: kCVPixelFormatType_OneComponent8)
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        let address = try XCTUnwrap(CVPixelBufferGetBaseAddress(buffer))
        for y in 0..<height {
            let row = address.advanced(by: y * CVPixelBufferGetBytesPerRow(buffer)).assumingMemoryBound(to: UInt8.self)
            for x in 0..<width { row[x] = values[y * width + x] }
        }
        return buffer
    }

    private func makeBuffer(width: Int, height: Int, format: OSType) throws -> CVPixelBuffer {
        var buffer: CVPixelBuffer?
        XCTAssertEqual(CVPixelBufferCreate(kCFAllocatorDefault, width, height, format, nil, &buffer), kCVReturnSuccess)
        return try XCTUnwrap(buffer)
    }
}
