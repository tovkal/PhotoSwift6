import UIKit
import Photos
import PhotosUI
import SwiftUI
import Combine

private extension UICollectionView {
    func indexPathsForElements(in rect: CGRect) -> [IndexPath] {
        let allLayoutAttributes = collectionViewLayout.layoutAttributesForElements(in: rect)!
        return allLayoutAttributes.map { $0.indexPath }
    }
}

class AssetGridViewController: UIViewController {
    private enum GridSection: Int {
        case main
    }

    var fetchResult: PHFetchResult<PHAsset>!
    var availableWidth: CGFloat = 0

    private var addButtonItem: UIBarButtonItem!
    private var collectionViewFlowLayout: UICollectionViewFlowLayout!
    private var collectionView: UICollectionView!
    private var dataSource: UICollectionViewDiffableDataSource<GridSection, PHAsset>!

    fileprivate let imageManager = PHCachingImageManager()
    fileprivate var thumbnailSize: CGSize!
    fileprivate var previousPreheatRect = CGRect.zero
    private let cellSize: CGFloat = 80
    private var hasViewLoadedForFirstTime = false

    // MARK: UIViewController / Life Cycle

    init() {
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        PHPhotoLibrary.shared().unregisterChangeObserver(self)
    }

    override func loadView() {
        collectionViewFlowLayout = UICollectionViewFlowLayout()
        collectionViewFlowLayout.minimumLineSpacing = 1
        collectionViewFlowLayout.minimumInteritemSpacing = 0
        collectionViewFlowLayout.itemSize = CGSize(width: cellSize, height: cellSize)
        collectionView = UICollectionView(frame: .zero, collectionViewLayout: collectionViewFlowLayout)
        collectionView.register(GridViewCell.self, forCellWithReuseIdentifier: GridViewCell.identifier)
        collectionView.allowsMultipleSelection = true
        collectionView.delegate = self
        (collectionView as UIScrollView).delegate = self
        dataSource = UICollectionViewDiffableDataSource(collectionView: collectionView) { [weak self] collectionView, indexPath, asset in
            guard let self else { return UICollectionViewCell() }
            // Dequeue a GridViewCell.
            guard let cell = collectionView.dequeueReusableCell(withReuseIdentifier: GridViewCell.identifier, for: indexPath) as? GridViewCell
            else { fatalError("Unexpected cell in collection view") }

            // Request an image for the asset from the PHCachingImageManager.
            cell.representedAssetIdentifier = asset.localIdentifier
            imageManager.requestImage(for: asset, targetSize: thumbnailSize, contentMode: .aspectFill, options: nil, resultHandler: { image, _ in
                // UIKit may have recycled this cell by the handler's activation time.
                // Set the cell's thumbnail image only if it's still showing the same asset.
                if cell.representedAssetIdentifier == asset.localIdentifier {
                    cell.thumbnailImage = image
                }
            })

            return cell
        }

        view = collectionView
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        resetCachedAssets()
        initialFetch()
    }

    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        let width = view.bounds.inset(by: view.safeAreaInsets).width
        // Adjust the item size if the available width has changed.
        if availableWidth != width {
            availableWidth = width
            let columnCount = (availableWidth / cellSize).rounded(.towardZero)
            let itemLength = (availableWidth - columnCount - 1) / columnCount
            collectionViewFlowLayout.itemSize = CGSize(width: itemLength, height: itemLength)
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        // Start collection view at the bottom
        if !hasViewLoadedForFirstTime {
            hasViewLoadedForFirstTime = true
            let contentSize = self.collectionView.collectionViewLayout.collectionViewContentSize
            if contentSize.height > self.collectionView.bounds.size.height {
                let targetOffset = CGPoint(x: 0, y: contentSize.height - self.collectionView.bounds.size.height)
                self.collectionView.setContentOffset(targetOffset, animated: false)
            }
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        // Determine the size of the thumbnails to request from the PHCachingImageManager.
        let scale = UIScreen.main.scale
        let cellSize = collectionViewFlowLayout.itemSize
        thumbnailSize = CGSize(width: cellSize.width * scale, height: cellSize.height * scale)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        updateCachedAssets()
    }

    private func updateAssetsForAssetCollection() {
        let options = PHFetchOptions()
        options.sortDescriptors = [
            NSSortDescriptor(key: "creationDate", ascending: false),
            NSSortDescriptor(key: "modificationDate", ascending: false)
        ]

        fetchResult = PHAsset.fetchAssets(with: options)
        createSnapshotWithFetchResult()
    }

    // MARK: Asset Caching

    fileprivate func resetCachedAssets() {
        imageManager.stopCachingImagesForAllAssets()
        previousPreheatRect = .zero
    }

    /// - Tag: UpdateAssets
    fileprivate func updateCachedAssets() {
        // Update only if the view is visible.
        guard isViewLoaded && view.window != nil else { return }

        // The window you prepare ahead of time is twice the height of the visible rect.
        let visibleRect = CGRect(origin: collectionView!.contentOffset, size: collectionView!.bounds.size)
        let preheatRect = visibleRect.insetBy(dx: 0, dy: -0.5 * visibleRect.height)

        // Update only if the visible area is significantly different from the last preheated area.
        let delta = abs(preheatRect.midY - previousPreheatRect.midY)
        guard delta > view.bounds.height / 3 else { return }

        // Compute the assets to start and stop caching.
        let (addedRects, removedRects) = differencesBetweenRects(previousPreheatRect, preheatRect)
        let addedAssets = addedRects
            .flatMap { rect in collectionView!.indexPathsForElements(in: rect) }
            .map { indexPath in fetchResult.object(at: indexPath.item) }
        let removedAssets = removedRects
            .flatMap { rect in collectionView!.indexPathsForElements(in: rect) }
            .map { indexPath in fetchResult.object(at: indexPath.item) }

        // Update the assets the PHCachingImageManager is caching.
        imageManager.startCachingImages(for: addedAssets,
                                        targetSize: thumbnailSize, contentMode: .aspectFill, options: nil)
        imageManager.stopCachingImages(for: removedAssets,
                                       targetSize: thumbnailSize, contentMode: .aspectFill, options: nil)
        // Store the computed rectangle for future comparison.
        previousPreheatRect = preheatRect
    }

    fileprivate func differencesBetweenRects(_ old: CGRect, _ new: CGRect) -> (added: [CGRect], removed: [CGRect]) {
        if old.intersects(new) {
            var added = [CGRect]()
            if new.maxY > old.maxY {
                added += [CGRect(x: new.origin.x, y: old.maxY,
                                 width: new.width, height: new.maxY - old.maxY)]
            }
            if old.minY > new.minY {
                added += [CGRect(x: new.origin.x, y: new.minY,
                                 width: new.width, height: old.minY - new.minY)]
            }
            var removed = [CGRect]()
            if new.maxY < old.maxY {
                removed += [CGRect(x: new.origin.x, y: new.maxY,
                                   width: new.width, height: old.maxY - new.maxY)]
            }
            if old.minY < new.minY {
                removed += [CGRect(x: new.origin.x, y: old.minY,
                                   width: new.width, height: new.minY - old.minY)]
            }
            return (added, removed)
        } else {
            return ([new], [old])
        }
    }
}

private extension AssetGridViewController {
    func initialFetch() {
        PHPhotoLibrary.requestAuthorization(for: .readWrite) { status in
            //
        }
        PHPhotoLibrary.shared().register(self)
        self.fetchResult = nil
        self.updateAssetsForAssetCollection()
    }
}

// MARK: - UICollectionViewDelegate

extension AssetGridViewController: UICollectionViewDelegate {
}

// MARK: - UIScrollViewDelegate {

extension AssetGridViewController: UIScrollViewDelegate {
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        updateCachedAssets()
    }
}

// MARK: - PHPhotoLibraryChangeObserver

extension AssetGridViewController: PHPhotoLibraryChangeObserver {
    func photoLibraryDidChange(_ changeInstance: PHChange) {
        Task { @MainActor in
            guard let changes = changeInstance.changeDetails(for: fetchResult) else { return }
            fetchResult = changes.fetchResultAfterChanges
            createSnapshotWithFetchResult()
            resetCachedAssets()
        }
    }
}

// MARK: - Private functions

private extension AssetGridViewController {
    func createSnapshotWithFetchResult() {
        var items = [PHAsset]()
        fetchResult.enumerateObjects { (asset, _, _) in items.append(asset) }

        var snapshot = NSDiffableDataSourceSnapshot<GridSection, PHAsset>()
        snapshot.appendSections([.main])
        snapshot.appendItems(items, toSection: .main)
        dataSource.apply(snapshot, animatingDifferences: true)
    }
}
