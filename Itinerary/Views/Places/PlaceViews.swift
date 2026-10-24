import MapKit
import SwiftUI

/// Row that shows a configured place or "Not set".
struct PlaceRow: View {
    let title: String
    let symbol: String
    let place: Place?

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .foregroundStyle(.tint)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(place?.summary ?? String(localized: "Not set"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
    }
}

/// Searches an address or point of interest, or uses the current location.
struct PlacePickerView: View {
    let title: String
    @Binding var place: Place?

    @Environment(\.dismiss) private var dismiss
    @State private var search = LocationSearchModel()
    @State private var locator = CurrentLocationProvider()
    @State private var query = ""
    @State private var isResolving = false
    @State private var errorMessage: String?
    @State private var cameraPosition: MapCameraPosition = .automatic

    var body: some View {
        List {
            if let place {
                Section("Selected") {
                    Map(position: $cameraPosition) {
                        Marker(place.name, coordinate: place.coordinate)
                    }
                    .frame(height: 180)
                    .listRowInsets(EdgeInsets())
                    .allowsHitTesting(false)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(place.name).font(.headline)
                        if !place.address.isEmpty {
                            Text(place.address)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Section {
                Button {
                    Task { await useCurrentLocation() }
                } label: {
                    Label("Use my current location", systemImage: "location.fill")
                }
                .disabled(isResolving)
            }

            if !search.results.isEmpty {
                Section("Results") {
                    ForEach(search.results, id: \.self) { completion in
                        Button {
                            Task { await select(completion) }
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(completion.title)
                                    .foregroundStyle(.primary)
                                if !completion.subtitle.isEmpty {
                                    Text(completion.subtitle)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .disabled(isResolving)
                    }
                }
            }

            if let message = errorMessage ?? search.errorMessage {
                Section {
                    Text(message).foregroundStyle(.red)
                }
            }
        }
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: Text("Search for an address or place"))
        .onChange(of: query) { _, newValue in
            search.update(query: newValue)
        }
        .overlay {
            if isResolving {
                ProgressView()
                    .controlSize(.large)
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: centerMap)
    }

    private func centerMap() {
        guard let place else { return }
        cameraPosition = .region(MKCoordinateRegion(center: place.coordinate, latitudinalMeters: 800, longitudinalMeters: 800))
    }

    private func select(_ completion: MKLocalSearchCompletion) async {
        isResolving = true
        defer { isResolving = false }
        do {
            place = try await search.resolve(completion)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func useCurrentLocation() async {
        isResolving = true
        defer { isResolving = false }
        do {
            place = try await locator.currentPlace()
            errorMessage = nil
            centerMap()
        } catch is CancellationError {
            return
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
