import CoreLocation
import Foundation

enum CoordinateConverter {
    private static let semiMajorAxis = 6_378_245.0
    private static let eccentricitySquared = 0.00669342162296594323
    private static let pi = Double.pi

    static func mapCoordinate(
        fromWGS84 coordinate: CLLocationCoordinate2D,
        usesGCJ02: Bool
    ) -> CLLocationCoordinate2D {
        guard usesGCJ02, isInsideMainlandChina(coordinate) else {
            return coordinate
        }
        return wgs84ToGCJ02(coordinate)
    }

    static func wgs84Coordinate(
        fromMapCoordinate coordinate: CLLocationCoordinate2D,
        usesGCJ02: Bool
    ) -> CLLocationCoordinate2D {
        guard usesGCJ02, isInsideMainlandChina(coordinate) else {
            return coordinate
        }
        return gcj02ToWGS84(coordinate)
    }

    private static func wgs84ToGCJ02(
        _ coordinate: CLLocationCoordinate2D
    ) -> CLLocationCoordinate2D {
        var latitudeOffset = transformLatitude(
            x: coordinate.longitude - 105,
            y: coordinate.latitude - 35
        )
        var longitudeOffset = transformLongitude(
            x: coordinate.longitude - 105,
            y: coordinate.latitude - 35
        )

        let latitudeRadians = coordinate.latitude / 180 * pi
        var magic = sin(latitudeRadians)
        magic = 1 - eccentricitySquared * magic * magic
        let squareRootMagic = sqrt(magic)

        latitudeOffset = latitudeOffset * 180 /
            ((semiMajorAxis * (1 - eccentricitySquared)) /
                (magic * squareRootMagic) * pi)
        longitudeOffset = longitudeOffset * 180 /
            (semiMajorAxis / squareRootMagic * cos(latitudeRadians) * pi)

        return CLLocationCoordinate2D(
            latitude: coordinate.latitude + latitudeOffset,
            longitude: coordinate.longitude + longitudeOffset
        )
    }

    private static func gcj02ToWGS84(
        _ coordinate: CLLocationCoordinate2D
    ) -> CLLocationCoordinate2D {
        var estimate = coordinate

        for _ in 0..<10 {
            let converted = wgs84ToGCJ02(estimate)
            let latitudeError = converted.latitude - coordinate.latitude
            let longitudeError = converted.longitude - coordinate.longitude
            estimate.latitude -= latitudeError
            estimate.longitude -= longitudeError

            if max(abs(latitudeError), abs(longitudeError)) < 0.0000001 {
                break
            }
        }

        return estimate
    }

    private static func isInsideMainlandChina(
        _ coordinate: CLLocationCoordinate2D
    ) -> Bool {
        coordinate.longitude >= 72.004 &&
        coordinate.longitude <= 137.8347 &&
        coordinate.latitude >= 0.8293 &&
        coordinate.latitude <= 55.8271
    }

    private static func transformLatitude(x: Double, y: Double) -> Double {
        var result = -100 + 2 * x + 3 * y + 0.2 * y * y +
            0.1 * x * y + 0.2 * sqrt(abs(x))
        result += (20 * sin(6 * x * pi) + 20 * sin(2 * x * pi)) * 2 / 3
        result += (20 * sin(y * pi) + 40 * sin(y / 3 * pi)) * 2 / 3
        result += (160 * sin(y / 12 * pi) + 320 * sin(y * pi / 30)) * 2 / 3
        return result
    }

    private static func transformLongitude(x: Double, y: Double) -> Double {
        var result = 300 + x + 2 * y + 0.1 * x * x +
            0.1 * x * y + 0.1 * sqrt(abs(x))
        result += (20 * sin(6 * x * pi) + 20 * sin(2 * x * pi)) * 2 / 3
        result += (20 * sin(x * pi) + 40 * sin(x / 3 * pi)) * 2 / 3
        result += (150 * sin(x / 12 * pi) + 300 * sin(x / 30 * pi)) * 2 / 3
        return result
    }
}
