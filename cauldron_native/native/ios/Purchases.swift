import Foundation
import StoreKit
#if os(macOS)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

enum Purchases {
    private static var watchers: [String] = []
    private static var listening: Task<Void, Never>?

    static func listen() {
        guard listening == nil else { return }
        listening = Task.detached {
            for await update in Transaction.updates {
                if case .verified(let transaction) = update { await transaction.finish() }
                await announce()
            }
        }
    }

    static func products(_ id: String, _ keys: [String]) {
        Task {
            do {
                let found = try await Product.products(for: keys.map(storeID))
                var products: [[String: Any]] = []
                for product in found { products.append(await described(product)) }
                answerRequest(id, "ok", ["products": products])
            } catch {
                answerRequest(id, "error", "unavailable")
            }
        }
    }

    static func buy(_ id: String, _ key: String) {
        Task {
            do {
                guard let product = try await Product.products(for: [storeID(key)]).first else {
                    return answerRequest(id, "error", "not_found")
                }
                try await bought(id, try await product.purchase())
            } catch {
                answerRequest(id, "error", "unavailable")
            }
        }
    }

    static func owned(_ id: String) {
        Task { answerRequest(id, "ok", ["owned": await entitled()]) }
    }

    static func restore(_ id: String) {
        Task {
            do {
                try await AppStore.sync()
                answerRequest(id, "ok", ["owned": await entitled()])
            } catch StoreKitError.userCancelled {
                answerRequest(id, "cancelled", nil)
            } catch {
                answerRequest(id, "error", "unavailable")
            }
        }
    }

    static func watch(_ id: String) {
        watchers.append(id)
        listen()
    }

    static func subscription(_ id: String, _ keys: [String]) {
        Task {
            guard let product = try? await Product.products(for: keys.map(storeID)).first,
                  let group = product.subscription?.subscriptionGroupID,
                  let statuses = try? await Product.SubscriptionInfo.status(for: group) else {
                return answerRequest(id, "ok", ["subscription": [:] as [String: Any]])
            }
            var found: [String: Any] = [:]
            for status in statuses {
                guard case .verified(let transaction) = status.transaction,
                      case .verified(let renewal) = status.renewalInfo else { continue }
                found["next"] = key(renewal.autoRenewPreference ?? renewal.currentProductID)
                if status.state == .subscribed || status.state == .inGracePeriod {
                    found["current"] = key(renewal.currentProductID)
                    found["expires"] = transaction.expirationDate?.timeIntervalSince1970
                }
            }
            answerRequest(id, "ok", ["subscription": found])
        }
    }

    static func transactions(_ id: String) {
        Task {
            var found: [Transaction] = []
            for await result in Transaction.all {
                if case .verified(let transaction) = result, transaction.revocationDate == nil { found.append(transaction) }
            }
            let recent = found.sorted { $0.purchaseDate > $1.purchaseDate }.prefix(10).map { transaction in
                [
                    "id": String(transaction.id),
                    "key": key(transaction.productID),
                    "purchased": transaction.purchaseDate.timeIntervalSince1970,
                    "subscription": transaction.productType == .autoRenewable
                ] as [String: Any]
            }
            answerRequest(id, "ok", ["transactions": Array(recent)])
        }
    }

    static func refund(_ id: String, _ transaction: String) {
        Task { @MainActor in
            guard let number = UInt64(transaction) else { return answerRequest(id, "error", "not_found") }
            do {
                switch try await StoreSheets.refund(number) {
                case .success: answerRequest(id, "ok", "requested")
                default: answerRequest(id, "cancelled", nil)
                }
            } catch StoreSheetError.unsupported {
                answerRequest(id, "error", "unsupported")
            } catch {
                answerRequest(id, "error", "failed")
            }
        }
    }

    static func manage() {
        Task { @MainActor in try? await StoreSheets.manage() }
    }

    static func redeem(_ id: String) {
        Task { @MainActor in
            do {
                try await StoreSheets.redeem()
                answerRequest(id, "ok", "finished")
            } catch StoreSheetError.unsupported {
                answerRequest(id, "error", "unsupported")
            } catch {
                answerRequest(id, "error", "failed")
            }
        }
    }

