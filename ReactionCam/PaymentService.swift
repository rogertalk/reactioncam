import Foundation
import StoreKit
import UIKit

class PaymentService: NSObject,
    SKPaymentTransactionObserver,
    SKProductsRequestDelegate
{
    static let instance = PaymentService()

    let purchaseDidComplete = Event<Void>()
    
    @discardableResult
    func loadProducts() -> Promise<[SKProduct]> {
        if let promise = self.productsPromise {
            return promise
        }
        let (p, cb, err) = Promise<[SKProduct]>.exposed()
        self.productsCallbacks = (cb, err)
        self.productsPromise = p
        let request = SKProductsRequest(productIdentifiers: [
            "RCOINS80",
            "RCOINS420",
            "RCOINS1750",
        ])
        self.productsRequest = request
        request.delegate = self
        request.start()
        return p
    }

    func showBuyCoins() {
        PaymentService.instance.loadProducts().then { products in
            let alert = AnywhereAlertController(title: "🤑", message: "Get more Coins to spend on creator rewards and other in-app features!", preferredStyle: .alert)
            products.sorted(by: { $0.price.doubleValue < $1.price.doubleValue }).forEach {
                p in
                let f = NumberFormatter()
                f.formatterBehavior = .behavior10_4
                f.numberStyle = .currency
                f.locale = p.priceLocale
                let title: String
                if let formattedPrice = f.string(from: p.price) {
                    title = "\(p.localizedTitle) for \(formattedPrice)"
                } else {
                    title = p.localizedTitle
                }
                alert.addAction(UIAlertAction(title: title, style: .default) { _ in
                    let payment = SKMutablePayment(product: p)
                    payment.quantity = 1
                    // TODO: Set payment.applicationUsername
                    SKPaymentQueue.default().add(payment)
                })
            }
            alert.addCancel()
            alert.show()
        }
    }
    
    // MARK: - SKPaymentTransactionObserver

    func paymentQueue(_ queue: SKPaymentQueue, removedTransactions transactions: [SKPaymentTransaction]) {
        print("TODO: Handle removed transactions \(transactions)")
    }

    func paymentQueue(_ queue: SKPaymentQueue, updatedTransactions transactions: [SKPaymentTransaction]) {
        var unfinishedTransactions = [SKPaymentTransaction]()
        for transaction in transactions {
            switch transaction.transactionState {
            case .deferred:
                print("TODO: UI for deferred transaction \(transaction)")
            case .failed:
                Logging.warning("Payment Service", [
                    "Status": "Transaction failed",
                    "Error": transaction.error?.localizedDescription ?? "N/A"])
                print("TODO: UI for failed transaction \(transaction)")
            case .purchased:
                unfinishedTransactions.append(transaction)
            case .purchasing:
                print("TODO: UI for pending transaction \(transaction)")
            case .restored:
                print("TODO: Support restoring transaction \(transaction)")
            }
        }
        guard !unfinishedTransactions.isEmpty else {
            return
        }
        // Send receipt data to backend to complete any unfinished business.
        guard let url = Bundle.main.appStoreReceiptURL, let data = try? Data(contentsOf: url) else {
            Logging.danger("Payment Service", ["Status": "Could not load receipt file"])
            return
        }
        let transactionIds = unfinishedTransactions.compactMap({ $0.transactionIdentifier })
        Logging.debug("Payment Service", [
            "Status": "Registering purchases",
            "PurchaseCount": unfinishedTransactions.count,
            "IdCount": transactionIds.count])
        Intent.registerPurchase(receipt: data, purchases: transactionIds).performWithoutDispatch(BackendClient.api) {
            guard
                $0.successful && $0.code == 200,
                let data = $0.data,
                let finishedTransactionIds = data["completed_purchase_ids"] as? [String]
                else
            {
                Logging.danger("Payment Service", [
                    "Status": "Could not register payments",
                    "Code": String($0.code)])
                return
            }
            for transaction in unfinishedTransactions {
                guard let id = transaction.transactionIdentifier else {
                    continue
                }
                guard finishedTransactionIds.contains(id) else {
                    Logging.warning("Payment Service", [
                        "Status": "Transaction not finished",
                        "TransactionId": id])
                    continue
                }
                self.purchaseDidComplete.emit()
                SKPaymentQueue.default().finishTransaction(transaction)
            }
        }
    }

    // MARK: - SKProductsRequestDelegate

    func productsRequest(_ request: SKProductsRequest, didReceive response: SKProductsResponse) {
        if let (cb, _) = self.productsCallbacks {
            cb(response.products)
        }
        // TODO: Look at response.invalidProductIdentifiers
        self.productsRequest = nil
    }

    // MARK: - Private

    private var productsCallbacks: (([SKProduct]) -> (), (Error) -> ())?
    private var productsPromise: Promise<[SKProduct]>?
    private var productsRequest: SKProductsRequest?

    private override init() {
        super.init()
    }
}
