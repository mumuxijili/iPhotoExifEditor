import CoreLocation
import Foundation

struct PhotoEditDraft {
    let targetAssetID: String

    var originalLocation: CLLocation?
    var pendingLocation: CLLocation?

    var originalCreationDate: Date?
    var pendingCreationDate: Date?

    var displayedLocation: CLLocation? {
        pendingLocation ?? originalLocation
    }

    var displayedCreationDate: Date? {
        pendingCreationDate ?? originalCreationDate
    }

    var hasLocationChange: Bool {
        guard let pendingLocation else { return false }
        guard let originalLocation else { return true }
        return !Self.coordinatesMatch(pendingLocation.coordinate, originalLocation.coordinate)
    }

    var hasDateChange: Bool {
        guard let pendingCreationDate else { return false }
        guard let originalCreationDate else { return true }
        return abs(pendingCreationDate.timeIntervalSince(originalCreationDate)) >= 0.5
    }

    var hasChanges: Bool {
        hasLocationChange || hasDateChange
    }

    mutating func stageLocation(_ location: CLLocation) {
        if let originalLocation,
           Self.coordinatesMatch(location.coordinate, originalLocation.coordinate) {
            pendingLocation = nil
        } else {
            pendingLocation = location
        }
    }

    mutating func stageCreationDate(_ date: Date) {
        if let originalCreationDate,
           abs(date.timeIntervalSince(originalCreationDate)) < 0.5 {
            pendingCreationDate = nil
        } else {
            pendingCreationDate = date
        }
    }

    mutating func discardLocationChange() {
        pendingLocation = nil
    }

    mutating func discardDateChange() {
        pendingCreationDate = nil
    }

    mutating func acceptLocation(_ location: CLLocation?) {
        originalLocation = location
        pendingLocation = nil
    }

    mutating func acceptCreationDate(_ date: Date?) {
        originalCreationDate = date
        pendingCreationDate = nil
    }

    private static func coordinatesMatch(
        _ lhs: CLLocationCoordinate2D,
        _ rhs: CLLocationCoordinate2D
    ) -> Bool {
        abs(lhs.latitude - rhs.latitude) < 0.0000001 &&
        abs(lhs.longitude - rhs.longitude) < 0.0000001
    }
}
