I have the following code:

```swift
extension AssetGridViewController: PHPhotoLibraryChangeObserver {
    func photoLibraryDidChange(_ changeInstance: PHChange) {
        Task { @MainActor in
            guard let changes = changeInstance.changeDetails(for: fetchResult) else { return }
            fetchResult = changes.fetchResultAfterChanges
        }
    }
}
```

With Swift 6, this generates a compilation error: `Main actor-isolated instance method 'photoLibraryDidChange' cannot be used to satisfy nonisolated protocol requirement`. The error includes to fix-it suggestions:

1. Adding `nonisolated` to the function (`nonisolated func photoLibraryDidChange(_ changeInstance: PHChange)`)
2. Adding `@preconcurrency` to the protocol conformance (`extension AssetGridViewController: @preconcurrency PHPhotoLibraryChangeObserver {`)

Both options generate a runtime error: `EXC_BREAKPOINT (code=1, subcode=0x105b7c400)`. For context, `AssetGridViewController` is a regular `UIViewController`.

Any ideas on how to fix this?