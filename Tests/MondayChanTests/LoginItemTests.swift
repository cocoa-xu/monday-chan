import ServiceManagement
import Testing
@testable import MondayChan

@Test @MainActor func loginItemReflectsApprovalAndChangesMadeInSystemSettings() {
    let service = TestLoginItemService()
    let item = LoginItem(service: service)
    #expect(!item.isEnabled)
    item.setEnabled(true)
    #expect(item.isEnabled)
    #expect(item.status == .requiresApproval)
    service.status = .enabled
    item.refresh()
    #expect(item.status == .enabled)
    service.status = .notRegistered
    item.refresh()
    #expect(!item.isEnabled)
    item.setEnabled(true)
    item.setEnabled(false)
    #expect(!item.isEnabled)
}

@Test @MainActor func rejectedLoginRegistrationDoesNotShowAnEnabledSwitch() {
    let service = TestLoginItemService()
    service.rejectsRegistration = true
    let item = LoginItem(service: service)
    item.setEnabled(true)
    #expect(item.error != nil)
    #expect(!item.isEnabled)
    service.rejectsRegistration = false
    item.setEnabled(true)
    #expect(item.error == nil)
    #expect(item.isEnabled)
}

@MainActor private final class TestLoginItemService: LoginItemService {
    enum Failure: Error { case denied }
    var status: SMAppService.Status = .notRegistered
    var rejectsRegistration = false
    func register() throws {
        if rejectsRegistration { throw Failure.denied }
        status = .requiresApproval
    }
    func unregister() throws { status = .notRegistered }
}
