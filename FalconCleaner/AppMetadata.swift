import Foundation

/// Turns an LSApplicationCategoryType into a readable role, e.g.
/// "public.app-category.developer-tools" -> "Developer Tools".
func humanCategory(_ raw: String?) -> String? {
    guard let raw = raw, let last = raw.split(separator: ".").last else { return nil }
    let words = last.split(separator: "-").map { $0.prefix(1).uppercased() + $0.dropFirst() }
    let result = words.joined(separator: " ")
    return result.isEmpty ? nil : result
}

/// Extracts the vendor/maker from an NSHumanReadableCopyright string, e.g.
/// "© 2024 Zoom Video Communications, Inc. All rights reserved." -> "Zoom Video Communications, Inc."
func vendorFromCopyright(_ copyright: String?) -> String? {
    guard var s = copyright else { return nil }
    for phrase in ["All rights reserved", "All Rights Reserved"] {
        s = s.replacingOccurrences(of: phrase, with: "")
    }
    s = s.replacingOccurrences(of: "©", with: " ")
    s = s.replacingOccurrences(of: "(c)", with: " ", options: .caseInsensitive)
    s = s.replacingOccurrences(of: "Copyright", with: " ", options: .caseInsensitive)
    // Drop years and year ranges like "2020" or "2020-2024".
    s = s.replacingOccurrences(of: "[0-9]{4}(\\s*[-–]\\s*[0-9]{4})?", with: " ", options: .regularExpression)
    s = s.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
    s = s.trimmingCharacters(in: CharacterSet(charactersIn: " ,.-–\t"))
    return s.isEmpty ? nil : s
}
