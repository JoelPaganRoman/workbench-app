import Foundation

enum WorkbenchTab: String, CaseIterable, Identifiable, Codable {
    case docs, sheets, slides, gemini, drive
    case gmail, calendar, keep, meet

    var id: String { rawValue }

    /// The tabs the original Electron app shipped with — the default set.
    static let defaultEnabled = "docs,sheets,slides,gemini,drive"

    var label: String {
        switch self {
        case .docs:     return "Docs"
        case .sheets:   return "Sheets"
        case .slides:   return "Slides"
        case .gemini:   return "Gemini"
        case .drive:    return "Drive"
        case .gmail:    return "Gmail"
        case .calendar: return "Calendar"
        case .keep:     return "Keep"
        case .meet:     return "Meet"
        }
    }

    var symbol: String {
        switch self {
        case .docs:     return "doc.text"
        case .sheets:   return "tablecells"
        case .slides:   return "rectangle.on.rectangle"
        case .gemini:   return "sparkles"
        case .drive:    return "externaldrive"
        case .gmail:    return "envelope"
        case .calendar: return "calendar"
        case .keep:     return "note.text"
        case .meet:     return "video"
        }
    }

    var url: URL {
        switch self {
        case .docs:     return URL(string: "https://docs.google.com/document/u/0/")!
        case .sheets:   return URL(string: "https://docs.google.com/spreadsheets/u/0/")!
        case .slides:   return URL(string: "https://docs.google.com/presentation/u/0/")!
        case .gemini:   return URL(string: "https://gemini.google.com/app")!
        case .drive:    return URL(string: "https://drive.google.com/drive/u/0/my-drive")!
        case .gmail:    return URL(string: "https://mail.google.com/mail/u/0/")!
        case .calendar: return URL(string: "https://calendar.google.com/calendar/u/0/r")!
        case .keep:     return URL(string: "https://keep.google.com/")!
        case .meet:     return URL(string: "https://meet.google.com/")!
        }
    }

    /// Mirrors the Electron app's classifyUrl(): which tab does a URL belong to?
    /// Unwraps Google's /url?q= redirector first so links shared by Gemini
    /// route to the right tab.
    static func classify(_ url: URL) -> (tab: WorkbenchTab?, resolved: URL) {
        var u = url
        if (u.host == "www.google.com" || u.host == "google.com"), u.path == "/url",
           let comps = URLComponents(url: u, resolvingAgainstBaseURL: false),
           let inner = comps.queryItems?.first(where: { $0.name == "q" || $0.name == "url" })?.value,
           let innerURL = URL(string: inner), innerURL.host != nil {
            u = innerURL
        }
        guard let host = u.host else { return (nil, u) }
        if host.contains("drive.google.com") { return (.drive, u) }
        if host.contains("gemini.google.com") { return (.gemini, u) }
        if host.contains("mail.google.com") { return (.gmail, u) }
        if host.contains("calendar.google.com") { return (.calendar, u) }
        if host.contains("keep.google.com") { return (.keep, u) }
        if host.contains("meet.google.com") { return (.meet, u) }
        if host.contains("docs.google.com") || host.contains("sheets.google.com") || host.contains("slides.google.com") {
            if u.path.hasPrefix("/spreadsheets") { return (.sheets, u) }
            if u.path.hasPrefix("/presentation") { return (.slides, u) }
            if u.path.hasPrefix("/document") { return (.docs, u) }
        }
        return (nil, u)
    }
}
