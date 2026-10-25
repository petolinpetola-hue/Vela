#!/bin/bash
set -e

mkdir -p Sources .github/workflows

cat > project.yml <<‘EOF’
name: VelaIOS
options:
bundleIdPrefix: app.velamaps
deploymentTarget:
iOS: “17.0”
targets:
VelaIOS:
type: application
platform: iOS
sources:
- path: Sources
settings:
base:
PRODUCT_BUNDLE_IDENTIFIER: app.velamaps.ios
PRODUCT_NAME: Vela
SWIFT_VERSION: “5.0”
TARGETED_DEVICE_FAMILY: “1,2”
GENERATE_INFOPLIST_FILE: YES
INFOPLIST_KEY_CFBundleDisplayName: Vela
INFOPLIST_KEY_NSLocationWhenInUseUsageDescription: “Vela usa la posizione per mostrare dove ti trovi e calcolare percorsi.”
CODE_SIGNING_ALLOWED: NO
EOF

cat > Sources/VelaIOSApp.swift <<‘EOF’
import SwiftUI

@main
struct VelaIOSApp: App {
var body: some Scene {
WindowGroup {
ContentView()
}
}
}
EOF

cat > Sources/ContentView.swift <<‘EOF’
import SwiftUI
import MapKit
import CoreLocation

struct ContentView: View {
@State private var camera: MapCameraPosition = .automatic
@State private var query = “”
@State private var results: [MKMapItem] = []
@State private var destination: MKMapItem?
@State private var route: MKRoute?
@State private var manager = CLLocationManager()
@State private var coordinate: CLLocationCoordinate2D?
@State private var message = “”

var body: some View {
    ZStack(alignment: .top) {
        Map(position: $camera) {
            UserAnnotation()
            if let destination {
                Marker(destination.name ?? "Destinazione",
                       coordinate: destination.placemark.coordinate)
            }
            if let route {
                MapPolyline(route.polyline).stroke(.blue, lineWidth: 6)
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
                    .onSubmit { Task { await search() } }
                Button("Cerca") { Task { await search() } }
            }
            .padding()
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
            if !results.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(results.enumerated()), id: \.offset) { _, item in
                            Button {
                                destination = item
                                route = nil
                                results = []
                                camera = .region(MKCoordinateRegion(
                                    center: item.placemark.coordinate,
                                    span: MKCoordinateSpan(latitudeDelta: 0.025,
                                                           longitudeDelta: 0.025)))
                            } label: {
                                VStack(alignment: .leading) {
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
                .frame(maxHeight: 260)
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
            Button("Posizione") { locate() }
            Spacer()
            Button("Percorso") { Task { await directions() } }
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
        manager.delegate = LocationHandler.shared
        LocationHandler.shared.onLocation = { value in
            coordinate = value
        }
        manager.requestWhenInUseAuthorization()
        manager.requestLocation()
    }
}
@MainActor
private func search() async {
    guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
    let request = MKLocalSearch.Request()
    request.naturalLanguageQuery = query
    if let coordinate {
        request.region = MKCoordinateRegion(
            center: coordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.4, longitudeDelta: 0.4))
    }
    do {
        results = try await MKLocalSearch(request: request).start().mapItems
        message = results.isEmpty ? "Nessun risultato trovato." : ""
    } catch {
        message = "Ricerca non riuscita: \(error.localizedDescription)"
    }
}
private func locate() {
    manager.requestWhenInUseAuthorization()
    manager.requestLocation()
    if let coordinate {
        camera = .region(MKCoordinateRegion(
            center: coordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.03, longitudeDelta: 0.03)))
    } else {
        message = "Attendi la posizione e riprova."
    }
}
@MainActor
private func directions() async {
    guard let destination else { return }
    guard let coordinate else {
        locate()
        message = "Attendi la posizione e riprova."
        return
    }
    let request = MKDirections.Request()
    request.source = MKMapItem(placemark: MKPlacemark(coordinate: coordinate))
    request.destination = destination
    request.transportType = .automobile
    do {
        guard let found = try await MKDirections(request: request).calculate().routes.first else {
            message = "Percorso non disponibile."
            return
        }
        route = found
        camera = .rect(found.polyline.boundingMapRect)
        message = ""
    } catch {
        message = "Errore percorso: \(error.localizedDescription)"
    }
}

}

final class LocationHandler: NSObject, CLLocationManagerDelegate {
static let shared = LocationHandler()
var onLocation: ((CLLocationCoordinate2D) -> Void)?

func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
    if let coordinate = locations.last?.coordinate {
        onLocation?(coordinate)
    }
}

}
EOF

cat > .github/workflows/ios.yml <<‘EOF’
name: Build iOS IPA

on:
push:
branches: [ main ]
workflow_dispatch:

permissions:
contents: read

jobs:
build:
runs-on: macos-15
steps:
- uses: actions/checkout@v4
- name: Install XcodeGen
run: brew install xcodegen
- name: Generate Xcode project
run: xcodegen generate
- name: Build app
run: |
xcodebuild 
-project VelaIOS.xcodeproj 
-scheme VelaIOS 
-configuration Release 
-sdk iphoneos 
-derivedDataPath build/DerivedData 
CODE_SIGNING_ALLOWED=NO 
build
- name: Package unsigned IPA
run: |
mkdir -p build/Payload
cp -R build/DerivedData/Build/Products/Release-iphoneos/Vela.app build/Payload/
cd build
zip -r VelaIOS-unsigned.ipa Payload
- uses: actions/upload-artifact@v4
with:
name: VelaIOS-unsigned-ipa
path: build/VelaIOS-unsigned.ipa
if-no-files-found: error
EOF

cat > README.md <<‘EOF’

Vela iOS

Porting iniziale di Vela Maps con SwiftUI e Apple MapKit.

Funzioni iniziali: mappa, ricerca luoghi, posizione, percorsi in auto e apertura della destinazione in Apple Maps.

GitHub Actions compila su macOS e produce un IPA non firmato, da firmare prima dell’installazione.

Questa è una base iniziale, non ancora un porting completo. Navigazione vocale, mappe e routing offline, trasporto pubblico, prezzi carburante e avvisi autovelox richiedono ulteriore implementazione. Prima della distribuzione, rispettare la licenza GPL-3.0 del progetto Android originale.
EOF

echo “File Vela iOS creati.”