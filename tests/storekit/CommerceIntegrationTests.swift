import XCTest
import StoreKit
import StoreKitTest
@testable import CommerceHost

final class CommerceIntegrationTests: XCTestCase {
    @MainActor
    private func session() throws -> SKTestSession {
        let value = try SKTestSession(configurationFileNamed: "AdRemoval")
        value.resetToDefaultState()
        value.clearTransactions()
        value.disableDialogs = true
        value.storefront = "JPN"
        value.locale = Locale(identifier: "ja_JP")
        return value
    }
    @MainActor
    private func waitFor(_ condition: () -> Bool) async throws {
        for _ in 0..<200 {
            if condition() { return }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        XCTFail("StoreKit state did not update within 10 seconds")
    }

    @MainActor
    func testVerifiedPurchaseRestoreAndRelaunch() async throws {
        let session = try session()
        let store = AdRemovalStore(enabled: true)
        await store.refreshEntitlements()
        XCTAssertEqual(store.entitlement, .free)
        _ = try await store.refreshPurchaseInfo()
        XCTAssertFalse(store.busy)
        XCTAssertEqual(store.snapshot()["available"] as? Bool, true)
        XCTAssertFalse((store.snapshot()["price"] as? String ?? "").isEmpty)
        _ = try await store.purchase()
        XCTAssertEqual(store.entitlement, .removed)
        XCTAssertFalse(store.busy)
        XCTAssertEqual(session.allTransactions().count, 1)
        let restored = AdRemovalStore(enabled: true)
        _ = try await restored.restore()
        XCTAssertEqual(restored.entitlement, .removed)
        XCTAssertFalse(restored.busy)
        let relaunch = AdRemovalStore(enabled: true)
        await relaunch.refreshEntitlements()
        XCTAssertEqual(relaunch.entitlement, .removed)
        _ = try await relaunch.purchase()
        XCTAssertEqual(session.allTransactions().count, 1, "A second tap must not create another transaction")
    }

    @MainActor
    func testRefundRevokesRightsThroughTransactionUpdates() async throws {
        let session = try session()
        let store = AdRemovalStore(enabled: true)
        store.start()
        try await waitFor { store.entitlement == .free }
        _ = try await store.purchase()
        XCTAssertEqual(store.entitlement, .removed)
        let transaction = try XCTUnwrap(session.allTransactions().first)
        try session.refundTransaction(identifier: transaction.identifier)
        try await waitFor { store.entitlement == .free }
        XCTAssertFalse(store.busy)
    }

    @MainActor
    func testAskToBuyDoesNotGrantRightsUntilApproval() async throws {
        let session = try session()
        session.askToBuyEnabled = true
        let store = AdRemovalStore(enabled: true)
        store.start()
        try await waitFor { store.entitlement == .free }
        _ = try await store.purchase()
        XCTAssertTrue(store.pendingApproval)
        XCTAssertFalse(store.busy)
        XCTAssertEqual(store.entitlement, .free)
        XCTAssertEqual(store.snapshot()["available"] as? Bool, false)
        do { _ = try await store.purchase(); XCTFail("A pending purchase must not start again") }
        catch { XCTAssertTrue(store.pendingApproval) }
        let transaction = try XCTUnwrap(session.allTransactions().first)
        try session.approveAskToBuyTransaction(identifier: transaction.identifier)
        try await waitFor { store.entitlement == .removed && !store.pendingApproval }
    }

    @MainActor
    func testDeclinedAskToBuyCanBeExplicitlyRechecked() async throws {
        let session = try session()
        session.askToBuyEnabled = true
        let store = AdRemovalStore(enabled: true)
        store.start()
        try await waitFor { store.entitlement == .free }
        _ = try await store.purchase()
        XCTAssertTrue(store.pendingApproval)
        let transaction = try XCTUnwrap(session.allTransactions().first)
        try session.declineAskToBuyTransaction(identifier: transaction.identifier)
        _ = try await store.refreshPurchaseInfo()
        XCTAssertEqual(store.entitlement, .free, "Rechecking must never grant unpaid rights")
        XCTAssertFalse(store.pendingApproval, "An explicit recheck must not remain stuck after a declined request")
        XCTAssertFalse(store.busy)
        session.askToBuyEnabled = false
        _ = try await store.purchase()
        XCTAssertEqual(store.entitlement, .removed)
    }

    @MainActor
    func testFailureAndCancellationReleaseBusyWithoutGrantingRights() async throws {
        let session = try session()
        try await session.setSimulatedError(.generic(.userCancelled), forAPI: .purchase)
        let store = AdRemovalStore(enabled: true)
        await store.refreshEntitlements()
        do { _ = try await store.purchase() } catch { /* StoreKit may return cancellation or an error. */ }
        XCTAssertFalse(store.busy)
        XCTAssertEqual(store.entitlement, .free)
        XCTAssertTrue(session.allTransactions().isEmpty)
        try await session.setSimulatedError(.generic(.networkError(URLError(.notConnectedToInternet))), forAPI: .purchase)
        do { _ = try await store.purchase(); XCTFail("An offline purchase must not succeed") } catch {}
        XCTAssertFalse(store.busy)
        XCTAssertEqual(store.entitlement, .free)
        try await session.setSimulatedError(nil, forAPI: .purchase)
        _ = try await store.purchase()
        XCTAssertFalse(store.busy)
        XCTAssertEqual(store.entitlement, .removed, "A canceled attempt must allow a later purchase")
    }

    @MainActor
    func testConcurrentTapIsRejectedBeforeProductLookup() async throws {
        let session = try session()
        let store = AdRemovalStore(enabled: true)
        await store.refreshEntitlements()
        let first = Task { @MainActor in try await store.purchase() }
        try await waitFor { store.busy }
        do { _ = try await store.purchase(); XCTFail("Concurrent purchase must be rejected") }
        catch { XCTAssertTrue(store.busy) }
        _ = try await first.value
        XCTAssertEqual(session.allTransactions().count, 1)
        XCTAssertFalse(store.busy)
    }

    @MainActor
    func testPreviewCannotPurchaseOrRestore() async throws {
        let session = try session()
        let store = AdRemovalStore(enabled: false)
        do { _ = try await store.purchase(); XCTFail("Preview purchase must be disabled") } catch {}
        do { _ = try await store.restore(); XCTFail("Preview restore must be disabled") } catch {}
        XCTAssertTrue(session.allTransactions().isEmpty)
        XCTAssertFalse(store.busy)
        let unchecked = AdRemovalStore(enabled: true)
        do { _ = try await unchecked.purchase(); XCTFail("Unchecked rights must block purchasing") } catch {}
        XCTAssertTrue(session.allTransactions().isEmpty)
    }
}
