import Foundation

struct LLMPricingCatalog {
    struct Pricing: Sendable, Equatable {
        let inputUSDPerMillionTokens: Double
        let cachedInputUSDPerMillionTokens: Double?
        let outputUSDPerMillionTokens: Double
        let source: String
        let version: String
        let currency: String
    }

    private static let entries: [String: Pricing] = [
        "gpt-5.4-mini": Pricing(
            inputUSDPerMillionTokens: 0.40,
            cachedInputUSDPerMillionTokens: 0.04,
            outputUSDPerMillionTokens: 1.60,
            source: "gracula-internal-pricing",
            version: "internal-v1",
            currency: "USD"
        ),
        "gpt-5.5": Pricing(
            inputUSDPerMillionTokens: 1.25,
            cachedInputUSDPerMillionTokens: 0.125,
            outputUSDPerMillionTokens: 10.00,
            source: "gracula-internal-pricing",
            version: "internal-v1",
            currency: "USD"
        )
    ]

    static func pricing(for model: String) -> Pricing? {
        let normalized = model.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "openai/", with: "")
        return entries[normalized]
    }

    static func cost(
        for model: String,
        promptTokens: Int?,
        cachedPromptTokens: Int?,
        completionTokens: Int?
    ) -> (value: Double, pricing: Pricing)? {
        guard let pricing = pricing(for: model) else {
            return nil
        }

        let prompt = max(0, promptTokens ?? 0)
        let cached = max(0, cachedPromptTokens ?? 0)
        let uncachedPrompt = max(0, prompt - cached)
        let completion = max(0, completionTokens ?? 0)

        let inputCost = (Double(uncachedPrompt) / 1_000_000.0) * pricing.inputUSDPerMillionTokens
        let cachedInputCost = (Double(cached) / 1_000_000.0) * (pricing.cachedInputUSDPerMillionTokens ?? pricing.inputUSDPerMillionTokens)
        let outputCost = (Double(completion) / 1_000_000.0) * pricing.outputUSDPerMillionTokens
        return (inputCost + cachedInputCost + outputCost, pricing)
    }
}
