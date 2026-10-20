import XCTest
@testable import MacMuralCore

final class LaunchAtLoginTests: XCTestCase {
    private final class FakeService: LoginItemService {
        var status: LoginItemStatus = .notRegistered
        var registerCount = 0
        var unregisterCount = 0
        var registrationError: Error?
        var unregistrationError: Error?
        var registeredStatus: LoginItemStatus = .enabled
        var updateStatusBeforeError = false
        func register() throws {
            registerCount += 1
            if updateStatusBeforeError { status = registeredStatus }
            if let registrationError { throw registrationError }
            status = registeredStatus
        }
        func unregister() throws {
            unregisterCount += 1
            if let unregistrationError { throw unregistrationError }
            status = .notRegistered
        }
    }
    private var preferences: UserDefaults!
    private var suite: String!
    override func setUpWithError() throws {
        suite = "MacMural.login.tests.\(UUID().uuidString)"
        preferences = try XCTUnwrap(UserDefaults(suiteName: suite))
    }
    override func tearDown() { preferences.removePersistentDomain(forName: suite) }
    private func controller(_ service: FakeService) -> LaunchAtLoginController {
        LaunchAtLoginController(service: service, defaults: preferences)
    }

    func testInstalledFirstLaunchRegistersOnce() {
        let service = FakeService()
        let first = controller(service)
        first.configureDefaultIfNeeded(isInstalled: true)
        XCTAssertEqual(service.registerCount, 1)
        XCTAssertEqual(first.status, .enabled)
        controller(service).configureDefaultIfNeeded(isInstalled: true)
        XCTAssertEqual(service.registerCount, 1)
    }

    func testDevelopmentBuildDoesNotRegisterOrConsumeDefaultAttempt() {
        let service = FakeService()
        controller(service).configureDefaultIfNeeded(isInstalled: false)
        XCTAssertEqual(service.registerCount, 0)
        controller(service).configureDefaultIfNeeded(isInstalled: true)
        XCTAssertEqual(service.registerCount, 1)
    }

    func testExternalDisableIsRespectedOnEveryLaterLaunch() {
        let service = FakeService()
        let first = controller(service)
        first.configureDefaultIfNeeded(isInstalled: true)
        service.status = .notRegistered // User disables it in System Settings.
        XCTAssertEqual(first.status, .notRegistered)
        controller(service).configureDefaultIfNeeded(isInstalled: true)
        XCTAssertEqual(service.registerCount, 1)
        XCTAssertEqual(service.status, .notRegistered)
    }

    func testExplicitDisablePersistsAndDoesNotQuitTheApp() {
        let service = FakeService()
        let first = controller(service)
        first.configureDefaultIfNeeded(isInstalled: true)
        first.setEnabled(false)
        XCTAssertEqual(service.unregisterCount, 1)
        XCTAssertEqual(first.status, .notRegistered)
        controller(service).configureDefaultIfNeeded(isInstalled: true)
        XCTAssertEqual(service.registerCount, 1)
    }

    func testExplicitOptOutBeforeDefaultSetupIsRespected() {
        let service = FakeService()
        controller(service).setEnabled(false)
        controller(service).configureDefaultIfNeeded(isInstalled: true)
        XCTAssertEqual(service.registerCount, 0)
        XCTAssertEqual(service.unregisterCount, 0)
        XCTAssertEqual(service.status, .notRegistered)
    }

    func testExistingEnabledOrApprovalPendingItemIsNotRegisteredAgain() {
        for status in [LoginItemStatus.enabled, .requiresApproval] {
            preferences.removePersistentDomain(forName: suite)
            let service = FakeService()
            service.status = status
            controller(service).configureDefaultIfNeeded(isInstalled: true)
            XCTAssertEqual(service.registerCount, 0)
            XCTAssertEqual(service.status, status)
        }
    }

    func testNotFoundCanBeRegisteredForTheFirstTime() {
        let service = FakeService()
        service.status = .notFound
        controller(service).configureDefaultIfNeeded(isInstalled: true)
        XCTAssertEqual(service.registerCount, 1)
        XCTAssertEqual(service.status, .enabled)
    }

    func testFailedRegistrationIsVisibleAndOnlyRetriedByUser() {
        let service = FakeService()
        service.registrationError = NSError(domain: "Test", code: 1, userInfo: [NSLocalizedDescriptionKey: "Signature rejected"])
        let first = controller(service)
        first.configureDefaultIfNeeded(isInstalled: true)
        XCTAssertEqual(first.errorMessage, "Signature rejected")
        XCTAssertEqual(first.status, .notRegistered)
        controller(service).configureDefaultIfNeeded(isInstalled: true)
        XCTAssertEqual(service.registerCount, 1)
        service.registrationError = nil
        first.setEnabled(true)
        XCTAssertEqual(service.registerCount, 2)
        XCTAssertNil(first.errorMessage)
        XCTAssertEqual(first.status, .enabled)
    }

    func testApprovalPendingStateIsNotReportedAsEnabledOrAsAnError() {
        let service = FakeService()
        service.registeredStatus = .requiresApproval
        service.updateStatusBeforeError = true
        service.registrationError = NSError(domain: "Test", code: 2)
        let first = controller(service)
        first.configureDefaultIfNeeded(isInstalled: true)
        XCTAssertEqual(first.status, .requiresApproval)
        XCTAssertNil(first.errorMessage)
        first.setEnabled(false)
        XCTAssertEqual(first.status, .notRegistered)
    }

    func testFailedUnregisterKeepsActualEnabledStateAndReportsError() {
        let service = FakeService()
        service.status = .enabled
        service.unregistrationError = NSError(domain: "Test", code: 3)
        let first = controller(service)
        first.setEnabled(false)
        XCTAssertNotNil(first.errorMessage)
        XCTAssertEqual(first.status, .enabled)
    }

    func testLoginLaunchIsQuietAndWelcomeAppearsOnlyOnceManually() {
        let first = controller(FakeService())
        XCTAssertFalse(first.shouldShowWelcome(isLoginLaunch: true))
        XCTAssertTrue(first.shouldShowWelcome(isLoginLaunch: false))
        first.markWelcomeShown()
        let next = controller(FakeService())
        XCTAssertFalse(next.shouldShowWelcome(isLoginLaunch: true))
        XCTAssertFalse(next.shouldShowWelcome(isLoginLaunch: false))
    }
}
