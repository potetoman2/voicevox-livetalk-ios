import Foundation

var checks = 0
func check(_ condition: Bool, _ message: String) { checks += 1; precondition(condition, message) }
let bundle = "jp.livetalk.mobile"
func evidence(verified: Bool = true, product: String = CommercePolicy.removalProductID,
              app: String = "jp.livetalk.mobile", permanent: Bool = true,
              revoked: Bool = false, upgraded: Bool = false) -> PurchaseEvidence {
    PurchaseEvidence(verified: verified, productID: product, bundleID: app, nonConsumable: permanent, revoked: revoked, upgraded: upgraded)
}
check(CommercePolicy.grantsAdRemoval(evidence(), bundleID: bundle), "Verified permanent purchase grants removal")
check(!CommercePolicy.grantsAdRemoval(evidence(verified: false), bundleID: bundle), "Unverified purchases never unlock")
check(!CommercePolicy.grantsAdRemoval(evidence(product: "other"), bundleID: bundle), "Different SKU never unlocks")
check(!CommercePolicy.grantsAdRemoval(evidence(app: "other.app"), bundleID: bundle), "Another app receipt never unlocks")
check(!CommercePolicy.grantsAdRemoval(evidence(permanent: false), bundleID: bundle), "Subscription or consumable never unlocks")
check(!CommercePolicy.grantsAdRemoval(evidence(revoked: true), bundleID: bundle), "Refund or revocation removes rights")
check(!CommercePolicy.grantsAdRemoval(evidence(upgraded: true), bundleID: bundle), "Superseded rights never unlock")
check(!CommercePolicy.grantsAdRemoval(evidence(app: ""), bundleID: ""), "Missing app identity cannot grant rights")
func ad(_ state: AdEntitlement = .free, optIn: Bool = true, consent: Bool = true,
        foreground: Bool = true, settings: Bool = true, conversation: Bool = false,
        car: Bool = false, presenting: Bool = false, purchase: Bool = false) -> Bool {
    CommercePolicy.allowsAd(entitlement: state, optedIn: optIn, consentReady: consent,
        foreground: foreground, settingsVisible: settings, conversationActive: conversation,
        carPlay: car, presenting: presenting, purchasing: purchase)
}
check(ad(), "Consenting free user may see settings banner")
check(!ad(.checking), "Startup cannot show an ad before rights are known")
check(!ad(.removed), "Purchased app never starts ads")
check(!ad(optIn: false), "No processing consent means no ads")
check(!ad(consent: false), "Provider consent failure means no ads")
check(!ad(foreground: false), "No background ads")
check(!ad(settings: false), "Conversation page has no ads")
check(!ad(conversation: true), "Active call, listening, synthesis or reply blocks ads")
check(!ad(car: true), "No CarPlay ads")
check(!ad(presenting: true), "Consent or other modal blocks ads")
check(!ad(purchase: true), "No ads while buying or restoring")
check(CommercePolicy.validApplicationID(CommercePolicy.testApplicationID, production: false), "Official preview app ID")
check(!CommercePolicy.validApplicationID(CommercePolicy.testApplicationID, production: true), "Test app ID blocked in production")
check(CommercePolicy.validBannerID(CommercePolicy.testBannerID, production: false), "Official test banner ID")
check(!CommercePolicy.validBannerID(CommercePolicy.testBannerID, production: true), "Test unit blocked in production")
check(!CommercePolicy.validBannerID("ca-app-pub-1/2", production: false), "Malformed unit blocked")
check(!CommercePolicy.validApplicationID("ca-app-pub-1234567890123456/1234567890", production: true), "Wrong separator blocked")
func completion(_ expected: Int = 2, current: Int = 2, foreground: Bool = true,
                state: AdEntitlement = .free, conversation: Bool = false,
                car: Bool = false, purchase: Bool = false, requiresFree: Bool = true) -> Bool {
    CommercePolicy.acceptsConsentCompletion(expected: expected, current: current,
        foreground: foreground, entitlement: state, conversationActive: conversation,
        carPlay: car, purchasing: purchase, requiresFree: requiresFree)
}
check(completion(), "Current foreground consent can complete")
check(!completion(current: 3), "Deletion or withdrawal invalidates a delayed consent result")
check(!completion(current: 3, foreground: true), "Foreground return cannot revive an old consent prompt")
check(!completion(foreground: false), "Background consent result is ignored")
check(!completion(state: .checking), "Unchecked rights cannot start consent processing")
check(!completion(state: .removed), "A completed purchase blocks delayed Google consent")
check(!completion(conversation: true), "Native speech blocks delayed consent")
check(!completion(car: true), "CarPlay blocks delayed consent")
check(!completion(purchase: true), "A pending purchase operation blocks delayed consent")
check(completion(state: .removed, requiresFree: false), "Purchased users may still withdraw ad consent")
check(!completion(current: 3, state: .removed, requiresFree: false), "Withdrawal still rejects a stale prompt")
check(AdAudience(rawValue: "teen")?.underAgeOfConsent == true, "Teen requests use restricted consent")
check(AdAudience(rawValue: "adult")?.underAgeOfConsent == false, "Changed adult audience is reflected")
check(AdAudience(rawValue: "unknown") == nil, "Invalid imported audience is never accepted")
print("Commerce policy: \(checks) assertions passed. StoreKit payment/restore still requires StoreKit or sandbox integration tests.")
