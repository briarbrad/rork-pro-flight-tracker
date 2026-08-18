import SwiftUI

/// Sheet for adding a flight to the watchlist: ident + date + check interval.
struct AddFlightSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var ident: String = ""
    @State private var date: Date = Date()
    @State private var intervalMinutes: Int = 15
    @State private var isSubmitting: Bool = false
    @State private var errorMessage: String?
    @FocusState private var identFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Flight number (e.g. DL244)", text: $ident)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .focused($identFocused)
                        .font(TypeScale.control)

                    DatePicker("Date", selection: $date, displayedComponents: .date)
                } header: {
                    Text("Flight")
                } footer: {
                    Text("Use the airline code plus number — the engine looks it up on FlightAware.")
                }

                Section {
                    Stepper(value: $intervalMinutes, in: 5...240, step: 5) {
                        HStack {
                            Text("Server check interval")
                            Spacer()
                            Text("\(intervalMinutes) min")
                                .foregroundStyle(Theme.inkSecondary)
                                .monospacedDigit()
                        }
                    }
                } footer: {
                    Text("How often the engine re-checks this flight in the background. Shorter intervals spend more FlightAware credit.")
                }

                if let errorMessage {
                    Section {
                        Label {
                            Text(errorMessage)
                        } icon: {
                            LucideIcon(name: "triangle-alert", size: 16,
                                       fallback: "exclamationmark.triangle")
                        }
                        .foregroundStyle(Theme.red)
                        .font(TypeScale.body)
                    }
                }

                Section {
                    Button {
                        submit()
                    } label: {
                        HStack {
                            Spacer()
                            if isSubmitting {
                                ProgressView().tint(.white)
                                Text("Checking flight…")
                            } else {
                                LucideIcon(name: "radar", size: 16, fallback: "plus")
                                Text("Track flight")
                            }
                            Spacer()
                        }
                        .font(TypeScale.control)
                        .foregroundStyle(.white)
                        .padding(.vertical, 6)
                    }
                    .listRowBackground(Theme.teal)
                    .disabled(isSubmitting || ident.trimmingCharacters(in: .whitespaces).count < 3)
                }
            }
            .navigationTitle("Track a flight")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Theme.inkSecondary)
                }
            }
            .onAppear { identFocused = true }
        }
        .presentationDetents([.medium, .large])
    }

    private func submit() {
        guard !isSubmitting else { return }
        isSubmitting = true
        errorMessage = nil
        Haptics.tap()
        let flightIdent = ident
        let flightDate = date
        let interval = intervalMinutes
        Task {
            do {
                try await store.addFlight(ident: flightIdent, date: flightDate,
                                          intervalMinutes: interval)
                Haptics.success()
                dismiss()
            } catch {
                errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
                isSubmitting = false
            }
        }
    }
}
