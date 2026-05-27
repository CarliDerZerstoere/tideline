import SwiftUI
import PDFKit

/// Doctor PDF export sheet (task #46). Four-state flow:
///   configure → generating → ready (share) → optional error.
///
/// Mirrors the styling of `HealthKitImportSheet`. The renderer lives in
/// `DoctorPDFRenderer` as a pure function; this view only orchestrates.
struct DoctorPDFSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.cycleStore) private var store

    @State private var step: PDFStep = .configure
    @State private var cycleCount: Int = 12
    @State private var includeEvents: Bool = true
    @State private var includeSymptoms: Bool = false
    @State private var patientHeader: String = ""

    @State private var lastFileURL: URL?
    @State private var lastReceipt: ExportReceipt?
    @State private var lastThumbnail: UIImage?
    @State private var errorMessage: String?

    enum PDFStep: Equatable {
        case configure
        case generating
        case ready
        case error
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    switch step {
                    case .configure: configureStep
                    case .generating: generatingStep
                    case .ready: readyStep
                    case .error: errorStep
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 24)
                .padding(.bottom, 24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(PageBackground.color(scheme: colorScheme).ignoresSafeArea())
            .navigationTitle("Frauenarzt-Bericht")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Schließen") { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Configure

    private var configureStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Bericht für meinen Frauenarzt-Termin")
                .tidelineSerifHeadline(size: 28, relativeTo: .title)
                .fontDesign(.serif)
                .italic()
                .fontWeight(.bold)

            Text("Tideline erstellt einen privaten PDF-Bericht auf deinem Gerät — kein Upload, kein Cloud.")
                .font(.body)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 14) {
                Stepper(value: $cycleCount, in: 3...60) {
                    HStack {
                        Text("Anzahl Zyklen")
                        Spacer()
                        Text("\(cycleCount)")
                            .foregroundStyle(.secondary)
                    }
                }
                Toggle("Ereignis-Liste einschließen", isOn: $includeEvents)
                Toggle("Symptom-Journal (letzte 30 Tage)", isOn: $includeSymptoms)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Name (optional)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField("z. B. Maria Mustermann, geb. 01.01.1990", text: $patientHeader)
                        .textFieldStyle(.roundedBorder)
                        .submitLabel(.done)
                }
            }
            .padding(14)
            .background(
                Color.primary.opacity(0.04),
                in: RoundedRectangle(cornerRadius: 12)
            )

            Spacer(minLength: 12)

            primaryButton("Bericht erstellen") {
                Task { await generate() }
            }

            // Audit Wave-A fix (4.5): plain-language description of the
            // tamper-evidence receipt. The German gynecologist user
            // doesn't know what "SHA-256" means; the previous copy
            // surfaced the technical term in the smallest, lowest-
            // contrast text on the sheet. Now we explain what the
            // receipt does without leading with a hash-algorithm name.
            Text("Tideline fügt dem Bericht einen Echtheitsstempel hinzu, damit du nachweisen kannst, dass er seit der Erstellung nicht verändert wurde.")
                .font(.caption2)
                // Task #133 — was .tertiary; bumped to .secondary (WCAG AA on body text).
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    // MARK: - Generating

    private var generatingStep: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.2)
            Text("Bericht wird erstellt …")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 280)
    }

    // MARK: - Ready

    private var readyStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Bericht bereit")
                .tidelineSerifHeadline(size: 24, relativeTo: .title2)
                .fontDesign(.serif)
                .italic()
                .fontWeight(.bold)

            if let thumb = lastThumbnail {
                Image(uiImage: thumb)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxHeight: 340)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.5)
                    )
                    .shadow(color: .black.opacity(0.08), radius: 6, y: 2)
            }

            if let receipt = lastReceipt {
                VStack(alignment: .leading, spacing: 4) {
                    // Audit Wave-A fix (4.5): renamed "Beleg" →
                    // "Echtheitsstempel" so the section header carries
                    // the plain-language meaning of the hash, not just
                    // "receipt" (which a German user might confuse with
                    // payment terminology).
                    Text("Echtheitsstempel")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("SHA-256:\(receipt.shortHex)…")
                        .font(.system(size: 11, design: .monospaced))
                        .textSelection(.enabled)
                    // Sub-line explaining what the hex does, in plain
                    // German. Below the monospaced hash so a curious
                    // user can connect the code to the explanation.
                    Text("Dieser Code beweist, dass der Bericht seit der Erstellung nicht verändert wurde.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(receipt.generatedAtISO8601)
                        .font(.system(size: 10, design: .monospaced))
                        // Task #133 — was .tertiary; bumped to .secondary so the
                        // timestamp (forensically important on the export receipt)
                        // is legible. WCAG AA gate.
                        .foregroundStyle(.secondary)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    Color.primary.opacity(0.04),
                    in: RoundedRectangle(cornerRadius: 8)
                )
            }

            Spacer(minLength: 12)

            if let url = lastFileURL {
                ShareLink(item: url) {
                    Text("Teilen")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 50)
                        .background(Self.coralGradient, in: RoundedRectangle(cornerRadius: 14))
                        .shadow(color: Color(red: 0.91, green: 0.44, blue: 0.44).opacity(0.35), radius: 12, y: 4)
                }
                // A11y sweep (audit fix #131 follow-up): the gradient-coral
                // primary affordance doesn't translate to VoiceOver. Spell
                // out the action + that the share uses the iOS share sheet
                // (image, email, AirDrop, Files, etc.) so VoiceOver users
                // know what to expect on tap.
                .accessibilityLabel("PDF-Bericht teilen")
                .accessibilityHint("Öffnet die iOS-Teilen-Übersicht — du kannst den Bericht per Mail, AirDrop oder in die Dateien-App schicken.")
            }

            Button("Schließen") { dismiss() }
                .frame(maxWidth: .infinity, minHeight: 44)
        }
    }

    // MARK: - Error

    private var errorStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(.orange)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, 24)
            Text("Bericht konnte nicht erstellt werden")
                .font(.system(size: 18, weight: .semibold))
                .frame(maxWidth: .infinity, alignment: .center)
            Text(errorMessage ?? "")
                .font(.body)
                .foregroundStyle(.secondary)
            primaryButton("Erneut versuchen") {
                step = .configure
            }
        }
    }

    // MARK: - Buttons / shared

    private func primaryButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 50)
                .background(Self.coralGradient, in: RoundedRectangle(cornerRadius: 14))
                .shadow(color: Color(red: 0.91, green: 0.44, blue: 0.44).opacity(0.35), radius: 12, y: 4)
        }
        .buttonStyle(.plain)
    }

    private static let coralGradient = LinearGradient(
        colors: [Color(red: 0.93, green: 0.48, blue: 0.48), Color(red: 0.88, green: 0.38, blue: 0.38)],
        startPoint: .top,
        endPoint: .bottom
    )

    // MARK: - Actions

    private func generate() async {
        guard let store else {
            errorMessage = "Datenquelle nicht verfügbar."
            step = .error
            return
        }
        step = .generating
        // Brief min-display so the transition reads as deliberate rather
        // than a flicker (typical render <300 ms).
        let started = Date.now
        let data = await store.doctorPDFData(
            maxCycles: cycleCount,
            includeEvents: includeEvents,
            includeSymptoms: includeSymptoms,
            patientHeader: patientHeader
        )
        let (pdf, receipt) = DoctorPDFRenderer.render(data: data)
        let elapsed = Date.now.timeIntervalSince(started)
        if elapsed < 0.4 {
            try? await Task.sleep(nanoseconds: UInt64((0.4 - elapsed) * 1_000_000_000))
        }
        do {
            let url = try writeToTempFile(pdf: pdf)
            lastFileURL = url
            lastReceipt = receipt
            lastThumbnail = thumbnail(from: pdf)
            step = .ready
        } catch {
            errorMessage = error.localizedDescription
            step = .error
        }
    }

    private func writeToTempFile(pdf: Data) throws -> URL {
        let df = DateFormatter()
        df.locale = Locale(identifier: "de_DE")
        df.dateFormat = "yyyy-MM-dd"
        let filename = "Tideline-Zyklusbericht-\(df.string(from: .now)).pdf"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        try pdf.write(to: url, options: .atomic)
        return url
    }

    private func thumbnail(from pdfData: Data) -> UIImage? {
        guard let doc = PDFDocument(data: pdfData), let page = doc.page(at: 0) else { return nil }
        let bounds = page.bounds(for: .mediaBox)
        // Audit Wave-A fix (4.5): explicitly set the renderer format
        // scale to the screen's native scale (3x on iPhone 16 Pro)
        // instead of relying on the default. The previous `scale: 1.0`
        // multiplier produced a 1x raster which iOS upscaled to fit the
        // 340pt preview container — visibly blurry on 3x devices, which
        // is the entire target hardware. PDF rendering is vector, so a
        // bounds-sized canvas at 3x format scale produces a crisp raster
        // at native dimensions without any geometry scaling in the draw
        // block. Fallback to 3.0 if no key window (test isolation).
        let format = UIGraphicsImageRendererFormat()
        let scenes = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
        let window = scenes.flatMap { $0.windows }.first { $0.isKeyWindow }
            ?? scenes.flatMap { $0.windows }.first
        format.scale = window?.screen.scale ?? 3.0
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: bounds.size, format: format)
        return renderer.image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(origin: .zero, size: bounds.size))
            ctx.cgContext.translateBy(x: 0, y: bounds.height)
            ctx.cgContext.scaleBy(x: 1, y: -1)
            page.draw(with: .mediaBox, to: ctx.cgContext)
        }
    }
}

#Preview {
    DoctorPDFSheet()
}
