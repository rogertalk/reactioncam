import Foundation

struct Wallet {
    let balance: Int
    let created: Date
    let id: String

    init(data: DataType) {
        self.balance = data["balance"] as! Int
        self.created = Date(timeIntervalSince1970: (data["created"] as! Double) / 1000)
        self.id = data["id"] as! String
    }
}
