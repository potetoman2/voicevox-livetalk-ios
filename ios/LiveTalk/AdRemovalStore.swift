import Foundation
import StoreKit

@MainActor
final class AdRemovalStore {
    private(set) var entitlement: AdEntitlement = .checking
    private(set) var busy = false
    private(set) var pendingApproval = false
    private var product: Product?
    private var updates: Task<Void, Never>?
    private var started = false
    private var verifying = false
    private var verificationAgain = false
    var changed: (() -> Void)?
    let enabled: Bool
    private let bundleID: String

    init(enabled: Bool, bundleID: String = Bundle.main.bundleIdentifier ?? "") {
        self.enabled = enabled; self.bundleID = bundleID
    }
    deinit { updates?.cancel() }

    func start() {
        guard !started else { return }; started = true
        updates = Task { [weak self] in
            for await result in Transaction.updates {
                guard !Task.isCancelled, let self else { return }
                switch result {
                case .verified(let transaction):
                    guard transaction.productID == CommercePolicy.removalProductID else { continue }
                    if self.grants(transaction) { self.entitlement = .removed; self.pendingApproval = false; self.changed?() }
                    // Re-read Apple's current rights for refunds, revocation and account changes.
                    await self.refreshEntitlements()
                    if transaction.appBundleID == self.bundleID { await transaction.finish() }
                case .unverified(let transaction, _):
                    if transaction.productID == CommercePolicy.removalProductID {
                        self.entitlement = .checking; self.changed?()
                    }
                }
            }
        }
        Task { [weak self] in
            guard let self else { return }
            await self.refreshEntitlements()
            if self.enabled { await self.loadProduct() }
        }
    }

    private func grants(_ transaction: Transaction) -> Bool {
        CommercePolicy.grantsAdRemoval(PurchaseEvidence(verified: true, productID: transaction.productID,
            bundleID: transaction.appBundleID, nonConsumable: transaction.productType == .nonConsumable,
            revoked: transaction.revocationDate != nil, upgraded: transaction.isUpgraded), bundleID: bundleID)
    }
    func refreshEntitlements() async {
        if verifying { verificationAgain = true; return }
        verifying = true
        repeat {
            verificationAgain = false
            var removed = false, untrusted = false
            for await result in Transaction.currentEntitlements {
                switch result {
                case .verified(let transaction): if grants(transaction) { removed = true }
                case .unverified(let transaction, _):
                    if transaction.productID == CommercePolicy.removalProductID { untrusted = true }
                }
            }
            entitlement = removed ? .removed : untrusted ? .checking : .free
            if removed { pendingApproval = false }
            changed?()
        } while verificationAgain
        verifying = false
    }
    private func loadProduct() async {
        do {
            product = try await Product.products(for: [CommercePolicy.removalProductID]).first(where: { $0.id == CommercePolicy.removalProductID && $0.type == .nonConsumable })
        } catch { product = nil }
        changed?()
    }
    func refreshPurchaseInfo() async throws -> [String: Any] {
        guard enabled, !busy else { throw CommerceError.message("購入の確認は公開版で利用できます。確認中は少しお待ちください。") }
        busy = true; changed?(); defer { busy = false; changed?() }
        await refreshEntitlements(); await loadProduct()
        return ["message": product == nil ? "購入情報を取得できません。通信を確認して後でお試しください。" : "購入情報を更新しました。"]
    }
    func snapshot() -> [String: Any] {
        ["entitlement": entitlement.rawValue, "available": enabled && product != nil && !pendingApproval,
         "busy": busy, "pending": pendingApproval, "price": product?.displayPrice ?? "",
         "preview": !enabled]
    }
    func purchase() async throws -> [String: Any] {
        guard enabled else { throw CommerceError.message("評価版では購入できません。料金は発生しません。") }
        guard !busy else { throw CommerceError.message("購入の確認中です。少しお待ちください。") }
        guard !pendingApproval else { throw CommerceError.message("購入の承認を待っています。承認されると自動で反映します。") }
        guard entitlement != .removed else { return ["message": "広告はすでに除去されています。"] }
        // Lock before any suspension, including product loading, to reject concurrent bridge calls.
        busy = true; changed?(); defer { busy = false; changed?() }
        if product == nil { await loadProduct() }
        guard let product, product.type == .nonConsumable else { throw CommerceError.message("購入情報を取得できません。App Storeへの接続を確認し、後でお試しください。") }
        let message: String
        do {
            switch try await product.purchase() {
            case .success(let result):
                guard case .verified(let transaction) = result, grants(transaction) else {
                    entitlement = .checking
                    throw CommerceError.message("Appleの購入確認を完了できません。「購入を復元」をお試しください。")
                }
                entitlement = .removed; pendingApproval = false; changed?()
                await transaction.finish(); await refreshEntitlements()
                message = "広告を除去しました。通常の会話機能はそのまま使えます。"
            case .pending: pendingApproval = true; message = "購入の承認を待っています。承認されると自動で反映します。"
            case .userCancelled: message = "購入をキャンセルしました。"
            @unknown default: throw CommerceError.message("購入の状態を確認できません。「購入を復元」をお試しください。")
            }
        } catch let error as CommerceError { throw error }
        catch { throw CommerceError.message("購入を完了できません。App Storeへの接続を確認し、後でお試しください。") }
        // The caller publishes a fresh snapshot after the operation lock is released by defer.
        return ["message": message]
    }
    func restore() async throws -> [String: Any] {
        guard enabled else { throw CommerceError.message("評価版では購入の復元を実行しません。公開版の購入情報はAppleで管理されます。") }
        guard !busy else { throw CommerceError.message("購入の確認中です。少しお待ちください。") }
        busy = true; changed?(); defer { busy = false; changed?() }
        do { try await AppStore.sync() }
        catch { throw CommerceError.message("購入を復元できません。購入時のApple Accountと通信を確認してください。") }
        await refreshEntitlements(); await loadProduct()
        let message = entitlement == .removed ? "購入を復元しました。広告は表示されません。" : entitlement == .checking ? "購入の確認を完了できませんでした。時間をおいてお試しください。" : "このApple Accountに広告除去の購入は見つかりませんでした。"
        return ["message": message]
    }
}
