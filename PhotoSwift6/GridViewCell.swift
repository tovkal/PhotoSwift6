import UIKit

class GridViewCell: UICollectionViewCell {
    static let identifier = String(describing: GridViewCell.self)
    private let selectionImageSize: CGFloat = 20

    private lazy var imageView: UIImageView = {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        return imageView
    }()

    var representedAssetIdentifier: String!

    var thumbnailImage: UIImage! {
        didSet {
            imageView.image = thumbnailImage
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        commonInit()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func commonInit() {
        contentView.addSubview(imageView)

        imageView.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: topAnchor),
            imageView.leadingAnchor.constraint(equalTo: leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: trailingAnchor),
            imageView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        imageView.image = nil
    }
}
