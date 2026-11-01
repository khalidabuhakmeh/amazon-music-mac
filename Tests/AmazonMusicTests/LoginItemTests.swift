import Testing
@testable import AmazonMusic

@MainActor
struct LoginItemTests {
    @Test func mapping() {
        #expect(LoginItemPresentation(.enabled).isOn)
        #expect(!LoginItemPresentation(.disabled).isOn)
        #expect(LoginItemPresentation(.requiresApproval).needsApproval)
        #expect(!LoginItemPresentation(.notFound).canToggle)
        #expect(LoginItemPresentation(.notFound).caption != nil)
    }
    @Test func fakeRegister() throws {
        let f = FakeLoginItem()
        try f.register(); #expect(f.status == .enabled)
        try f.unregister(); #expect(f.status == .disabled)
    }
}
