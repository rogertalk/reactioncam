import UIKit

fileprivate let SECTION_UPLOADS = 0
fileprivate let SECTION_PINNED = 1
fileprivate let SECTION_CONTENT = 2

protocol ContentCollectionDelegate {
    func contentCollection(_ contentCollectionView: UICollectionView, didScrollTo offset: CGPoint)
    func contentCollection(_ contentCollectionView: UICollectionView, didSelectUpload upload: UploadJob, at indexPath: IndexPath)
}
    
class ContentCollectionView: UICollectionView, UICollectionViewDataSource, UICollectionViewDelegate, UICollectionViewDelegateFlowLayout {

    var contentCollectionDelegate: ContentCollectionDelegate?
    var headerTitle: String?
    
    override func awakeFromNib() {
        super.awakeFromNib()
        self.delegate = self
        self.dataSource = self        
        self.register(UINib(nibName: "ContentGridCell", bundle: nil), forCellWithReuseIdentifier: "ContentGridCell")
        self.register(UINib(nibName: "UploadCell", bundle: nil), forCellWithReuseIdentifier: "UploadCell")
        self.register(UINib(nibName: "ContentCollectionHeaderView", bundle: nil), forSupplementaryViewOfKind: UICollectionElementKindSectionHeader, withReuseIdentifier: "ContentCollectionHeaderView")
        self.contentInset = UIEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        self.indicatorStyle = .white
    }
    
    var pinnedContent: PinnedContent? {
        didSet {
            self.reloadData()
        }
    }
    
    var content = [Content]() {
        didSet {
            // TODO
            self.reloadData()
        }
    }
    
