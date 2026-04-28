import Domain
import Testing

@Test
func riskLevelsSortFromSafeToCritical() {
    #expect(ToolRiskLevel.safe < .reversible)
    #expect(ToolRiskLevel.reversible < .externalCommunication)
    #expect(ToolRiskLevel.externalCommunication < .financialOrCritical)
}

@Test
func riskLevelRawValuesMatchPlannerContract() {
    #expect(ToolRiskLevel.safe.rawValue == "safe")
    #expect(ToolRiskLevel.reversible.rawValue == "reversible")
    #expect(ToolRiskLevel.externalCommunication.rawValue == "externalCommunication")
    #expect(ToolRiskLevel.financialOrCritical.rawValue == "financialOrCritical")
}

