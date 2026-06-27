import SwiftUI
import Combine

// iOS presentation helpers. Phase 3: the iOS accent is now the Moonstone orb
// primary (#B8D9FF) from the new design system — no amber anywhere. The macOS
// app still uses FelixBrand.accent from shared Constants.swift (untouched).

extension Color {
    /// Felix's iOS accent — the Moonstone orb blue (see FelixColor).
    static let felix = FelixColor.orbPrimary
}

/// Human label + SF Symbol for a backend tool (used by result sheet & history).
func toolMeta(_ tool: String?) -> (label: String, symbol: String) {
    switch tool {
    case "notes.create_from_image", "notes.append_to_note", "notes.list_notes":
        return ("Apple Notes", "note.text")
    case "numbers.create_spreadsheet", "numbers.add_expense",
         "numbers.read_sheet", "numbers.edit_cell":
        return ("Apple Numbers", "tablecells.fill")
    case "slides.create_presentation":                       return ("Google Slides", "rectangle.on.rectangle.angled")
    case "gmail.draft_email", "gmail.reply_draft":           return ("Gmail", "envelope.fill")
    case "gmail.read_inbox", "gmail.read_email":             return ("Inbox", "tray.fill")
    case "browser.open_url", "browser.read_page", "browser.fill_form":
        return ("Chrome", "safari.fill")
    case "media.open_apple_music":                           return ("Apple Music", "music.note")
    case "media.open_spotify", "media.play_pause",
         "media.next_track", "media.previous_track":
        return ("Music", "music.note")
    case "ios.create_reminder":                              return ("Reminder", "checklist")
    case "ios.create_note":                                  return ("Note", "note.text")
    case "ios.open_maps":                                    return ("Maps", "map.fill")
    case "ios.send_message_draft":                           return ("Messages", "message.fill")
    default:                                                 return (tool ?? "Done", "checkmark.seal.fill")
    }
}

/// App-wide settings + backend resolution, backed by UserDefaults so the
/// macOS and iOS apps share the same keys.
@MainActor
final class AppSettings: ObservableObject {
    /// App Group used to share the backend URL with the Share + Widget extensions.
    /// MUST match the App Group capability on every target (see manual Xcode steps).
    static let appGroupID = "group.com.felix.shared"

    @Published var backendOverride: String {
        didSet {
            UserDefaults.standard.set(backendOverride, forKey: FelixBrand.backendURLKey)
            // Mirror into the shared suite so app extensions see the same URL.
            UserDefaults(suiteName: Self.appGroupID)?
                .set(backendOverride, forKey: FelixBrand.backendURLKey)
        }
    }
    @Published var notifyCompletion: Bool {
        didSet { UserDefaults.standard.set(notifyCompletion, forKey: FelixBrand.notifyCompletionKey) }
    }
    @Published var notifyErrors: Bool {
        didSet { UserDefaults.standard.set(notifyErrors, forKey: FelixBrand.notifyErrorsKey) }
    }

    /// Used when no Mac is discovered and no manual URL is set.
    let fallbackURL = "https://felix-production-a0f5.up.railway.app"

    init() {
        let d = UserDefaults.standard
        backendOverride = d.string(forKey: FelixBrand.backendURLKey) ?? ""
        notifyCompletion = d.object(forKey: FelixBrand.notifyCompletionKey) as? Bool ?? true
        notifyErrors = d.object(forKey: FelixBrand.notifyErrorsKey) as? Bool ?? true
        // Seed the shared suite so the Share/Widget extensions have the URL.
        UserDefaults(suiteName: Self.appGroupID)?
            .set(backendOverride, forKey: FelixBrand.backendURLKey)
    }

    /// A manual URL (Settings) wins; otherwise a discovered Mac; otherwise the
    /// public fallback so the demo works off-LAN.
    func resolvedBaseURL(discovery: MacDiscovery) -> String {
        let manual = backendOverride.trimmingCharacters(in: .whitespacesAndNewlines)
        if !manual.isEmpty { return manual.hasSuffix("/") ? String(manual.dropLast()) : manual }
        return discovery.baseURL ?? fallbackURL
    }
}

// MARK: - Reusable presentation pieces

/// A frosted glass surface used across the redesigned screens.
extension View {
    func frostedCard(cornerRadius: CGFloat = 20) -> some View {
        self
            .background(
                DarkBlurView()
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(FelixColor.cardBorder, lineWidth: 1)
            )
    }
}

/// Tinted rounded-square tool icon. Phase 3: a single Moonstone tint (no amber),
/// matching the Phase 8 result-card icon treatment.
struct ToolBadge: View {
    let tool: String?
    var size: CGFloat = 44
    var failed: Bool = false

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
            .fill(failed ? FelixColor.error : FelixColor.orbPrimary)
            .frame(width: size, height: size)
            .overlay(
                Image(systemName: failed ? "exclamationmark.triangle.fill" : ToolStyle.icon(for: tool))
                    .font(.system(size: size * 0.42, weight: .heavy))
                    .foregroundStyle(.black)
            )
    }
}

/// A shimmering skeleton row for list loading states.
struct SkeletonRow: View {
    @State private var on = false
    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 12).frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 7) {
                RoundedRectangle(cornerRadius: 5).frame(width: 200, height: 13)
                RoundedRectangle(cornerRadius: 5).frame(width: 110, height: 10)
            }
            Spacer()
        }
        .foregroundStyle(.white.opacity(on ? 0.12 : 0.05))
        .padding(.vertical, 8)
        .onAppear {
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { on = true }
        }
    }
}

/// Standard dark-mode empty state.
struct FelixEmptyState: View {
    let symbol: String
    let title: String
    let subtitle: String
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 46, weight: .light))
                .foregroundStyle(Color.felix.opacity(0.75))
            Text(title)
                .font(.system(size: 20, weight: .heavy))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
            Text(subtitle)
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(.white.opacity(0.6))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: 320)
        .padding(40)
    }
}
