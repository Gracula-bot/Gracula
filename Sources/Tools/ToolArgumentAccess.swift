import Domain

extension ToolCall {
    func requiredStringArgument(_ key: String) throws -> String {
        guard let argument = arguments[key] else {
            throw ToolError.missingArgument(key)
        }

        guard case .string(let value) = argument else {
            throw ToolError.invalidArgument(key)
        }

        return value
    }
}

