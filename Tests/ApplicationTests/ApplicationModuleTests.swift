import Application
import Testing

@Test
func applicationModuleIsImportable() {
    #expect(ApplicationModule.name == "Application")
    #expect(ApplicationModule.domainDependency == "Domain")
}

