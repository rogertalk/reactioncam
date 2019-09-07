import Foundation
import XLActionController

public class ActionSheetController: ActionController<ActionSheetCell, String, ActionSheetHeader, String, UICollectionReusableView, Void> {
    
    public override var prefersStatusBarHidden: Bool {
        return false
    }
    
    required public init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
    }
    
    public override init(nibName nibNameOrNil: String? = nil, bundle nibBundleOrNil: Bundle? = nil) {
        super.init(nibName: nibNameOrNil, bundle: nibBundleOrNil)
        
        collectionViewLayout.minimumLineSpacing = 0
        collectionViewLayout.sectionInset = UIEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
        
        settings.behavior.hideOnScrollDown = false
        settings.animation.scale = nil
        settings.animation.present.duration = 0.6
        settings.animation.dismiss.duration = 0.5
        settings.animation.dismiss.options = .curveEaseIn
        settings.animation.dismiss.offset = 30
        
        cellSpec = .nibFile(nibName: "ActionSheetCell", bundle: Bundle(for: ActionSheetCell.self), height: { _ in 60})
        sectionHeaderSpec = .cellClass(height: { _ in 5 })
        headerSpec = .cellClass(height: { [weak self] (headerData: String) in
            guard let me = self else { return 0 }
            let label = UILabel(frame: CGRect(x: 0, y: 0, width: me.view.frame.width - 40, height: CGFloat.greatestFiniteMagnitude))
            label.numberOfLines = 0
            label.font = .systemFont(ofSize: 17.0)
            label.text = headerData
            label.sizeToFit()
            return label.frame.size.height + 20
        })
        
        onConfigureHeader = { [weak self] header, headerData in
            guard let me = self else { return }
            header.label.frame = CGRect(x: 0, y: 0, width: me.view.frame.size.width - 40, height: CGFloat.greatestFiniteMagnitude)
            header.label.text = headerData
            header.label.sizeToFit()
            header.label.center = CGPoint(x: header.frame.size.width  / 2, y:header.frame.size.height / 2)
        }
        onConfigureSectionHeader = { sectionHeader, sectionHeaderData in
            sectionHeader.backgroundColor = UIColor(white: 0.95, alpha: 1.0)
        }
        onConfigureCellForAction = { [weak self] cell, action, indexPath in
            cell.setup(action.data, detail: nil, image: nil)
            cell.separatorView?.isHidden = indexPath.item == self!.collectionView.numberOfItems(inSection: indexPath.section) - 1
            cell.alpha = action.enabled ? 1.0 : 0.5
            let color: UIColor
            switch action.style {
            case .cancel:
                color = UIColor.white.withAlphaComponent(0.4)
            case .destructive:
                color = .red
            default:
                color = .white
            }
            cell.actionTitleLabel?.textColor = color
        }

        let visualEffectView = UIVisualEffectView(effect: UIBlurEffect(style: .dark))
        self.backgroundView = visualEffectView
    }

    convenience init(title: String? = nil) {
        self.init()
        self.headerData = title
    }
    
    func addCancel(title: String = "Cancel", handler: (() -> ())? = nil) {
        self.addAction(Action(title, style: .cancel) { _ in
            handler?()
        })
    }
}

public class ActionSheetCell: ActionCell {
    
    public override init(frame: CGRect) {
        super.init(frame: frame)
        initialize()
    }
    
    required public init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
    }
    
    public override func awakeFromNib() {
        super.awakeFromNib()
        initialize()
    }
    
    func initialize() {
        backgroundColor = .clear
        let backgroundView = UIView()
        backgroundView.backgroundColor = UIColor(white: 1, alpha: 0.15)
        selectedBackgroundView = backgroundView
        separatorView?.backgroundColor = UIColor(white: 1, alpha: 0.15)
    }
}

public class ActionSheetSection: Section<String, Void> {
    public override init() {
        super.init()
        self.data = ()
    }
}

public class ActionSheetHeader: UICollectionReusableView {
    
    lazy var label: UILabel = {
        let label = UILabel()
        label.textColor = UIColor.white.withAlphaComponent(0.4)
        label.numberOfLines = 0
        label.textAlignment = .center
        label.lineBreakMode = .byWordWrapping
        label.font = .systemFont(ofSize: 20, weight: .regular)
        return label
    }()
    
    public override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        addSubview(label)
    }
    
    required public init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
