import SwiftUI
import MapKit
import CoreLocation

struct ContentView: View {
@State private var camera: MapCameraPosition = .automatic
@State private var query = “”
@State private var results: [MKMapItem] = []
@State private var destination: MKMapItem?
@State private var route: MKRoute?
@State private var userCoordinate: CLLocationCoordinate2D?
@State private var message = “”

private let locationManager = LocationManager.shared
var body: some View {
    ZStack(alignment: .top) {
        Map(position: $camera) {
            UserAnnotation()
            if let destination {
                Marker(
                    destination.name ?? "Destinazione",
                    coordinate: destination.placemark.coordinate
                )
            }
            if let route {
                MapPolyline(route.polyline)
                    .stroke(.blue, lineWidth: 6)
            }
        }
        .mapControls {
            MapCompass()
            MapScaleView()
            MapUserLocationButton()
        }
        .ignoresSafeArea(edges: .bottom)
        VStack(spacing: 8) {
            HStack {
                TextField("Cerca luogo o indirizzo", text: $query)
                    .submitLabel(.search)
                    .onSubmit {
                        Task { await searchPlaces() }
                    }
                Button("Cerca") {
                    Task { await searchPlaces() }
                }
            }
            .padding()
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
            if !results.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(results.enumerated()), id: \.offset) { _, item in
                            Button {
                                selectPlace(item)
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(item.name ?? "Luogo")
                                        .fontWeight(.medium)
                                    Text(item.placemark.title ?? "")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(12)
                            }
                            .buttonStyle(.plain)
                            Divider()
                        }
                    }
                }
                .frame(maxHeight: 250)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            }
            if let route {
                Text("\(Int(route.expectedTravelTime / 60)) min · \(String(format: "%.1f", route.distance / 1000)) km")
                    .padding(10)
                    .background(.regularMaterial, in: Capsule())
            }
            if !message.isEmpty {
                Text(message)
                    .font(.footnote)
                    .padding(8)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
            }
        }
        .padding()
    }
    .safeAreaInset(edge: .bottom) {
        HStack {
            Button("Posizione") {
                locateUser()
            }
            Spacer()
            Button("Percorso") {
                Task { await calculateRoute() }
            }
            .disabled(destination == nil)
            Spacer()
            Button("Apri in Mappe") {
                destination?.openInMaps()
            }
            .disabled(destination == nil)
        }
        .padding()
        .background(.regularMaterial)
    }
    .onAppear {
        locationManager.onLocationUpdate = { coordinate in
            userCoordinate = coordinate
        }
        locationManager.onError = { error in
            message = error
        }
        locationManager.requestPermission()
        locationManager.requestLocation()
    }
}
@MainActor
private func searchPlaces() async {
    let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty else { return }
    let request = MKLocalSearch.Request()
    request.naturalLanguageQuery = text
    if let userCoordinate {
        request.region = MKCoordinateRegion(
            center: userCoordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.4, longitudeDelta: 0.4)
        )
    }
    do {
        let response = try await MKLocalSearch(request: request).start()
        results = response.mapItems
        message = results.isEmpty ? "Nessun risultato trovato." : ""
    } catch {
        message = "Ricerca non riuscita: \(error.localizedDescription)"
    }
}
private func selectPlace(_ item: MKMapItem) {
    destination = item
    route = nil
    results = []
    camera = .region(
        MKCoordinateRegion(
            center: item.placemark.coordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.025, longitudeDelta: 0.025)
        )
    )
}
private func locateUser() {
    locationManager.requestPermission()
    locationManager.requestLocation()
    if let userCoordinate {
        camera = .region(
            MKCoordinateRegion(
                center: userCoordinate,
                span: MKCoordinateSpan(latitudeDelta: 0.03, longitudeDelta: 0.03)
            )
        )
    } else {
        message = "Attendi la rilevazione della posizione e riprova."
    }
}
@MainActor
private func calculateRoute() async {
    guard let destination else { return }
    guard let userCoordinate else {
        locateUser()
        message = "Attendi la posizione e riprova."
        return
    }
    let request = MKDirections.Request()
    request.source = MKMapItem(
        placemark: MKPlacemark(coordinate: userCoordinate)
    )
    request.destination = destination
    request.transportType = .automobile
    do {
        let response = try await MKDirections(request: request).calculate()
        guard let firstRoute = response.routes.first else {
            message = "Percorso non disponibile."
            return
        }
        route = firstRoute
        camera = .rect(firstRoute.polyline.boundingMapRect)
        message = ""
    } catch {
        message = "Errore percorso: \(error.localizedDescription)"
    }
}

}