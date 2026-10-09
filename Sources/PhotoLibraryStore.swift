import Combine
import CoreLocation
import Photos
import PhotosUI
import UIKit

@MainActor
final class PhotoLibraryStore: NSObject, ObservableObject {
    @Published private(set) var authorizationStatus: PHAuthorizationStatus
    @Published private(set) var assets: [PHAsset] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isWriting = false
    @Published var errorMessage: String?

    private let imageManager = PHCachingImageManager()

    override init() {
        authorizationStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        super.init()

        if authorizationStatus == .authorized || authorizationStatus == .limited {
            loadAssets()
        }
    }

    func refreshAuthorization() {
        authorizationStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        if authorizationStatus == .authorized || authorizationStatus == .limited {
            loadAssets()
        }
    }

    func requestAccess() {
        PHPhotoLibrary.requestAuthorization(for: .readWrite) { [weak self] status in
            DispatchQueue.main.async {
                guard let self else { return }
                self.authorizationStatus = status
                if status == .authorized || status == .limited {
                    self.loadAssets()
                }
            }
        }
    }

    func loadAssets() {
        guard authorizationStatus == .authorized || authorizationStatus == .limited else {
            assets = []
            return
        }

        isLoading = true

        let options = PHFetchOptions()
        options.sortDescriptors = [
            NSSortDescriptor(key: "creationDate", ascending: false)
        ]

        let result = PHAsset.fetchAssets(with: .image, options: options)
        var fetched: [PHAsset] = []
        fetched.reserveCapacity(result.count)
        result.enumerateObjects { asset, _, _ in
            fetched.append(asset)
        }

        assets = fetched
        isLoading = false
    }

    func asset(withIdentifier identifier: String) -> PHAsset? {
        PHAsset.fetchAssets(
            withLocalIdentifiers: [identifier],
            options: nil
        ).firstObject
    }

    @discardableResult
    func requestImage(
        for asset: PHAsset,
        targetSize: CGSize,
        contentMode: PHImageContentMode,
        completion: @escaping (UIImage?) -> Void
    ) -> PHImageRequestID {
        let options = PHImageRequestOptions()
        options.deliveryMode = .opportunistic
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = true

        return imageManager.requestImage(
            for: asset,
            targetSize: targetSize,
            contentMode: contentMode,
            options: options
        ) { image, info in
            let cancelled = (info?[PHImageCancelledKey] as? Bool) ?? false
            guard !cancelled else { return }
            DispatchQueue.main.async {
                completion(image)
            }
        }
    }

    func cancelImageRequest(_ requestID: PHImageRequestID) {
        guard requestID != PHInvalidImageRequestID else { return }
        imageManager.cancelImageRequest(requestID)
    }

    func presentLimitedLibraryPicker(from viewController: UIViewController) {
        PHPhotoLibrary.shared().presentLimitedLibraryPicker(from: viewController) { [weak self] (_: [String]) in
            DispatchQueue.main.async {
                self?.loadAssets()
            }
        }
    }

    func updateLocation(
        assetID: String,
        location: CLLocation,
        completion: @escaping (Result<PHAsset, Error>) -> Void
    ) {
        guard !isWriting else { return }
        guard let asset = asset(withIdentifier: assetID) else {
            completion(.failure(PhotoLibraryStoreError.assetNotFound))
            return
        }

        isWriting = true
        PHPhotoLibrary.shared().performChanges {
            PHAssetChangeRequest(for: asset).location = location
        } completionHandler: { [weak self] success, error in
            DispatchQueue.main.async {
                guard let self else { return }
                self.isWriting = false

                guard success else {
                    completion(.failure(error ?? PhotoLibraryStoreError.writeFailed))
                    return
                }
                guard let refreshed = self.asset(withIdentifier: assetID) else {
                    completion(.failure(PhotoLibraryStoreError.assetNotFoundAfterWrite))
                    return
                }
                guard let saved = refreshed.location,
                      Self.coordinatesMatch(saved.coordinate, location.coordinate) else {
                    completion(.failure(PhotoLibraryStoreError.verificationFailed("GPS")))
                    return
                }

                self.loadAssets()
                completion(.success(refreshed))
            }
        }
    }

    func updateCreationDate(
        assetID: String,
        date: Date,
        completion: @escaping (Result<PHAsset, Error>) -> Void
    ) {
        guard !isWriting else { return }
        guard let asset = asset(withIdentifier: assetID) else {
            completion(.failure(PhotoLibraryStoreError.assetNotFound))
            return
        }

        isWriting = true
        PHPhotoLibrary.shared().performChanges {
            PHAssetChangeRequest(for: asset).creationDate = date
        } completionHandler: { [weak self] success, error in
            DispatchQueue.main.async {
                guard let self else { return }
                self.isWriting = false

                guard success else {
                    completion(.failure(error ?? PhotoLibraryStoreError.writeFailed))
                    return
                }
                guard let refreshed = self.asset(withIdentifier: assetID) else {
                    completion(.failure(PhotoLibraryStoreError.assetNotFoundAfterWrite))
                    return
                }
                guard let saved = refreshed.creationDate,
                      abs(saved.timeIntervalSince(date)) < 1 else {
                    completion(.failure(PhotoLibraryStoreError.verificationFailed("拍摄日期")))
                    return
                }

                self.loadAssets()
                completion(.success(refreshed))
            }
        }
    }

    private static func coordinatesMatch(
        _ lhs: CLLocationCoordinate2D,
        _ rhs: CLLocationCoordinate2D
    ) -> Bool {
        abs(lhs.latitude - rhs.latitude) < 0.0000001 &&
        abs(lhs.longitude - rhs.longitude) < 0.0000001
    }
}

enum PhotoLibraryStoreError: LocalizedError {
    case assetNotFound
    case assetNotFoundAfterWrite
    case writeFailed
    case verificationFailed(String)

    var errorDescription: String? {
        switch self {
        case .assetNotFound:
            return "找不到目标照片，可能已被移出当前授权范围"
        case .assetNotFoundAfterWrite:
            return "写入完成，但无法重新读取目标照片"
        case .writeFailed:
            return "照片库没有完成修改"
        case let .verificationFailed(field):
            return "\(field) 写入后校验失败"
        }
    }
}
