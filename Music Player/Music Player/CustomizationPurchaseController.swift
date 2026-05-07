//
//  CustomizationPurchaseController.swift
//  Music Player
//
//  Created by Codex on 2026-05-07.
//

import Combine
import Foundation
import StoreKit

@MainActor
final class CustomizationPurchaseController: ObservableObject {
    @Published private(set) var hasCustomizationEntitlement = false
    @Published private(set) var hasLoadedEntitlements = false
    @Published private(set) var isLoadingProduct = false
    @Published private(set) var isPurchasing = false
    @Published var purchaseErrorMessage = ""

    private let customizationProductID = "MelonMusicCustomization"
    private var customizationProduct: Product?
    private var transactionUpdatesTask: Task<Void, Never>?
    private var hasStarted = false

    deinit {
        transactionUpdatesTask?.cancel()
    }

    func start() async {
        guard !hasStarted else { return }
        hasStarted = true

        transactionUpdatesTask = Task { [weak self] in
            for await result in Transaction.updates {
                guard let self else { return }
                await self.handle(transactionResult: result)
            }
        }

        await refreshEntitlements()
        await loadProduct(showsError: false)
    }

    func enableCustomizationIfPossible() async -> Bool {
        purchaseErrorMessage = ""

        await refreshEntitlements()
        if hasCustomizationEntitlement {
            return true
        }

        return await purchaseCustomization()
    }

    func restorePurchases() async -> Bool {
        purchaseErrorMessage = ""

        do {
            try await AppStore.sync()
            await refreshEntitlements()

            if !hasCustomizationEntitlement {
                purchaseErrorMessage = String(localized: "No Customization Purchase Found")
            }

            return hasCustomizationEntitlement
        } catch {
            purchaseErrorMessage = error.localizedDescription
            return false
        }
    }

    func refreshEntitlements() async {
        var isEntitled = false

        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else { continue }

            if transaction.productID == customizationProductID,
               transaction.revocationDate == nil {
                isEntitled = true
                break
            }
        }

        hasCustomizationEntitlement = isEntitled
        hasLoadedEntitlements = true
    }

    private func loadProduct(showsError: Bool) async {
        guard customizationProduct == nil else { return }

        isLoadingProduct = true
        defer { isLoadingProduct = false }

        do {
            customizationProduct = try await Product.products(for: [customizationProductID]).first

            if customizationProduct == nil, showsError {
                purchaseErrorMessage = String(localized: "Customization Purchase Unavailable")
            }
        } catch {
            if showsError {
                purchaseErrorMessage = error.localizedDescription
            }
        }
    }

    private func purchaseCustomization() async -> Bool {
        await loadProduct(showsError: true)

        guard let customizationProduct else {
            purchaseErrorMessage = String(localized: "Customization Purchase Unavailable")
            return false
        }

        isPurchasing = true
        defer { isPurchasing = false }

        do {
            let result = try await customizationProduct.purchase()

            switch result {
            case .success(let verification):
                guard case .verified(let transaction) = verification else {
                    purchaseErrorMessage = String(localized: "Purchase Could Not Be Verified")
                    return false
                }

                hasCustomizationEntitlement = transaction.revocationDate == nil
                await transaction.finish()
                return hasCustomizationEntitlement

            case .pending:
                purchaseErrorMessage = String(localized: "Purchase Pending")
                return false

            case .userCancelled:
                return false

            @unknown default:
                purchaseErrorMessage = String(localized: "Purchase Failed")
                return false
            }
        } catch {
            purchaseErrorMessage = error.localizedDescription
            return false
        }
    }

    private func handle(transactionResult: VerificationResult<Transaction>) async {
        guard case .verified(let transaction) = transactionResult else { return }

        if transaction.productID == customizationProductID {
            hasCustomizationEntitlement = transaction.revocationDate == nil
            await transaction.finish()
        }
    }
}
