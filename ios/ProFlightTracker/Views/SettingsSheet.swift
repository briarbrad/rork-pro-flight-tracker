import SwiftUI

/// App-wide settings. The master Pro / Simple toggle lives here — obvious,
/// persisted, and presentation-only (same snapshots after a switch).
struct SettingsSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.md) {
                    modeCard
                    aboutCard
                }
                .padding(Space.md)
            }
            .background(Theme.canvas)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        Haptics.tap()
                        dismiss()
                    }
                    .font(TypeScale.bodyMedium)
                    .foregroundStyle(Theme.teal)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private var modeCard: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            SectionHeader(icon: "sliders-horizontal", title: "Flight view")

            Text("Choose how every trip looks. Switching does not refresh or re-run a brief — it's the same data, shown differently.")
                .font(TypeScale.caption)
                .foregroundStyle(Theme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)

            Picker("Display mode", selection: modeBinding) {
                ForEach(AppDisplayMode.allCases, id: \.self) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityLabel("Flight view")

            VStack(alignment: .leading, spacing: Space.xs) {
                ForEach(AppDisplayMode.allCases, id: \.self) { mode in
                    modeRow(mode)
                }
            }
        }
        .cardStyle()
    }

    private func modeRow(_ mode: AppDisplayMode) -> some View {
        let selected = store.displayMode == mode
        return Button {
            guard store.displayMode != mode else { return }
            Haptics.tap()
            store.displayMode = mode
        } label: {
            HStack(alignment: .top, spacing: Space.sm) {
                LucideIcon(name: mode == .pro ? "radar" : "plane",
                           size: 16,
                           fallback: mode == .pro ? "scope" : "airplane")
                    .foregroundStyle(selected ? Theme.teal : Theme.inkSecondary)
                    .padding(.top, 2)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(mode.title) mode")
                        .font(TypeScale.bodyStrong)
                        .foregroundStyle(Theme.ink)
                    Text(mode.subtitle)
                        .font(TypeScale.caption)
                        .foregroundStyle(Theme.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                if selected {
                    LucideIcon(name: "check", size: 14, fallback: "checkmark")
                        .foregroundStyle(Theme.teal)
                }
            }
            .padding(Space.sm)
            .background(selected ? Theme.teal.opacity(0.08) : Theme.canvas)
            .clipShape(.rect(cornerRadius: Theme.Radius.well))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var aboutCard: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            SectionHeader(icon: "info", title: "About Simple mode")
            Text("Simple mode is a traditional flight tracker: a prediction at the top, gate / takeoff / arrival times, one risk line, and a map when the plane is moving. The nerd stack — evidence, ATC flow, G-AIRMET, ops, chat — stays in Pro.")
                .font(TypeScale.caption)
                .foregroundStyle(Theme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .cardStyle()
    }

    private var modeBinding: Binding<AppDisplayMode> {
        Binding(
            get: { store.displayMode },
            set: { newValue in
                guard store.displayMode != newValue else { return }
                Haptics.tap()
                store.displayMode = newValue
            })
    }
}
