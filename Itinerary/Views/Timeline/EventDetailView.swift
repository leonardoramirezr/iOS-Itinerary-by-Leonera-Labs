import SwiftUI

/// Details of an itinerary item.
struct EventDetailView: View {
    let item: ItineraryItem
    let onDelete: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 12) {
                        Image(systemName: item.kind.symbol)
                            .font(.title2)
                            .foregroundStyle(item.kind.color)
                            .frame(width: 36)
                        Text(item.title)
                            .font(.title3.bold())
                    }
                    LabeledContent("Time", value: TimeText.range(item.start, item.end))
                    LabeledContent("Duration", value: TimeText.duration(minutes: item.durationMinutes))
                    LabeledContent("Type", value: item.kind.title)
                }

                if let location = item.location, !location.isEmpty {
                    Section("Location") {
                        Text(location)
                        Button {
                            openInMaps(location)
                        } label: {
                            Label("Open in Maps", systemImage: "map")
                        }
                    }
                }

                if let notes = item.notes, !notes.isEmpty {
                    Section("Notes") {
                        Text(notes)
                    }
                }

                Section {
                    Button(role: .destructive) {
                        onDelete()
                        dismiss()
                    } label: {
                        Label("Remove from itinerary", systemImage: "trash")
                    }
                }
            }
            .navigationTitle(item.kind.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func openInMaps(_ location: String) {
        var components = URLComponents(string: "https://maps.apple.com/")
        components?.queryItems = [URLQueryItem(name: "q", value: location)]
        if let url = components?.url {
            openURL(url)
        }
    }
}
