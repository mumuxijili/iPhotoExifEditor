import Photos
import SwiftUI
import UIKit

struct ContentView: View {
    @EnvironmentObject private var photoLibrary: PhotoLibraryStore
    @Environment(\.scenePhase) private var scenePhase
    @State private var isShowingSettings = false

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("照片")
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            isShowingSettings = true
                        } label: {
                            Label("设置", systemImage: "gearshape")
                        }
                    }
                }
        }
        .sheet(isPresented: $isShowingSettings) {
            SettingsView()
        }
        .onChange(of: scenePhase) { phase in
            if phase == .active {
                photoLibrary.refreshAuthorization()
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch photoLibrary.authorizationStatus {
        case .authorized, .limited:
            PhotoLibraryGridView()
        case .notDetermined:
            ContentUnavailableView {
                Label("访问照片", systemImage: "photo.on.rectangle.angled")
            } description: {
                Text("选择一张照片后，可以修改它的位置和拍摄日期。")
            } actions: {
                Button("选择照片访问权限") {
                    photoLibrary.requestAccess()
                }
                .buttonStyle(.borderedProminent)
            }
        case .denied, .restricted:
            ContentUnavailableView {
                Label("无法访问照片", systemImage: "lock.fill")
            } description: {
                Text("请在系统设置中允许 iPhotoExifEditor 读取和修改照片。")
            } actions: {
                Button("打开设置") {
                    guard let url = URL(string: UIApplication.openSettingsURLString) else {
                        return
                    }
                    UIApplication.shared.open(url)
                }
                .buttonStyle(.borderedProminent)
            }
        @unknown default:
            ContentUnavailableView(
                "无法读取权限状态",
                systemImage: "exclamationmark.triangle"
            )
        }
    }
}

private struct PhotoLibraryGridView: View {
    @EnvironmentObject private var photoLibrary: PhotoLibraryStore

    private let columns = [
        GridItem(.adaptive(minimum: 104, maximum: 180), spacing: 2)
    ]

    var body: some View {
        Group {
            if photoLibrary.isLoading && photoLibrary.assets.isEmpty {
                ProgressView("正在读取照片…")
            } else if photoLibrary.assets.isEmpty {
                ContentUnavailableView(
                    "没有可访问的照片",
                    systemImage: "photo",
                    description: Text("请刷新照片库，或调整有限照片访问范围。")
                )
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 2) {
                        ForEach(photoLibrary.assets, id: \.localIdentifier) { asset in
                            NavigationLink {
                                PhotoEditorView(asset: asset)
                            } label: {
                                PhotoGridCell(asset: asset)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 2)
                }
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                if photoLibrary.authorizationStatus == .limited {
                    Button {
                        openPhotoAccessSettings()
                    } label: {
                        Label("添加可访问照片", systemImage: "photo.badge.plus")
                    }
                    .accessibilityHint("在系统设置中编辑已授权照片，返回后自动刷新")
                }

                Button {
                    photoLibrary.loadAssets()
                } label: {
                    Label("刷新", systemImage: "arrow.clockwise")
                }
            }
        }
        .refreshable {
            photoLibrary.loadAssets()
        }
    }

    private func openPhotoAccessSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else {
            return
        }
        UIApplication.shared.open(url)
    }
}

struct PhotoGridCell: View {
    let asset: PHAsset

    var body: some View {
        PhotoAssetImageView(
            asset: asset,
            contentMode: .fill,
            targetSize: CGSize(width: 320, height: 320)
        )
        .aspectRatio(1, contentMode: .fit)
        .overlay(alignment: .bottomTrailing) {
            if asset.location != nil {
                Image(systemName: "location.fill")
                    .font(.caption)
                    .foregroundStyle(.white)
                    .padding(6)
                    .background(.black.opacity(0.55), in: Circle())
                    .padding(5)
            }
        }
        .accessibilityLabel(accessibilityDescription)
    }

    private var accessibilityDescription: String {
        let date = asset.creationDate.map {
            DateFormatter.localizedString(
                from: $0,
                dateStyle: .medium,
                timeStyle: .short
            )
        } ?? "未知日期"
        return asset.location == nil ? "\(date)，无位置信息" : "\(date)，有位置信息"
    }
}
