import SwiftUI
import StoreKit

/// "Tideline unterstützen" sheet — the only IAP surface in the app.
///
/// **Generous-free model (R31):** Tideline works fully without any
/// purchase. This sheet exists purely as an optional support channel for
/// users who want to back development. No feature is gated. No upsells.
/// Matches the privacy-first ethos: a paywall would conflict with the
/// "no streaks, no shame, no coercion" positioning.
///
/// Three states:
///   1. **Loading** — product fetch in flight (shown briefly on first open)
///   2. **Available** — "Kaufen" button + price + restore link
///   3. **Supported** — "Danke ❤" celebration state, restore link still
///      visible (in case of cross-device sync need)
struct SupportSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.storeKitService) private var storeKit

    var body: some View {
        NavigationStack {
            ZStack {
                PageBackground.color(scheme: colorScheme).ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        headerSection
                        statusSection
                        actionSection
                        explainerSection
                        Spacer(minLength: 16)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                }
            }
            .navigationTitle("Tideline unterstützen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .task {
            await storeKit?.loadProduct()
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Wenn dir Tideline gefällt")
                .tidelineSerifHeadline(size: 22, relativeTo: .title3)
                .fontDesign(.serif).italic().fontWeight(.bold)
                .accessibilityAddTraits(.isHeader)
            Text("Tideline ist vollständig nutzbar — ohne Abo, ohne Werbung, ohne Datensammlung. Wenn dir die App weiterhilft, kannst du die Entwicklung mit einem einmaligen Beitrag unterstützen.")
                .font(.system(size: 15))
                .foregroundStyle(.primary)
        }
    }

    // MARK: - Status / Action

    @ViewBuilder
    private var statusSection: some View {
        if let storeKit, storeKit.hasSupported {
            cardContainer {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        Image(systemName: "heart.fill")
                            .foregroundStyle(.pink)
                        Text("Du unterstützt Tideline")
                            .font(.system(size: 17, weight: .semibold))
                    }
                    Text("Danke. Das hilft mir, weiter an Tideline zu arbeiten.")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private var actionSection: some View {
        if let storeKit {
            VStack(spacing: 12) {
                if !storeKit.hasSupported {
                    Button {
                        Task { await storeKit.purchase() }
                    } label: {
                        HStack {
                            if storeKit.isPurchasing {
                                ProgressView()
                                    .progressViewStyle(.circular)
                                    .controlSize(.small)
                                    .tint(.white)
                            }
                            Text(buyButtonLabel(storeKit))
                                .fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.accentColor)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .disabled(storeKit.isPurchasing)
                    .accessibilityHint("Kauft den einmaligen Unterstützer-Beitrag.")
                }
                Button {
                    Task { await storeKit.restore() }
                } label: {
                    Text("Käufe wiederherstellen")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                }
                .accessibilityHint("Stellt einen früheren Kauf wieder her, z.B. auf einem neuen Gerät.")
                if let error = storeKit.lastError {
                    Text(error.localizedDescription)
                        .font(.system(size: 12))
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.leading)
                }
            }
        } else {
            Text("StoreKit nicht verfügbar.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
    }

    /// "Kaufen — €4.99" or fallback if product hasn't loaded yet.
    private func buyButtonLabel(_ storeKit: StoreKitService) -> String {
        if let product = storeKit.product {
            return "Unterstützen — \(product.displayPrice)"
        }
        return "Unterstützen"
    }

    // MARK: - Explainer

    private var explainerSection: some View {
        cardContainer {
            VStack(alignment: .leading, spacing: 10) {
                Text("Was du bekommst")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text("Ein gutes Gefühl. Mehr nicht — keine zusätzlichen Funktionen, kein freigeschaltetes Material. Tideline funktioniert für alle gleich.")
                    .font(.system(size: 14))
                    .foregroundStyle(.primary)

                Text("Was dein Beitrag finanziert")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.top, 6)
                Text("Apple-Entwicklergebühr, Recherche, Übersetzung, App-Store-Listing-Material. Tideline hat keine Investoren, kein Marketing-Budget, kein Datengeschäft.")
                    .font(.system(size: 14))
                    .foregroundStyle(.primary)

                Text("Daten")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.top, 6)
                Text("Apple verarbeitet die Zahlung. Ich erhalte keine Kreditkartendaten und keine Identifikationsdaten — nur das anonyme Auszahlungsstatement von Apple.")
                    .font(.system(size: 14))
                    .foregroundStyle(.primary)
            }
        }
    }

    // MARK: - Card container (matches MyCycleSheet pattern)

    @ViewBuilder
    private func cardContainer<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
    }
}

#Preview {
    SupportSheet()
}