    private static func bought(_ id: String, _ result: Product.PurchaseResult) async throws {
        switch result {
        case .success(.verified(let transaction)):
            await transaction.finish()
            answerRequest(id, "ok", "purchased")
        case .success(.unverified):
            answerRequest(id, "error", "failed")
        case .pending:
            answerRequest(id, "ok", "pending")
        case .userCancelled:
            answerRequest(id, "cancelled", nil)
        @unknown default:
            answerRequest(id, "error", "failed")
        }
    }

    private static func announce() async {
        let owned = await entitled()
        for watcher in await MainActor.run(body: { watchers }) { answerRequest(watcher, "ok", ["owned": owned]) }
    }

    private static func entitled() async -> [String] {
        var keys: [String] = []
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result, transaction.revocationDate == nil {
                keys.append(key(transaction.productID))
            }
        }
        return keys
    }

    private static func described(_ product: Product) async -> [String: Any] {
        var described: [String: Any] = [
            "key": key(product.id),
            "name": product.displayName,
            "description": product.description,
            "price": product.displayPrice,
            "amount": NSDecimalNumber(decimal: product.price).doubleValue,
            "type": kind(product.type)
        ]
        if let subscription = product.subscription {
            let period = subscription.subscriptionPeriod
            described["period"] = ["unit": unit(period.unit), "count": period.value]
            let months = months(period)
            if months > 1 { described["price_per_month"] = (product.price / Decimal(months)).formatted(product.priceFormatStyle) }
            described["intro_eligible"] = subscription.introductoryOffer != nil ? await subscription.isEligibleForIntroOffer : false
        }
        return described
    }

    private static func unit(_ unit: Product.SubscriptionPeriod.Unit) -> String {
        switch unit {
        case .day: "day"
        case .week: "week"
        case .month: "month"
        default: "year"
        }
    }

    private static func months(_ period: Product.SubscriptionPeriod) -> Int {
        switch period.unit {
        case .month: period.value
        case .year: period.value * 12
        default: 0
        }
    }

    private static func kind(_ type: Product.ProductType) -> String {
        switch type {
        case .consumable: "consumable"
        case .autoRenewable, .nonRenewable: "subscription"
        default: "non_consumable"
        }
    }

    private static var prefix: String { (Bundle.main.bundleIdentifier ?? "") + "." }

    private static func storeID(_ key: String) -> String { prefix + key }

    private static func key(_ productID: String) -> String {
        productID.hasPrefix(prefix) ? String(productID.dropFirst(prefix.count)) : productID
    }
}

enum StoreSheetError: Error {
    case unsupported
}

@MainActor
enum StoreSheets {
    #if os(iOS)
    private static var scene: UIWindowScene? {
        UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first { $0.activationState == .foregroundActive }
            ?? UIApplication.shared.connectedScenes.first as? UIWindowScene
    }

    static func refund(_ transaction: UInt64) async throws -> Transaction.RefundRequestStatus {
        guard let scene else { throw StoreSheetError.unsupported }
        return try await Transaction.beginRefundRequest(for: transaction, in: scene)
    }

    static func manage() async throws {
        guard let scene else { return }
        try await AppStore.showManageSubscriptions(in: scene)
    }

    static func redeem() async throws {
        guard let scene else { throw StoreSheetError.unsupported }
        try await AppStore.presentOfferCodeRedeemSheet(in: scene)
    }

    static func review() {
        guard let scene else { return }
        AppStore.requestReview(in: scene)
    }
    #elseif os(macOS)
    private static var controller: NSViewController? { (NSApp.keyWindow ?? NSApp.windows.first)?.contentViewController }

    static func refund(_ transaction: UInt64) async throws -> Transaction.RefundRequestStatus {
        guard let controller else { throw StoreSheetError.unsupported }
        return try await Transaction.beginRefundRequest(for: transaction, in: controller)
    }

    static func manage() async throws {
        if let url = URL(string: "https://apps.apple.com/account/subscriptions") { NSWorkspace.shared.open(url) }
    }

    static func redeem() async throws {
        guard let controller else { throw StoreSheetError.unsupported }
        try await AppStore.presentOfferCodeRedeemSheet(from: controller)
    }

    static func review() {
        guard let controller else { return }
        AppStore.requestReview(in: controller)
    }
    #else
    static func refund(_ transaction: UInt64) async throws -> Transaction.RefundRequestStatus {
        throw StoreSheetError.unsupported
    }

    static func manage() async throws {}

    static func redeem() async throws {
        throw StoreSheetError.unsupported
    }

    static func review() {}
    #endif
}
