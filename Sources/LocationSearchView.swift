import Combine
import CoreLocation
import MapKit
import SwiftUI

struct LocationSearchView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model = LocationSearchModel()
    @State private var query = ""

    let initialRegion: MKCoordinateRegion?
    let onSelect: (CLLocationCoordinate2D) -> Void

    var body: some View {
        NavigationStack {
            Group {
                if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    ContentUnavailableView(
                        "搜索地点",
                        systemImage: "magnifyingglass",
                        description: Text("输入地点名称、兴趣点或地址。")
                    )
                } else if model.isSearching && model.results.isEmpty {
                    ProgressView("正在搜索…")
                } else if let errorMessage = model.errorMessage {
                    ContentUnavailableView(
                        "搜索失败",
                        systemImage: "exclamationmark.triangle",
                        description: Text(errorMessage)
                    )
                } else if model.hasSearched && model.results.isEmpty {
                    ContentUnavailableView.search(text: query)
                } else {
                    List(model.results) { result in
                        Button {
                            onSelect(result.coordinate)
                            dismiss()
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(result.name)
                                    .font(.body)
                                    .foregroundStyle(.primary)

                                if !result.address.isEmpty {
                                    Text(result.address)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                }

                                Text(Self.coordinateText(result.coordinate))
                                    .font(.system(.caption2, design: .monospaced))
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("搜索地点")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(
                text: $query,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: "地点或地址"
            )
            .onChange(of: query) { value in
                model.updateQuery(value, region: initialRegion)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        dismiss()
                    }
                }
            }
        }
    }

    private static func coordinateText(
        _ coordinate: CLLocationCoordinate2D
    ) -> String {
        String(
            format: "%.6f, %.6f",
            coordinate.latitude,
            coordinate.longitude
        )
    }
}

@MainActor
private final class LocationSearchModel: ObservableObject {
    @Published private(set) var results: [LocationSearchResult] = []
    @Published private(set) var isSearching = false
    @Published private(set) var hasSearched = false
    @Published private(set) var errorMessage: String?

    private var searchTask: Task<Void, Never>?

    func updateQuery(_ query: String, region: MKCoordinateRegion?) {
        searchTask?.cancel()
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedQuery.isEmpty else {
            results = []
            isSearching = false
            hasSearched = false
            errorMessage = nil
            return
        }

        results = []
        isSearching = true
        hasSearched = false
        errorMessage = nil

        searchTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: 350_000_000)
                guard !Task.isCancelled else { return }

                let request = MKLocalSearch.Request()
                request.naturalLanguageQuery = trimmedQuery
                if let region {
                    request.region = region
                }

                let response = try await MKLocalSearch(request: request).start()
                guard !Task.isCancelled, let self else { return }

                self.results = response.mapItems.map { LocationSearchResult(mapItem: $0) }
                self.isSearching = false
                self.hasSearched = true
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled, let self else { return }
                self.results = []
                self.isSearching = false
                self.hasSearched = true
                self.errorMessage = error.localizedDescription
            }
        }
    }
}

private struct LocationSearchResult: Identifiable {
    let id = UUID()
    let name: String
    let address: String
    let coordinate: CLLocationCoordinate2D

    init(mapItem: MKMapItem) {
        name = mapItem.name ?? "未命名地点"
        address = mapItem.placemark.title ?? ""
        coordinate = mapItem.placemark.coordinate
    }
}
