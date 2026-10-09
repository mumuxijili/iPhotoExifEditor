import CoreLocation
import Foundation
import UIKit

struct LocationClipboardPayload: Encodable {
    let format = "iPhotoExifEditor.location"
    let version = 1
    let latitude: Double
    let longitude: Double
    let altitude: Double?
    let horizontalAccuracy: Double?
    let verticalAccuracy: Double?
    let timestamp: String

    init(location: CLLocation) {
        latitude = location.coordinate.latitude
        longitude = location.coordinate.longitude
        altitude = location.verticalAccuracy >= 0 ? location.altitude : nil
        horizontalAccuracy = location.horizontalAccuracy >= 0 ? location.horizontalAccuracy : nil
        verticalAccuracy = location.verticalAccuracy >= 0 ? location.verticalAccuracy : nil
        timestamp = ISO8601DateFormatter().string(from: location.timestamp)
    }

    func jsonString() throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(self)
        guard let text = String(data: data, encoding: .utf8) else {
            throw LocationClipboardError.encodingFailed
        }
        return text
    }

    func copyToPasteboard() throws {
        UIPasteboard.general.string = try jsonString()
    }
}

enum LocationClipboardError: LocalizedError {
    case encodingFailed

    var errorDescription: String? {
        "无法生成 GPS JSON"
    }
}
