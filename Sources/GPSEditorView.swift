import CoreLocation
import MapKit
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
    @State private var isShowingLocationSearch = false

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
                    VStack(spacing: 3) {
                        Label(
                            "长按地图选择新位置",
                            systemImage: "hand.tap"
                        )
                        Text("长按橙色“新”标记后可拖动微调")
                            .font(.caption)
                    }
                    .font(.callout.bold())
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        .regularMaterial,
                        in: RoundedRectangle(cornerRadius: 12)
                    )
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

                    HStack(spacing: 12) {
                        Button {
                            isShowingSourcePicker = true
                        } label: {
                            Label(
                                "从照片导入",
                                systemImage: "photo.on.rectangle"
                            )
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)

                        Button {
                            isShowingLocationSearch = true
                        } label: {
                            Label("搜索地点", systemImage: "magnifyingglass")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    }
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
        .sheet(isPresented: $isShowingLocationSearch) {
            LocationSearchView(initialRegion: searchRegion) { mapCoordinate in
                setCandidateFromMapCoordinate(mapCoordinate)
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

    private var searchRegion: MKCoordinateRegion? {
        guard let location = candidateLocation ?? originalLocation else {
            return nil
        }
        let mapCoordinate = CoordinateConverter.mapCoordinate(
            fromWGS84: location.coordinate,
            usesGCJ02: usesMainlandChinaCorrection
        )
        return MKCoordinateRegion(
            center: mapCoordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.5, longitudeDelta: 0.5)
        )
    }

    private func setCandidateFromMapCoordinate(
        _ mapCoordinate: CLLocationCoordinate2D
    ) {
        let wgs84Coordinate = CoordinateConverter.wgs84Coordinate(
            fromMapCoordinate: mapCoordinate,
            usesGCJ02: usesMainlandChinaCorrection
        )
        candidateLocation = CLLocation(
            latitude: wgs84Coordinate.latitude,
            longitude: wgs84Coordinate.longitude
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
