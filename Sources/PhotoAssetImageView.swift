import Photos
import SwiftUI
import UIKit

struct PhotoAssetImageView: View {
    @EnvironmentObject private var photoLibrary: PhotoLibraryStore

    let asset: PHAsset
    let contentMode: ContentMode
    let targetSize: CGSize

    @State private var image: UIImage?
    @State private var requestID: PHImageRequestID = PHInvalidImageRequestID

    var body: some View {
        ZStack {
            Color(uiColor: .secondarySystemBackground)

            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            } else {
                ProgressView()
            }
        }
        .clipped()
        .onAppear(perform: requestImage)
        .onDisappear(perform: cancelRequest)
    }

    private func requestImage() {
        cancelRequest()
        let scale = UIScreen.main.scale
        let pixels = CGSize(
            width: targetSize.width * scale,
            height: targetSize.height * scale
        )
        let photoContentMode: PHImageContentMode
        switch contentMode {
        case .fit:
            photoContentMode = .aspectFit
        case .fill:
            photoContentMode = .aspectFill
        }
        requestID = photoLibrary.requestImage(
            for: asset,
            targetSize: pixels,
            contentMode: photoContentMode
        ) { loadedImage in
            if let loadedImage {
                image = loadedImage
            }
        }
    }

    private func cancelRequest() {
        photoLibrary.cancelImageRequest(requestID)
        requestID = PHInvalidImageRequestID
    }
}