    var uploads = [UploadJob]() {
        didSet {
            self.uploadEventsHooked = !self.uploads.isEmpty
            // TODO
            self.reloadData()
        }
    }

    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, referenceSizeForHeaderInSection section: Int) -> CGSize {
        return section == 0 && self.headerTitle != nil ? CGSize(width: collectionView.bounds.width, height: 80) : .zero
    }
    
    func collectionView(_ collectionView: UICollectionView, viewForSupplementaryElementOfKind kind: String, at indexPath: IndexPath) -> UICollectionReusableView {
        guard indexPath.section == 0, let header = self.headerTitle else {
            return UICollectionReusableView()
        }
        let headerView = self.dequeueReusableSupplementaryView(ofKind: kind, withReuseIdentifier: "ContentCollectionHeaderView", for: indexPath) as! ContentCollectionHeaderView
        headerView.titleLabel.text = header
        return headerView
    }
    
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        switch indexPath.section {
        case SECTION_UPLOADS:
            let cell = self.dequeueReusableCell(withReuseIdentifier: "UploadCell", for: indexPath) as! UploadCell
            cell.upload = self.uploads[indexPath.row]
            return cell
        case SECTION_PINNED:
            let content = self.pinnedContent!
            let cell = self.dequeueReusableCell(withReuseIdentifier: "ContentGridCell", for: indexPath) as! ContentGridCell
            if let url = content.thumbnailURL {
                cell.thumbnailImageView.af_setImageBiased(withURL: url, placeholderImage: #imageLiteral(resourceName: "relatedContent"))
            }
            cell.titleLabel.text = content.title
            cell.pinnedBadgeView.isHidden = false
            return cell
        case SECTION_CONTENT:
            // TODO: Logging
            // Logging.log("Profile Content Tapped", ["Index": indexPath.row, "OwnProfile": self.account?.isCurrentUser ?? false])

            let content = self.content[indexPath.row]
            let cell = self.dequeueReusableCell(withReuseIdentifier: "ContentGridCell", for: indexPath) as! ContentGridCell
            if let url = content.thumbnailURL {
                cell.thumbnailImageView.af_setImageBiased(withURL: url, placeholderImage: #imageLiteral(resourceName: "relatedContent"))
            }
            cell.titleLabel.text = content.title ?? content.relatedTo?.title ?? ""
            return cell
        default:
            return UICollectionViewCell()
        }
    }
    
    func collectionView(_ collectionView: UICollectionView, shouldHighlightItemAt indexPath: IndexPath) -> Bool {
        return true
    }
    
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        switch indexPath.section {
        case SECTION_PINNED:
            guard let content = self.pinnedContent else {
                break
            }
            TabBarController.select(contentId: content.id)
        case SECTION_CONTENT:
            TabBarController.select(contentList: self.content, presetContentId: self.content[indexPath.row].id)
        case SECTION_UPLOADS:
            self.contentCollectionDelegate?.contentCollection(self, didSelectUpload: self.uploads[indexPath.row], at: indexPath)
        default:
            break
        }
    }
    
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        switch section {
        case SECTION_UPLOADS:
            return self.uploads.count
        case SECTION_CONTENT:
            return self.content.count
        case SECTION_PINNED:
            return self.pinnedContent == nil ? 0 : 1
        default:
            return 0
        }
    }
    
    func numberOfSections(in collectionView: UICollectionView) -> Int {
        return 3
    }
    
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        switch indexPath.section {
        case SECTION_UPLOADS:
            return CGSize(width: self.bounds.width - 32, height: 50)
        case SECTION_PINNED:
            let width = self.bounds.width
            return CGSize(width: self.bounds.width - 32, height: width * 9 / 16 + 86)
        case SECTION_CONTENT:
            let width = (self.bounds.width - 32) / 2 - 4
            return CGSize(width: width, height: width * 9 / 16 + 72)
        default:
            return .zero
        }
    }
    
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, minimumInteritemSpacingForSectionAt section: Int) -> CGFloat {
        return 8
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        self.contentCollectionDelegate?.contentCollection(self, didScrollTo: self.contentOffset)
    }
    
    // MARK: Private
    
    private var uploadEventsHooked = false {
        didSet {
            guard oldValue != self.uploadEventsHooked else {
                return
            }
            if self.uploadEventsHooked {
                UploadService.instance.uploadCompleted.addListener(self, method: ContentCollectionView.handleUploadCompleted)
                UploadService.instance.uploadProgress.addListener(self, method: ContentCollectionView.handleUploadProgress)
            } else {
                UploadService.instance.uploadCompleted.removeListener(self)
                UploadService.instance.uploadProgress.removeListener(self)
            }
        }
    }
    
    private func handleUploadCompleted(job: CompletedUploadJob) {
        guard let i = self.uploads.index(where: { $0.id == job.id }) else {
            return
        }
        self.uploads.remove(at: i)
    }
    
    private func handleUploadProgress(job: UploadJob) {
        guard job.isVisible else {
            return
        }
        if let i = self.uploads.index(where: { $0.id == job.id }) {
            self.uploads[i] = job
            let indexPath = IndexPath(item: i, section: SECTION_UPLOADS)
            (self.cellForItem(at: indexPath) as? UploadCell)?.upload = job
        } else {
            // TODO: Animate
            self.uploads.insert(job, at: 0)
        }
    }
}

class ContentGridCell: UICollectionViewCell {
    @IBOutlet weak var thumbnailImageView: UIImageView!
    @IBOutlet weak var titleLabel: UILabel!
    @IBOutlet weak var pinnedBadgeView: UIView!

    override func awakeFromNib() {
        super.awakeFromNib()
        self.pinnedBadgeView.setHeavyShadow()
    }

    override func prepareForReuse() {
        self.thumbnailImageView.af_cancelImageRequest()
        self.thumbnailImageView.image = #imageLiteral(resourceName: "relatedContent")
        self.titleLabel.text = nil
        self.pinnedBadgeView.isHidden = true
    }
}

class ContentCollectionHeaderView: UICollectionReusableView {
    @IBOutlet weak var titleLabel: UILabel!
    
}
