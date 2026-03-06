import Foundation
import StoreKit
import os

private let storeLog = Logger(subsystem: "com.lihuangxiao.photon", category: "store")

@MainActor
class StoreKitService: ObservableObject {

    nonisolated static let proProductID = "com.lihuangxiao.photon.pro"
    static let freeScanLimit = 1

    @Published var isPro: Bool = false
    @Published var proProduct: Product?
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?

    private var transactionListener: Task<Void, Never>?

    // MARK: - Scan Counting

    private let scanCountKey = "completedScanCount"

    var completedScanCount: Int {
        UserDefaults.standard.integer(forKey: scanCountKey)
    }

    var canScanForFree: Bool {
        completedScanCount < Self.freeScanLimit
    }

    var freeScansRemaining: Int {
        max(0, Self.freeScanLimit - completedScanCount)
    }

    func recordCompletedScan() {
        let current = UserDefaults.standard.integer(forKey: scanCountKey)
        UserDefaults.standard.set(current + 1, forKey: scanCountKey)
        storeLog.notice("Recorded completed scan: \(current + 1)/\(Self.freeScanLimit)")
    }

    // MARK: - Init

    init() {
        transactionListener = listenForTransactions()
        Task { await checkExistingEntitlement() }
    }

    deinit {
        transactionListener?.cancel()
    }

    // MARK: - Load Products

    func loadProducts() async {
        isLoading = true
        defer { isLoading = false }

        do {
            let products = try await Product.products(for: [Self.proProductID])
            proProduct = products.first
            if proProduct == nil {
                errorMessage = "Product not available. Please try again later."
            }
        } catch {
            storeLog.error("Failed to load products: \(error.localizedDescription)")
            errorMessage = "Could not load product. Check your connection."
        }
    }

    // MARK: - Purchase

    func purchase() async {
        guard let proProduct else {
            errorMessage = "Product not available."
            return
        }
        errorMessage = nil
        isLoading = true
        defer { isLoading = false }

        do {
            let result = try await proProduct.purchase()
            switch result {
            case .success(let verification):
                if case .verified(let transaction) = verification {
                    await transaction.finish()
                    isPro = true
                    storeLog.notice("Purchase successful")
                } else {
                    errorMessage = "Purchase could not be verified."
                }
            case .userCancelled:
                break
            case .pending:
                errorMessage = "Purchase is pending approval."
            @unknown default:
                break
            }
        } catch {
            errorMessage = "Purchase failed: \(error.localizedDescription)"
        }
    }

    // MARK: - Restore

    func restore() async {
        errorMessage = nil
        isLoading = true
        defer { isLoading = false }

        do {
            try await AppStore.sync()
        } catch {
            errorMessage = "Could not connect to the App Store."
            return
        }
        await checkExistingEntitlement()
        if !isPro {
            errorMessage = "No purchase found for this Apple ID."
        }
    }

    // MARK: - Entitlements

    private func checkExistingEntitlement() async {
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result,
               transaction.productID == Self.proProductID,
               transaction.revocationDate == nil {
                isPro = true
                storeLog.notice("Found existing Pro entitlement")
                return
            }
        }
    }

    // MARK: - Transaction Listener

    private func listenForTransactions() -> Task<Void, Never> {
        Task.detached { [weak self] in
            for await result in Transaction.updates {
                if case .verified(let transaction) = result {
                    await transaction.finish()
                    if transaction.productID == StoreKitService.proProductID {
                        let revoked = transaction.revocationDate != nil
                        await MainActor.run { [weak self] in
                            self?.isPro = !revoked
                        }
                    }
                }
            }
        }
    }
}
