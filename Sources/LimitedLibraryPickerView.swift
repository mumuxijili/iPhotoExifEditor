import Photos
import PhotosUI
import SwiftUI
import UIKit

struct LimitedLibraryPickerView: UIViewControllerRepresentable {
    let onFinish: () -> Void

    func makeUIViewController(context: Context) -> LimitedLibraryPickerController {
        let controller = LimitedLibraryPickerController()
        controller.onFinish = onFinish
        return controller
    }

    func updateUIViewController(
        _ controller: LimitedLibraryPickerController,
        context: Context
    ) {
        controller.onFinish = onFinish
    }
}

final class LimitedLibraryPickerController: UIViewController {
    var onFinish: (() -> Void)?
    private var didPresentPicker = false
    private var didFinish = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        let activityIndicator = UIActivityIndicatorView(style: .medium)
        activityIndicator.startAnimating()
        activityIndicator.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(activityIndicator)

        NSLayoutConstraint.activate([
            activityIndicator.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            activityIndicator.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard !didPresentPicker else { return }
        didPresentPicker = true

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            guard self.view.window != nil,
                  PHPhotoLibrary.authorizationStatus(for: .readWrite) == .limited else {
                self.finishOnce()
                return
            }

            PHPhotoLibrary.shared().presentLimitedLibraryPicker(from: self) { [weak self] (_: [String]) in
                DispatchQueue.main.async {
                    self?.finishOnce()
                }
            }
        }
    }

    private func finishOnce() {
        guard !didFinish else { return }
        didFinish = true
        onFinish?()
    }
}
