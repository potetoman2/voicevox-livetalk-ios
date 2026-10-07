import Foundation

enum DistributionPolicy {
    // No approved commercial GPT provider is wired into this app yet.
    // Enabling a plist switch must never sell an unusable conversation product.
    static let commercialConnectionAvailable = false
    // Rights are reserved; do not assume eligibility for the open-source flow.
    static let privatePlanUsagePermissionVerified = false

    static func purchasesAllowed(requested: Bool) -> Bool {
        requested && commercialConnectionAvailable
    }
    static func planUsageAllowed(requested: Bool, storeBuild: Bool) -> Bool {
        requested && !storeBuild && privatePlanUsagePermissionVerified
    }
    static func revenueAdsAllowed(requested: Bool, storeBuild: Bool) -> Bool {
        requested && storeBuild && commercialConnectionAvailable
    }
}
