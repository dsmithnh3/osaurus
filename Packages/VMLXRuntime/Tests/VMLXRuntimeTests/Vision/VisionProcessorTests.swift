import Testing
import Foundation
@testable import VMLXRuntime

@Suite("VisionProcessor")
struct VisionProcessorTests {

    @Test("Resize dimensions maintains aspect ratio")
    func resizeDimensions() {
        let vp = VisionProcessor()

        // Landscape
        let (w1, h1) = vp._resizeDimensions(width: 2000, height: 1000, maxDim: 1024)
        #expect(w1 == 1024)
        #expect(h1 == 512)

        // Portrait
        let (w2, h2) = vp._resizeDimensions(width: 500, height: 2000, maxDim: 1024)
        #expect(w2 == 256)
        #expect(h2 == 1024)

        // Already within limits
        let (w3, h3) = vp._resizeDimensions(width: 800, height: 600, maxDim: 1024)
        #expect(w3 == 800)
        #expect(h3 == 600)

        // Square
        let (w4, h4) = vp._resizeDimensions(width: 2048, height: 2048, maxDim: 1024)
        #expect(w4 == 1024)
        #expect(h4 == 1024)
    }

    @Test("Default normalization values are CLIP")
    func clipDefaults() {
        let vp = VisionProcessor()
        #expect(vp.normMean.count == 3)
        #expect(vp.normStd.count == 3)
        #expect(vp.maxSize == 1024)
    }

    @Test("Custom configuration")
    func customConfig() {
        let vp = VisionProcessor(
            maxSize: 512,
            normMean: [0.5, 0.5, 0.5],
            normStd: [0.5, 0.5, 0.5]
        )
        #expect(vp.maxSize == 512)
        #expect(vp.normMean == [0.5, 0.5, 0.5])
    }

    @Test("Invalid image data throws")
    func invalidData() {
        let vp = VisionProcessor()
        do {
            _ = try vp.processImage(data: Data([0, 1, 2, 3]))
            Issue.record("Expected error")
        } catch {
            // Expected: invalidImageData
        }
    }

    @Test("Invalid URL throws")
    func invalidURL() {
        let vp = VisionProcessor()
        do {
            _ = try vp.processImageURL("not-a-url")
            Issue.record("Expected error")
        } catch {
            // Expected: invalidImageURL
        }
    }

    @Test("Video not yet supported")
    func videoNotSupported() {
        let vp = VisionProcessor()
        do {
            _ = try vp.extractFrames(from: URL(fileURLWithPath: "/tmp/test.mp4"))
            Issue.record("Expected error")
        } catch {
            // Expected: videoNotSupported
        }
    }

    @Test("Normalization applies correctly")
    func normalization() {
        let vp = VisionProcessor(normMean: [0.5, 0.5, 0.5], normStd: [0.5, 0.5, 0.5])
        // CHW layout: 3 channels, 1 pixel each
        let input: [Float] = [1.0, 0.5, 0.0]  // R=1.0, G=0.5, B=0.0
        let normalized = vp._normalize(input, width: 1, height: 1)
        #expect(normalized[0] == 1.0)   // (1.0 - 0.5) / 0.5 = 1.0
        #expect(normalized[1] == 0.0)   // (0.5 - 0.5) / 0.5 = 0.0
        #expect(normalized[2] == -1.0)  // (0.0 - 0.5) / 0.5 = -1.0
    }

    @Test("Error descriptions exist")
    func errorDescriptions() {
        let errors: [VisionError] = [
            .invalidImageData, .invalidImageURL, .invalidBase64,
            .downloadFailed("url"), .fileNotFound("path"),
            .videoNotSupported, .frameExtractionFailed
        ]
        for error in errors {
            #expect(error.errorDescription != nil)
        }
    }
}
