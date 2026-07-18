import Foundation
import Security

struct ProcessDetails: Equatable {
    var signer: String?        // vendor from the code signature (e.g. "Bitdefender SRL")
    var enclosingApp: String?  // app bundle the executable lives in, if any
}

/// Lazily resolves richer info for a process executable (code-signature vendor and the
/// enclosing .app), cached by path since signatures don't change while the app runs.
final class ProcessInspector {
    static let shared = ProcessInspector()
    private var cache: [String: ProcessDetails] = [:]

    @MainActor
    func detailsAsync(forPath path: String) async -> ProcessDetails {
        if let cached = cache[path] { return cached }
        let details = await Task.detached { Self.compute(forPath: path) }.value
        cache[path] = details
        return details
    }

    private static func compute(forPath path: String) -> ProcessDetails {
        ProcessDetails(signer: signer(forPath: path), enclosingApp: enclosingApp(forPath: path))
    }

    // MARK: - Code signature

    private static func signer(forPath path: String) -> String? {
        let url = URL(fileURLWithPath: path) as CFURL
        var staticCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(url, [], &staticCode) == errSecSuccess,
              let code = staticCode else { return nil }

        var infoCF: CFDictionary?
        let flags = SecCSFlags(rawValue: kSecCSSigningInformation)
        guard SecCodeCopySigningInformation(code, flags, &infoCF) == errSecSuccess,
              let info = infoCF as? [String: Any] else { return nil }

        guard let certs = info[kSecCodeInfoCertificates as String] as? [SecCertificate],
              let leaf = certs.first,
              let summary = SecCertificateCopySubjectSummary(leaf) as String? else { return nil }

        return cleanSigner(summary)
    }

    private static func cleanSigner(_ summary: String) -> String? {
        if summary == "Software Signing" || summary.hasPrefix("Apple") { return "Apple" }
        var s = summary
        for prefix in ["Developer ID Application: ", "Apple Development: ",
                       "3rd Party Mac Developer Application: ", "Mac Developer: "] {
            if s.hasPrefix(prefix) { s = String(s.dropFirst(prefix.count)) }
        }
        // Drop a trailing team identifier like " (GUNFMW623Y)".
        s = s.replacingOccurrences(of: "\\s*\\([A-Z0-9]{6,}\\)$", with: "", options: .regularExpression)
        s = s.trimmingCharacters(in: .whitespaces)
        return s.isEmpty ? nil : s
    }

    // MARK: - Enclosing app

    private static func enclosingApp(forPath path: String) -> String? {
        guard let range = path.range(of: ".app/") else { return nil }
        let appPath = String(path[path.startIndex..<range.lowerBound]) + ".app"
        guard let bundle = Bundle(url: URL(fileURLWithPath: appPath)) else { return nil }
        return bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? bundle.object(forInfoDictionaryKey: "CFBundleName") as? String
            ?? URL(fileURLWithPath: appPath).deletingPathExtension().lastPathComponent
    }
}
