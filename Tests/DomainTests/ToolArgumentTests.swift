import Domain
import Foundation
import Testing

@Test
func toolArgumentCodableRoundTripPreservesCases() throws {
    let arguments: [String: ToolArgument] = [
        "string": .string("value"),
        "int": .int(42),
        "double": .double(3.14),
        "bool": .bool(true),
        "array": .stringArray(["a", "b"])
    ]

    let data = try JSONEncoder().encode(arguments)
    let decoded = try JSONDecoder().decode([String: ToolArgument].self, from: data)

    #expect(decoded == arguments)
}
