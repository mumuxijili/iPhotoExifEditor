import Photos
import SwiftUI

enum PhotoSourceValueKind {
    case location
    case creationDate

    var navigationTitle: String {
        switch self {
        case .location:
            return "导入 GPS"
        case .creationDate:
            return "导入拍摄日期"
        }
    }
}

struct PhotoSourcePickerView: View {
    @EnvironmentObject private var photoLibrary: PhotoLibraryStore
    @Environment(\.dismiss) private var dismiss

    let targetAssetID: String
    let kind: PhotoSourceValueKind
    let onSelect: (PHAsset) -> Void

    @State private var errorMessage: String?

    private let columns = [
        GridItem(.adaptive(minimum: 104, maximum: 180), spacing: 2)
    ]

    var body: some View {
        NavigationStack {
            Group {
                if photoLibrary.assets.isEmpty {
                    ContentUnavailableView(
                        "没有可选择的照片",
                        systemImage: "photo"
                    )
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 2) {
                            ForEach(photoLibrary.assets, id: \.localIdentifier) { asset in
                                Button {
                                    select(asset)
                                } label: {
                                    sourceCell(asset)
                                }
                                .buttonStyle(.plain)
                                .disabled(asset.localIdentifier == targetAssetID)
                            }
                        }
                        .padding(.horizontal, 2)
                    }
                }
            }
            .navigationTitle(kind.navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        dismiss()
                    }
                }
            }
        }
        .alert(
            "无法导入",
            isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )
        ) {
            Button("好", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func select(_ asset: PHAsset) {
        guard asset.localIdentifier != targetAssetID else {
            errorMessage = "目标照片不能同时作为来源照片"
            return
        }

        switch kind {
        case .location:
            guard asset.location != nil else {
                errorMessage = "这张照片没有 GPS 信息"
                return
            }
        case .creationDate:
            guard asset.creationDate != nil else {
                errorMessage = "这张照片没有拍摄日期"
                return
            }
        }

        onSelect(asset)
        dismiss()
    }

    private func sourceCell(_ asset: PHAsset) -> some View {
        PhotoGridCell(asset: asset)
            .overlay(alignment: .topLeading) {
                if asset.localIdentifier == targetAssetID {
                    Text("目标照片")
                        .font(.caption2.bold())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 4)
                        .background(.black.opacity(0.65), in: Capsule())
                        .padding(5)
                }
            }
            .overlay(alignment: .bottomLeading) {
                if !hasRequiredValue(asset) {
                    Text(missingValueText)
                        .font(.caption2.bold())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 4)
                        .background(.red.opacity(0.75), in: Capsule())
                        .padding(5)
                }
            }
            .opacity(asset.localIdentifier == targetAssetID ? 0.55 : 1)
    }

    private func hasRequiredValue(_ asset: PHAsset) -> Bool {
        switch kind {
        case .location:
            return asset.location != nil
        case .creationDate:
            return asset.creationDate != nil
        }
    }

    private var missingValueText: String {
        switch kind {
        case .location:
            return "无 GPS"
        case .creationDate:
            return "无日期"
        }
    }
}
