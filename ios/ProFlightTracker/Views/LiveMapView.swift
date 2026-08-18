import SwiftUI
import MapKit

/// Full-screen live tracker: polls /api/flight/track and draws the aircraft
/// with a breadcrumb trail of received positions.
struct LiveMapView: View {
    @Environment(\.dismiss) private var dismiss

    let flight: TrackedFlight
    let initialPosition: AircraftPosition?
    let registration: String?

    @State private var position: AircraftPosition?
    @State private var trail: [CLLocationCoordinate2D] = []
    @State private var camera: MapCameraPosition = .automatic
    @State private var isLoading: Bool = false
    @State private var statusText: String = "Locating aircraft…"

    var body: some View {
        ZStack {
            Map(position: $camera) {
                if !trail.isEmpty {
                    MapPolyline(coordinates: trail)
                        .stroke(Theme.teal, style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: [1, 6]))
                }
                if let position, let lat = position.latitude, let lon = position.longitude {
                    Annotation(flight.ident, coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon)) {
                        PlaneMarker(heading: position.heading ?? 0)
                    }
                }
            }
            .mapStyle(.standard(elevation: .flat))
            .ignoresSafeArea()

            VStack {
                topBar
                Spacer()
                statsPanel
            }
            .padding(16)
        }
        .task {
            if let initialPosition {
                apply(initialPosition)
            }
            await pollLoop()
        }
    }

    private var topBar: some View {
        HStack {
            Button {
                Haptics.tap()
                dismiss()
            } label: {
                LucideIcon(name: "x", size: 17, fallback: "xmark")
                    .foregroundStyle(Theme.ink)
                    .padding(11)
                    .background(.regularMaterial)
                    .clipShape(.circle)
            }
            .accessibilityLabel("Close map")
            Spacer()
            HStack(spacing: 6) {
                LucideIcon(name: "plane", size: 14, fallback: "airplane")
                Text(flight.ident)
                    .font(.subheadline.weight(.bold))
                if let registration {
                    Text(registration)
                        .font(.caption)
                        .foregroundStyle(Theme.inkSecondary)
                }
            }
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(.regularMaterial)
            .clipShape(.capsule)
            Spacer()
            if isLoading {
                ProgressView()
                    .controlSize(.small)
                    .padding(11)
                    .background(.regularMaterial)
                    .clipShape(.circle)
            } else {
                Color.clear.frame(width: 39, height: 39)
            }
        }
    }

    private var statsPanel: some View {
        VStack(spacing: 10) {
            if position == nil {
                Text(statusText)
                    .font(.subheadline)
                    .foregroundStyle(Theme.inkSecondary)
            } else {
                // Three numeric metrics share the row at full size; the data
                // source is descriptive text, not a metric, so it moves to its
                // own caption line instead of forcing the numbers to shrink.
                HStack(spacing: 0) {
                    stat(icon: "mountain", label: "Altitude",
                         value: position?.altitudeFt.map { "\(Int($0)) ft" } ?? "—")
                    stat(icon: "gauge", label: "Speed",
                         value: position?.groundspeedKts.map { "\(Int($0)) kt" } ?? "—")
                    stat(icon: "compass", label: "Heading",
                         value: position?.heading.map { "\(Int($0))°" } ?? "—")
                }
                if let source = position?.source, !source.isEmpty {
                    HStack(spacing: 5) {
                        LucideIcon(name: "radio", size: 11, fallback: "antenna.radiowaves.left.and.right")
                            .foregroundStyle(Theme.teal)
                        Text("Source · \(source.replacingOccurrences(of: "_", with: " "))")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(Theme.inkSecondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .background(.regularMaterial)
        .clipShape(.rect(cornerRadius: Theme.Radius.card))
    }

    private func stat(icon: String, label: String, value: String) -> some View {
        VStack(spacing: 4) {
            LucideIcon(name: icon, size: 15, fallback: "circle")
                .foregroundStyle(Theme.teal)
            // Full-size always — numeric values are short ("38000 ft"), and
            // with three columns each gets enough width; wrap rather than shrink.
            Text(value)
                .font(.subheadline.weight(.bold))
                .monospacedDigit()
                .foregroundStyle(Theme.ink)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Text(label)
                .font(.caption2)
                .foregroundStyle(Theme.inkSecondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Polling

    private func pollLoop() async {
        while !Task.isCancelled {
            await fetchPosition()
            try? await Task.sleep(for: .seconds(30))
        }
    }

    private func fetchPosition() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let envelope = try await API.flightTrack(
                flight: registration == nil ? flight.ident : nil,
                reg: registration)
            if let fresh = envelope.data, fresh.latitude != nil {
                apply(fresh)
            } else if position == nil {
                statusText = "No live position — the aircraft may be on the ground or out of coverage."
            }
        } catch {
            if position == nil {
                statusText = "Couldn't reach the tracking feed."
            }
        }
    }

    private func apply(_ fresh: AircraftPosition) {
        position = fresh
        guard let lat = fresh.latitude, let lon = fresh.longitude else { return }
        let coordinate = CLLocationCoordinate2D(latitude: lat, longitude: lon)
        if trail.last.map({ abs($0.latitude - lat) > 0.0005 || abs($0.longitude - lon) > 0.0005 }) ?? true {
            trail.append(coordinate)
        }
        if trail.count == 1 {
            camera = .region(MKCoordinateRegion(
                center: coordinate,
                span: MKCoordinateSpan(latitudeDelta: 3, longitudeDelta: 3)))
        }
    }
}
