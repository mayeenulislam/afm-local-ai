import Foundation

enum AppSupport {
    static let directoryName = "Local AI (AFM)"

    static func migrateLegacyContainer() {
        let fm = FileManager.default
        let applicationSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let legacy = applicationSupport.appendingPathComponent("LocalFMStudio", isDirectory: true)
        let current = applicationSupport.appendingPathComponent(directoryName, isDirectory: true)
        guard fm.fileExists(atPath: legacy.path), !fm.fileExists(atPath: current.path) else { return }
        try? fm.moveItem(at: legacy, to: current)
    }

    /// Restricts a path to the app user (0700 dirs / 0600 files), so persisted
    /// chats, saved responses, MCP config (API tokens), and chunk indexes are
    /// not world-readable. Secures the item plus every ancestor directory up to
    /// (excluding) the container root, so nested layouts like `Indexes/<hash>/`
    /// never inherit a permissive umask. It does not recurse into siblings.
    static func secure(_ url: URL, isDirectory: Bool) {
        let fm = FileManager.default
        let target = url.standardizedFileURL
        guard isInsideContainer(target) else { return }
        try? fm.setAttributes([FileAttributeKey.posixPermissions: isDirectory ? 0o700 : 0o600], ofItemAtPath: target.path)

        let base = baseDirectory.standardizedFileURL.path
        var directory = target.deletingLastPathComponent()
        while directory.path != base, directory.path.hasPrefix(base + "/") {
            try? fm.setAttributes([FileAttributeKey.posixPermissions: 0o700], ofItemAtPath: directory.path)
            let parent = directory.deletingLastPathComponent()
            if parent.path == directory.path { break }
            directory = parent
        }
    }

    private static func isInsideContainer(_ url: URL) -> Bool {
        let base = baseDirectory.standardizedFileURL.path
        return url.path == base || url.path.hasPrefix(base + "/")
    }

    static var baseDirectory: URL {
        let fm = FileManager.default
        let applicationSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return applicationSupport.appendingPathComponent(directoryName, isDirectory: true)
    }
}