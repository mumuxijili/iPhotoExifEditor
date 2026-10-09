import CoreLocation
import Foundation
import Photos
import SwiftUI

struct PhotoEditorView: View {
    @EnvironmentObject private var photoLibrary: PhotoLibraryStore
    @Environment(\.dismiss) private var dismiss
    @AppStorage("usesMainlandChinaMapCorrection")
    private var usesMainlandChinaCorrection = false

    let asset: PHAsset

    @State private var selectedTab: EditorTab = .gps
    @State private var draft: PhotoEditDraft
    @State private var dateInput: Date
    @State private var isResettingDateInput = false

    @State private var isShowingGPSEditor = false
    @State private var isShowingDateSourcePicker = false
    @State private var confirmation: ConfirmationKind?
    @State private var feedback: EditorFeedback?

    init(asset: PHAsset) {
        self.asset = asset
        _draft = State(
            initialValue: PhotoEditDraft(
                targetAssetID: asset.localIdentifier,
                originalLocation: asset.location,
                pendingLocation: nil,
                originalCreationDate: asset.creationDate,
                pendingCreationDate: nil
            )
        )
        _dateInput = State(initialValue: asset.creationDate ?? Date())
    }

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(spacing: 18) {
                    PhotoAssetImageView(
                        asset: asset,
                        contentMode: .fit,
                        targetSize: CGSize(width: 1600, height: 1200)
                    )
                    .frame(maxWidth: .infinity)
                    .frame(height: previewHeight(for: proxy.size))
                    .background(.black)
                    .clipShape(RoundedRectangle(cornerRadius: 14))

                    Picker("编辑项目", selection: $selectedTab) {
                        ForEach(EditorTab.allCases) { tab in
                            Text(tab.title).tag(tab)
                        }
                    }
                    .pickerStyle(.segmented)

                    switch selectedTab {
                    case .gps:
                        gpsTab(mapHeight: mapHeight(for: proxy.size))
                    case .date:
                        dateTab
                    }
                }
                .frame(maxWidth: 720)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, horizontalPadding(for: proxy.size))
                .padding(.vertical)
            }
        }
        .navigationTitle("编辑照片")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    closeEditor()
                } label: {
                    Label("返回", systemImage: "chevron.left")
                }
            }
        }
        .disabled(photoLibrary.isWriting)
        .overlay {
            if photoLibrary.isWriting {
                ZStack {
                    Color.black.opacity(0.18)
                        .ignoresSafeArea()
                    ProgressView("正在写入并校验…")
                        .padding()
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
            }
        }
        .sheet(isPresented: $isShowingGPSEditor) {
            GPSEditorView(
                targetAssetID: draft.targetAssetID,
                originalLocation: draft.originalLocation,
                initialLocation: draft.displayedLocation
            ) { location in
                draft.stageLocation(location)
            }
            .environmentObject(photoLibrary)
        }
        .sheet(isPresented: $isShowingDateSourcePicker) {
            PhotoSourcePickerView(
                targetAssetID: draft.targetAssetID,
                kind: .creationDate
            ) { sourceAsset in
                guard let date = sourceAsset.creationDate else { return }
                dateInput = date
                draft.stageCreationDate(date)
            }
            .environmentObject(photoLibrary)
        }
        .confirmationDialog(
            confirmationTitle,
            isPresented: confirmationIsPresented,
            titleVisibility: .visible
        ) {
            confirmationActions
        } message: {
            Text(confirmationMessage)
        }
        .alert(item: $feedback) { feedback in
            Alert(
                title: Text(feedback.title),
                message: Text(feedback.message),
                dismissButton: .default(Text("好"))
            )
        }
    }

    private func gpsTab(mapHeight: CGFloat) -> some View {
        VStack(spacing: 14) {
            LocationMapView(
                originalLocation: draft.originalLocation,
                proposedLocation: draft.hasLocationChange ? draft.pendingLocation : nil,
                usesMainlandChinaCorrection: usesMainlandChinaCorrection
            )
            .frame(height: mapHeight)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay {
                if draft.originalLocation == nil && !draft.hasLocationChange {
                    ContentUnavailableView(
                        "没有 GPS 信息",
                        systemImage: "location.slash",
                        description: Text("点击“编辑”后长按地图，或从其他照片导入。")
                    )
                    .background(.regularMaterial)
                }
            }


            locationSummary

            HStack {
                Button {
                    isShowingGPSEditor = true
                } label: {
                    Label("编辑", systemImage: "map")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

                Button {
                    copyDisplayedLocation()
                } label: {
                    Label("复制 JSON", systemImage: "doc.on.doc")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(draft.displayedLocation == nil)
            }

            Text("修改的是照片图库中的位置；原始图片文件的 EXIF 不会直接改变。")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            if draft.hasLocationChange {
                Divider()

                HStack {
                    Button("取消修改", role: .cancel) {
                        draft.discardLocationChange()
                    }
                    .frame(maxWidth: .infinity)

                    Button("确认修改") {
                        confirmation = .writeLocation
                    }
                    .buttonStyle(.borderedProminent)
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }

    private var locationSummary: some View {
        VStack(alignment: .leading, spacing: 8) {
            metadataRow(
                title: "原位置（WGS‑84）",
                value: Self.coordinateText(draft.originalLocation),
                color: .blue
            )

            if draft.hasLocationChange {
                metadataRow(
                    title: "新位置（WGS‑84）",
                    value: Self.coordinateText(draft.pendingLocation),
                    color: .orange
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var dateTab: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                metadataRow(
                    title: "原日期",
                    value: Self.dateText(draft.originalCreationDate),
                    color: .blue
                )

                if draft.hasDateChange {
                    metadataRow(
                        title: "新日期",
                        value: Self.dateText(draft.pendingCreationDate),
                        color: .orange
                    )
                }

                Text("时区：\(TimeZone.current.identifier)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            DatePicker(
                "设置拍摄日期",
                selection: $dateInput,
                displayedComponents: [.date, .hourAndMinute]
            )
            .datePickerStyle(.graphical)
            .onChange(of: dateInput) { value in
                guard !isResettingDateInput else { return }
                draft.stageCreationDate(value)
            }

            Button {
                isShowingDateSourcePicker = true
            } label: {
                Label("从其他照片导入日期", systemImage: "photo.on.rectangle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)

            if draft.hasDateChange {
                Divider()

                HStack {
                    Button("取消修改", role: .cancel) {
                        resetDateDraft()
                    }
                    .frame(maxWidth: .infinity)

                    Button("确认修改") {
                        confirmation = .writeDate
                    }
                    .buttonStyle(.borderedProminent)
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }

    private func metadataRow(
        title: String,
        value: String,
        color: Color
    ) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline) {
                Circle()
                    .fill(color)
                    .frame(width: 9, height: 9)
                Text(title)
                    .font(.subheadline.bold())
                Spacer()
                Text(value)
                    .font(.system(.subheadline, design: .monospaced))
                    .multilineTextAlignment(.trailing)
                    .textSelection(.enabled)
            }

            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Circle()
                        .fill(color)
                        .frame(width: 9, height: 9)
                    Text(title)
                        .font(.subheadline.bold())
                }
                Text(value)
                    .font(.system(.subheadline, design: .monospaced))
                    .textSelection(.enabled)
            }
        }
    }

    private func previewHeight(for size: CGSize) -> CGFloat {
        min(max(size.height * (size.width > size.height ? 0.42 : 0.28), 200), 340)
    }

    private func mapHeight(for size: CGSize) -> CGFloat {
        min(max(size.height * (size.width > size.height ? 0.48 : 0.36), 240), 390)
    }

    private func horizontalPadding(for size: CGSize) -> CGFloat {
        size.width >= 700 ? 28 : 16
    }

    private var confirmationIsPresented: Binding<Bool> {
        Binding(
            get: { confirmation != nil },
            set: { if !$0 { confirmation = nil } }
        )
    }

    private var confirmationTitle: String {
        switch confirmation {
        case .writeLocation:
            return "确认修改 GPS？"
        case .writeDate:
            return "确认修改拍摄日期？"
        case .discardAll:
            return "放弃未保存的修改？"
        case nil:
            return "确认操作"
        }
    }

    @ViewBuilder
    private var confirmationActions: some View {
        switch confirmation {
        case .writeLocation:
            Button("确认写入") {
                writeLocation()
            }
        case .writeDate:
            Button("确认写入") {
                writeCreationDate()
            }
        case .discardAll:
            Button("放弃修改", role: .destructive) {
                dismiss()
            }
        case nil:
            EmptyView()
        }

        Button("取消", role: .cancel) {}
    }

    private var confirmationMessage: String {
        switch confirmation {
        case .writeLocation:
            return """
            目标：\(draft.targetAssetID)
            原位置：\(Self.coordinateText(draft.originalLocation))
            新位置：\(Self.coordinateText(draft.pendingLocation))
            只修改照片图库的位置，不改写原始图片文件的 EXIF；不会删除、生成或替换图片。
            """
        case .writeDate:
            return """
            目标：\(draft.targetAssetID)
            原日期：\(Self.dateText(draft.originalCreationDate))
            新日期：\(Self.dateText(draft.pendingCreationDate))
            此操作不会删除、生成或替换图片。
            """
        case .discardAll:
            return "当前 GPS 或拍摄日期草稿尚未写入照片库。"
        case nil:
            return ""
        }
    }

    private func closeEditor() {
        if draft.hasChanges {
            confirmation = .discardAll
        } else {
            dismiss()
        }
    }

    private func resetDateDraft() {
        draft.discardDateChange()
        isResettingDateInput = true
        dateInput = draft.originalCreationDate ?? Date()
        DispatchQueue.main.async {
            isResettingDateInput = false
        }
    }

    private func copyDisplayedLocation() {
        guard let location = draft.displayedLocation else { return }

        do {
            try LocationClipboardPayload(location: location).copyToPasteboard()
            feedback = EditorFeedback(
                title: "已复制",
                message: "当前显示的 GPS 已复制为 JSON，照片没有被修改。"
            )
        } catch {
            feedback = EditorFeedback(
                title: "复制失败",
                message: error.localizedDescription
            )
        }
    }

    private func writeLocation() {
        guard let location = draft.pendingLocation else { return }

        photoLibrary.updateLocation(
            assetID: draft.targetAssetID,
            location: location
        ) { result in
            switch result {
            case let .success(refreshedAsset):
                draft.acceptLocation(refreshedAsset.location)
                feedback = EditorFeedback(
                    title: "图库位置修改成功",
                    message: "已重新读取并核对照片图库中的位置。原始图片文件的 EXIF 不会直接改变。"
                )
            case let .failure(error):
                feedback = EditorFeedback(
                    title: "GPS 修改失败",
                    message: error.localizedDescription
                )
            }
        }
    }

    private func writeCreationDate() {
        guard let date = draft.pendingCreationDate else { return }

        photoLibrary.updateCreationDate(
            assetID: draft.targetAssetID,
            date: date
        ) { result in
            switch result {
            case let .success(refreshedAsset):
                draft.acceptCreationDate(refreshedAsset.creationDate)
                dateInput = refreshedAsset.creationDate ?? date
                feedback = EditorFeedback(
                    title: "拍摄日期修改成功",
                    message: "已重新读取并核对目标照片的拍摄日期。"
                )
            case let .failure(error):
                feedback = EditorFeedback(
                    title: "拍摄日期修改失败",
                    message: error.localizedDescription
                )
            }
        }
    }

    private static func coordinateText(_ location: CLLocation?) -> String {
        guard let location else { return "无" }
        return String(
            format: "%.6f, %.6f",
            location.coordinate.latitude,
            location.coordinate.longitude
        )
    }

    private static func dateText(_ date: Date?) -> String {
        guard let date else { return "无" }
        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.timeZone = .autoupdatingCurrent
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium
        return "\(formatter.string(from: date))（\(TimeZone.current.identifier)）"
    }
}

private enum EditorTab: String, CaseIterable, Identifiable {
    case gps
    case date

    var id: Self { self }

    var title: String {
        switch self {
        case .gps:
            return "GPS"
        case .date:
            return "拍摄日期"
        }
    }
}

private enum ConfirmationKind {
    case writeLocation
    case writeDate
    case discardAll
}

private struct EditorFeedback: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}
