import UIKit

protocol SectionAction { }

enum BasicAction : SectionAction {
    case nothing
}

protocol TableViewSection {
    var cellReuseIdentifier: String { get }
    var count: Int { get }
    var headerTitle: String? { get }
    var rowHeight: CGFloat { get }

    func canSelect(_ row: Int) -> (Bool, SectionAction)
    func handleLongPress(_ row: Int) -> SectionAction
    func handleSelect(_ row: Int) -> SectionAction
    func populateCell(_ row: Int, cell: UITableViewCell)
}

/// Default implementations of Section functionality.
extension TableViewSection {
    func canSelect(_ row: Int) -> (Bool, SectionAction) {
        return (false, BasicAction.nothing)
    }

    func handleLongPress(_ row: Int) -> SectionAction {
        return BasicAction.nothing
    }

    func handleSelect(_ row: Int) -> SectionAction {
        return BasicAction.nothing
    }

    func populateCell(_ row: Int, cell: UITableViewCell) { }
}
