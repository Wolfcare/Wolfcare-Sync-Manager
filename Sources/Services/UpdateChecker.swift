import Foundation

/// Checks GitHub Releases for a newer published version of the app. Compares
/// the release tag against the app's own marketing version (the "1.0.0" part
/// of CFBundleShortVersionString, not the build number in parentheses) — so
/// this only fires when an actual versioned release is cut and published,
/// not on every local dev build.
enum UpdateChecker {
    struct ReleaseInfo: Equatable {
        let version: String
        let tagName: String
        let htmlURL: URL
        let publishedAt: Date?
        let notes: String
    }

    enum CheckError: LocalizedError {
        case badResponse
        case decoding

        var errorDescription: String? {
            switch self {
            case .badResponse: return "GitHub didn't respond as expected. Check your internet connection and try again."
            case .decoding: return "Couldn't understand GitHub's response."
            }
        }
    }

    private static let apiURL = URL(string: "https://api.github.com/repos/Wolfcare/Wolfcare-Sync-Manager/releases/latest")!

    /// The app's marketing version, e.g. "1.0.0" — CFBundleShortVersionString
    /// is "1.0.0 (7)" (version + build number), so this strips the parenthetical.
    static var currentAppVersion: String {
        let raw = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
        if let parenIndex = raw.firstIndex(of: "(") {
            return raw[..<parenIndex].trimmingCharacters(in: .whitespaces)
        }
        return raw
    }

    /// Fetches the latest published (non-draft, non-prerelease) GitHub release.
    /// Returns nil — not an error — if the repo has no qualifying releases yet.
    static func fetchLatestRelease() async throws -> ReleaseInfo? {
        var request = URLRequest(url: apiURL)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("ImitorSyncManager", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 10

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw CheckError.badResponse }
        if http.statusCode == 404 { return nil }
        guard (200...299).contains(http.statusCode) else { throw CheckError.badResponse }

        struct GitHubRelease: Decodable {
            let tag_name: String
            let html_url: String
            let published_at: String?
            let body: String?
            let draft: Bool
            let prerelease: Bool
        }

        guard let release = try? JSONDecoder().decode(GitHubRelease.self, from: data) else {
            throw CheckError.decoding
        }
        guard !release.draft, !release.prerelease, let url = URL(string: release.html_url) else {
            return nil
        }

        let version = release.tag_name.hasPrefix("v") ? String(release.tag_name.dropFirst()) : release.tag_name
        let published = release.published_at.flatMap { ISO8601DateFormatter().date(from: $0) }

        return ReleaseInfo(
            version: version,
            tagName: release.tag_name,
            htmlURL: url,
            publishedAt: published,
            notes: release.body ?? ""
        )
    }

    /// Dotted numeric version comparison ("1.2.0" > "1.1.9"); non-numeric
    /// components compare as 0, and a missing trailing component compares as 0.
    static func isNewer(_ remote: String, than current: String) -> Bool {
        let remoteParts = remote.split(separator: ".").map { Int($0) ?? 0 }
        let currentParts = current.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(remoteParts.count, currentParts.count) {
            let r = i < remoteParts.count ? remoteParts[i] : 0
            let c = i < currentParts.count ? currentParts[i] : 0
            if r != c { return r > c }
        }
        return false
    }
}
