import CoreLocation
import SwiftUI

struct GPSEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("usesMainlandChinaMapCorrection")
    private var usesMainlandChinaCorrection = false

    let targetAssetID: String
    let originalLocation: CLLocation?
    let onConfirm: (CLLocation) -> Void

    @State private var candidateLocation: CLLocation?
    @State private var isShowingSourcePicker = false

    init(
        targetAssetID: String,
        originalLocation: CLLocation?,
        initialLocation: CLLocation?,
        onConfirm: @escaping (CLLocation) -> Void
    ) {
        self.targetAssetID = targetAssetID
        self.originalLocation = originalLocation
        self.onConfirm = onConfirm
        _candidateLocation = State(initialValue: initialLocation)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                LocationMapView(
                    originalLocation: originalLocation,
                    proposedLocation: candidateForMap,
                    usesMainlandChinaCorrection: usesMainlandChinaCorrection,
                    allowsPicking: true
                ) { location in
                    candidateLocation = location
                }
                .overlay(alignment: .top) {
                    Label(
                        "长按地图选择新位置",
                        systemImage: "hand.tap"
                    )
                    .font(.callout.bold())
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.regularMaterial, in: Capsule())
                    .padding()
                }

                VStack(spacing: 12) {
                    if let candidateLocation {
                        Text("WGS‑84  \(Self.coordinateText(candidateLocation))")
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)
                    } else {
                        Text("尚未选择新位置")
                            .foregroundStyle(.secondary)
                    }

                    Button {
                        isShowingSourcePicker = true
                    } label: {
                        Label("从其他照片导入", systemImage: "photo.on.rectangle")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)

                    Toggle(
                        "中国大陆地图校正（GCJ‑02）",
                        isOn: $usesMainlandChinaCorrection
                    )
                    .font(.footnote)

                    Text("该选项只校正地图显示和选点；照片草稿始终使用 WGS‑84。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding()
                .background(.bar)
            }
            .navigationTitle("编辑 GPS")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("确认") {
                        guard let candidateLocation else { return }
                        onConfirm(candidateLocation)
                        dismiss()
                    }
                    .disabled(!hasChangedLocation)
                }
            }
        }
        .sheet(isPresented: $isShowingSourcePicker) {
            PhotoSourcePickerView(
                targetAssetID: targetAssetID,
                kind: .location
            ) { asset in
                if let location = asset.location {
                    candidateLocation = location
                }
            }
        }
    }

    private var candidateForMap: CLLocation? {
        guard let candidateLocation else { return nil }
        guard let originalLocation else { return candidateLocation }
        return Self.coordinatesMatch(
            candidateLocation.coordinate,
            originalLocation.coordinate
        ) ? nil : candidateLocation
    }

    private var hasChangedLocation: Bool {
        guard let candidateLocation else { return false }
        guard let originalLocation else { return true }
        return !Self.coordinatesMatch(
            candidateLocation.coordinate,
            originalLocation.coordinate
        )
    }

    private static func coordinatesMatch(
        _ lhs: CLLocationCoordinate2D,
        _ rhs: CLLocationCoordinate2D
    ) -> Bool {
        abs(lhs.latitude - rhs.latitude) < 0.0000001 &&
        abs(lhs.longitude - rhs.longitude) < 0.0000001
    }

    private static func coordinateText(_ location: CLLocation) -> String {
        String(
            format: "%.6f, %.6f",
            location.coordinate.latitude,
            location.coordinate.longitude
        )
    }
}
