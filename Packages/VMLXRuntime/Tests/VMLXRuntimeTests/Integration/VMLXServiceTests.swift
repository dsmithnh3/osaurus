import Testing
import Foundation
@testable import VMLXRuntime

@Suite("VMLXService")
struct VMLXServiceTests {

    @Test("Service ID is vmlx")
    func serviceId() {
        let service = VMLXService()
        #expect(service.serviceId == "vmlx")
    }

    @Test("isAvailable returns true")
    func available() {
        let service = VMLXService()
        #expect(service.isAvailable())
    }

    @Test("Handles local model names")
    func handlesLocal() {
        let service = VMLXService()
        #expect(service.handles(requestedModel: "local"))
        #expect(service.handles(requestedModel: "default"))
        #expect(service.handles(requestedModel: "vmlx"))
        #expect(service.handles(requestedModel: nil))
        #expect(service.handles(requestedModel: ""))
        #expect(service.handles(requestedModel: "Qwen3-8B-JANG"))
    }

    @Test("Does not handle remote provider prefixes")
    func doesNotHandleRemote() {
        let service = VMLXService()
        #expect(!service.handles(requestedModel: "openai/gpt-4"))
        #expect(!service.handles(requestedModel: "anthropic/claude"))
    }

    @Test("Conforms to VMLXToolCapableService")
    func conformsToProtocol() {
        let service = VMLXService()
        // Type check: VMLXService is VMLXToolCapableService
        let _: any VMLXToolCapableService = service
    }

    @Test("Generate without model throws")
    func generateWithoutModel() async {
        let service = VMLXService()
        do {
            _ = try await service.generateOneShot(
                messages: [VMLXChatMessage(role: "user", content: "Hi")],
                params: SamplingParams(),
                requestedModel: nil
            )
            Issue.record("Expected error")
        } catch {
            // Expected: noModelLoaded
        }
    }
}
