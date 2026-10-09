import CoreLocation
import MapKit
import SwiftUI

struct LocationMapView: UIViewRepresentable {
    let originalLocation: CLLocation?
    let proposedLocation: CLLocation?
    var allowsPicking = false
    var onLongPress: ((CLLocation) -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.delegate = context.coordinator
        mapView.pointOfInterestFilter = .includingAll
        mapView.showsCompass = true
        mapView.showsScale = true

        let recognizer = UILongPressGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleLongPress(_:))
        )
        recognizer.minimumPressDuration = 0.6
        mapView.addGestureRecognizer(recognizer)
        return mapView
    }

    func updateUIView(_ mapView: MKMapView, context: Context) {
        context.coordinator.parent = self

        let existing = mapView.annotations.compactMap { $0 as? LocationAnnotation }
        mapView.removeAnnotations(existing)

        var annotations: [LocationAnnotation] = []
        if let originalLocation {
            annotations.append(
                LocationAnnotation(
                    coordinate: originalLocation.coordinate,
                    kind: .original
                )
            )
        }

        if let proposedLocation,
           !Self.coordinatesMatch(
                proposedLocation.coordinate,
                originalLocation?.coordinate
           ) {
            annotations.append(
                LocationAnnotation(
                    coordinate: proposedLocation.coordinate,
                    kind: .proposed
                )
            )
        }

        mapView.addAnnotations(annotations)

        let signature = annotations
            .map {
                "\($0.kind.rawValue):\($0.coordinate.latitude):\($0.coordinate.longitude)"
            }
            .joined(separator: "|")

        guard signature != context.coordinator.lastRegionSignature else { return }
        context.coordinator.lastRegionSignature = signature

        if annotations.count == 1, let coordinate = annotations.first?.coordinate {
            mapView.setRegion(
                MKCoordinateRegion(
                    center: coordinate,
                    span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)
                ),
                animated: context.coordinator.hasSetRegion
            )
        } else if annotations.count > 1 {
            mapView.showAnnotations(annotations, animated: context.coordinator.hasSetRegion)
        } else if !context.coordinator.hasSetRegion {
            mapView.setRegion(
                MKCoordinateRegion(
                    center: CLLocationCoordinate2D(latitude: 0, longitude: 0),
                    span: MKCoordinateSpan(latitudeDelta: 120, longitudeDelta: 300)
                ),
                animated: false
            )
        }

        context.coordinator.hasSetRegion = true
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        var parent: LocationMapView
        var lastRegionSignature = ""
        var hasSetRegion = false

        init(parent: LocationMapView) {
            self.parent = parent
        }

        @objc
        func handleLongPress(_ recognizer: UILongPressGestureRecognizer) {
            guard recognizer.state == .began,
                  parent.allowsPicking,
                  let mapView = recognizer.view as? MKMapView else {
                return
            }

            let point = recognizer.location(in: mapView)
            let coordinate = mapView.convert(point, toCoordinateFrom: mapView)
            guard CLLocationCoordinate2DIsValid(coordinate) else { return }
            parent.onLongPress?(CLLocation(
                latitude: coordinate.latitude,
                longitude: coordinate.longitude
            ))
        }

        func mapView(
            _ mapView: MKMapView,
            viewFor annotation: MKAnnotation
        ) -> MKAnnotationView? {
            guard let locationAnnotation = annotation as? LocationAnnotation else {
                return nil
            }

            let identifier = "LocationMarker"
            let marker = mapView.dequeueReusableAnnotationView(
                withIdentifier: identifier
            ) as? MKMarkerAnnotationView ?? MKMarkerAnnotationView(
                annotation: annotation,
                reuseIdentifier: identifier
            )
            marker.annotation = annotation
            marker.canShowCallout = true

            switch locationAnnotation.kind {
            case .original:
                marker.markerTintColor = .systemBlue
                marker.glyphText = "旧"
            case .proposed:
                marker.markerTintColor = .systemOrange
                marker.glyphText = "新"
            }
            return marker
        }
    }

    private static func coordinatesMatch(
        _ lhs: CLLocationCoordinate2D,
        _ rhs: CLLocationCoordinate2D?
    ) -> Bool {
        guard let rhs else { return false }
        return abs(lhs.latitude - rhs.latitude) < 0.0000001 &&
        abs(lhs.longitude - rhs.longitude) < 0.0000001
    }
}

private final class LocationAnnotation: NSObject, MKAnnotation {
    enum Kind: String {
        case original
        case proposed
    }

    let coordinate: CLLocationCoordinate2D
    let kind: Kind

    var title: String? {
        switch kind {
        case .original:
            return "原位置"
        case .proposed:
            return "新位置"
        }
    }

    init(coordinate: CLLocationCoordinate2D, kind: Kind) {
        self.coordinate = coordinate
        self.kind = kind
    }
}
