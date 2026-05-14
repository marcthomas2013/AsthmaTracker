import Foundation
import Combine
import StoreKit

enum MonetizationConfig {
    static var adMobAppID: String {
        (Bundle.main.object(forInfoDictionaryKey: "GADApplicationIdentifier") as? String) ?? ""
    }

    static var adMobBannerUnitID: String {
        (Bundle.main.object(forInfoDictionaryKey: "AdMobBannerUnitID") as? String) ?? ""
    }

    static var adRemovalMonthlyProductID: String {
        (Bundle.main.object(forInfoDictionaryKey: "AdRemovalMonthlyProductID") as? String) ?? ""
    }
}

@MainActor
final class MonetizationManager: ObservableObject {
    @Published private(set) var isAdRemovalActive = false
    @Published private(set) var monthlyProduct: Product?
    @Published private(set) var isPurchasing = false
    @Published var purchaseStatusMessage: String?

    private var transactionUpdatesTask: Task<Void, Never>?

    init() {
        transactionUpdatesTask = observeTransactionUpdates()

        Task {
            await refreshProductsAndEntitlements()
        }
    }

    deinit {
        transactionUpdatesTask?.cancel()
    }

    func refreshProductsAndEntitlements() async {
        await loadProducts()
        await refreshEntitlements()
    }

    func purchaseMonthlyAdRemoval() async {
        guard let product = monthlyProduct else {
            purchaseStatusMessage = "Monthly ad removal is not configured yet."
            return
        }

        isPurchasing = true
        defer { isPurchasing = false }

        do {
            let purchaseResult = try await product.purchase()
            switch purchaseResult {
            case .success(let verification):
                let transaction = try Self.checkVerified(verification)
                await transaction.finish()
                await refreshEntitlements()
                purchaseStatusMessage = "Ad removal is now active."
            case .userCancelled:
                purchaseStatusMessage = "Purchase cancelled."
            case .pending:
                purchaseStatusMessage = "Purchase is pending approval."
            @unknown default:
                purchaseStatusMessage = "Purchase state is unknown."
            }
        } catch {
            purchaseStatusMessage = "Purchase failed: \(error.localizedDescription)"
        }
    }

    func restorePurchases() async {
        do {
            try await AppStore.sync()
            await refreshEntitlements()
            purchaseStatusMessage = isAdRemovalActive
                ? "Purchases restored. Ad removal is active."
                : "No active ad-removal subscription found."
        } catch {
            purchaseStatusMessage = "Restore failed: \(error.localizedDescription)"
        }
    }

    private func loadProducts() async {
        let productID = MonetizationConfig.adRemovalMonthlyProductID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !productID.isEmpty else {
            monthlyProduct = nil
            return
        }

        do {
            let products = try await Product.products(for: [productID])
            monthlyProduct = products.first
        } catch {
            purchaseStatusMessage = "Unable to load App Store products."
            monthlyProduct = nil
        }
    }

    private func refreshEntitlements() async {
        let productID = MonetizationConfig.adRemovalMonthlyProductID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !productID.isEmpty else {
            isAdRemovalActive = false
            return
        }

        var hasActiveEntitlement = false
        for await entitlement in Transaction.currentEntitlements {
            guard let transaction = try? Self.checkVerified(entitlement) else {
                continue
            }

            if transaction.productID == productID {
                hasActiveEntitlement = true
                break
            }
        }

        isAdRemovalActive = hasActiveEntitlement
    }

    private func observeTransactionUpdates() -> Task<Void, Never> {
        Task { [weak self] in
            for await update in Transaction.updates {
                guard let self else { return }

                guard let transaction = try? Self.checkVerified(update) else {
                    continue
                }

                await transaction.finish()
                await refreshEntitlements()
            }
        }
    }

    private static func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .verified(let safe):
            return safe
        case .unverified:
            throw StoreError.failedVerification
        }
    }
}

private enum StoreError: Error {
    case failedVerification
}
