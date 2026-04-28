import Application
import Domain
import Testing

@Test
func toolRegistryRegistersAndResolvesToolsByName() async throws {
    let registry = ToolRegistry()
    await registry.register(FakeTool(name: "open_url", result: .success("Opened")))

    let tool = try await registry.resolve(name: "open_url")

    #expect(tool.name == "open_url")
}

@Test
func toolRegistryReturnsDescriptorsSortedByName() async {
    let registry = ToolRegistry(tools: [
        FakeTool(name: "write_note", result: .success("Wrote"), riskLevel: .reversible),
        FakeTool(name: "open_url", result: .success("Opened"), riskLevel: .safe)
    ])

    let descriptors = await registry.descriptors()

    #expect(descriptors.map(\.name) == ["open_url", "write_note"])
    #expect(descriptors.map(\.riskLevel) == [.safe, .reversible])
}

@Test
func toolRegistryThrowsTypedErrorForUnknownTools() async throws {
    let registry = ToolRegistry()

    do {
        _ = try await registry.resolve(name: "missing")
        Issue.record("Expected unknown tool error")
    } catch DomainError.unknownTool(let name) {
        #expect(name == "missing")
    }
}

