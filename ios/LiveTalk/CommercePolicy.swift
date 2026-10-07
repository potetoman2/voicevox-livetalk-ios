import Foundation

enum AdEntitlement: String { case checking, free, removed }

enum AdAudience: String {
    case adult, teen
    var underAgeOfConsent: Bool { self == .teen }
}

struct PurchaseEvidence {
    let verified: Bool
    let productID: String
    let bundleID: String
    let nonConsumable: Bool
    let revoked: Bool
    let upgraded: Bool
}

enum CommercePolicy {
    static let removalProductID = "jp.livetalk.mobile.remove_ads"
    static let adConsentVersion = "google-ads:2026-10-07:2"
    static let testApplicationID = "ca-app-pub-3940256099942544~1458002511"
    static let testBannerID = "ca-app-pub-3940256099942544/2435281174"

    static func grantsAdRemoval(_ evidence: PurchaseEvidence, bundleID: String) -> Bool {
        evidence.verified && evidence.productID == removalProductID && evidence.bundleID == bundleID
            && evidence.nonConsumable && !evidence.revoked && !evidence.upgraded && !bundleID.isEmpty
    }

    static func allowsAd(entitlement: AdEntitlement, optedIn: Bool, consentReady: Bool,
                         foreground: Bool, settingsVisible: Bool, conversationActive: Bool,
                         carPlay: Bool, presenting: Bool, purchasing: Bool) -> Bool {
        entitlement == .free && optedIn && consentReady && foreground && settingsVisible
            && !conversationActive && !carPlay && !presenting && !purchasing
    }

    // A foreground return must not revive a consent operation invalidated while suspended.
    static func acceptsConsentCompletion(expected: Int, current: Int, foreground: Bool,
                                         entitlement: AdEntitlement, conversationActive: Bool,
                                         carPlay: Bool, purchasing: Bool, requiresFree: Bool = true) -> Bool {
        expected == current && foreground && (!requiresFree || entitlement == .free)
            && !conversationActive && !carPlay && !purchasing
    }

    static func validApplicationID(_ value: String, production: Bool) -> Bool {
        validID(value, separator: "~", digits: 10) && (!production || !value.hasPrefix("ca-app-pub-3940256099942544"))
    }
    static func validBannerID(_ value: String, production: Bool) -> Bool {
        validID(value, separator: "/", digits: 10) && (!production || !value.hasPrefix("ca-app-pub-3940256099942544"))
    }
    private static func validID(_ value: String, separator: String, digits: Int) -> Bool {
        value.range(of: "^ca-app-pub-[0-9]{16}" + NSRegularExpression.escapedPattern(for: separator) + "[0-9]{\(digits)}$", options: .regularExpression) != nil
    }
}

enum CommerceError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let text) = self { return text }; return nil }
}
