import UIKit

fileprivate let HEADER_HEIGHT = 20.0

class TopArtistsViewController :
    UIViewController,
    UICollectionViewDataSource,
    UICollectionViewDelegate,
    UICollectionViewDelegateFlowLayout {

    @IBOutlet weak var artistsCollection: UICollectionView!
    
    override var preferredStatusBarStyle: UIStatusBarStyle {
        return .lightContent
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        self.statusIndicatorView = StatusIndicatorView.create(container: self.view)
        
        self.artistsCollection.dataSource = self
        self.artistsCollection.delegate = self
        self.statusIndicatorView.showLoading()
        Intent.getTopCreators().perform(BackendClient.api) {
            self.statusIndicatorView.hide()
            guard $0.successful, let data = $0.data?["data"] as? [DataType] else {
                return
            }
            self.artists = data.compactMap {
                guard let account = $0["account"] as? DataType, let score = $0["score"] as? Int else {
                    return nil
                }
                return TopArtist(account: AccountBase(data: account), reactionCount: score)
            }
            self.artistsCollection.reloadData()
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        self.artistsCollection.setNeedsLayout()
    }
    
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let artist = self.artists[indexPath.row]
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "ArtistCell", for: indexPath) as! ArtistCell
        if let url = artist.account.imageURL {
            cell.avatarImageView.af_setImage(withURL: url)
        } else {
            cell.avatarImageView.image = #imageLiteral(resourceName: "single")
        }
        cell.usernameLabel.text = artist.account.displayName == artist.account.username ? "@\(artist.account.username)" : artist.account.displayName
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        let reactionCount = formatter.string(from: NSNumber(value: artist.reactionCount))!
        cell.reactionCountLabel.text = "\(reactionCount) \(artist.reactionCount == 1 ? "reaction" : "reactions")"
        return cell
    }
    
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        self.statusIndicatorView.showLoading()
        Intent.getProfile(identifier: String(self.artists[indexPath.row].account.id)).perform(BackendClient.api) {
            self.statusIndicatorView.hide()
            
            guard $0.successful, let data = $0.data else {
                return
            }
            TabBarController.select(account: Profile(data: data))
        }
    }
    
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return self.artists.count
    }
    
    func numberOfSections(in collectionView: UICollectionView) -> Int {
        return 1
    }

    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, insetForSectionAt section: Int) -> UIEdgeInsets {
        if #available(iOS 11.0, *) {
            return UIEdgeInsets(top: 76 + self.view.safeAreaInsets.top, left: 16, bottom: 16, right: 16)
        } else {
            return UIEdgeInsets(top: 96, left: 16, bottom: 16, right: 16)
        }
    }

    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        let width = (self.view.bounds.width - 48) / 2 - 4
        return CGSize(width: width, height: width)
    }
    
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, minimumInteritemSpacingForSectionAt section: Int) -> CGFloat {
        return 16
    }

    func scrollToTop() {
        self.artistsCollection.setContentOffset(CGPoint(x: 0.0, y: -HEADER_HEIGHT), animated: true)
    }

    // MARK: - Actions

    @IBAction func leaderboardTapped(_ sender: Any) {
        Logging.log("Leaderboard Tapped")

        guard let leaderboard = Bundle.main.loadNibNamed("TopUsersViewController", owner: nil, options: nil)?.first as? TopUsersViewController else {
            return
        }
        self.navigationController?.pushViewController(leaderboard, animated: true)
    }

    // MARK: - Private
    
    private var artists = [TopArtist]()
    private var statusIndicatorView: StatusIndicatorView!
    
    struct TopArtist {
        var account: AccountBase
        var reactionCount: Int
    }
}

class ArtistCell: UICollectionViewCell {
    @IBOutlet weak var avatarImageView: UIImageView!
    @IBOutlet weak var usernameLabel: UILabel!
    @IBOutlet weak var reactionCountLabel: UILabel!

    override func layoutSubviews() {
        super.layoutSubviews()
        self.avatarImageView.layer.cornerRadius = self.avatarImageView.frame.width / 2
    }
}
