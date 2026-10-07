import Foundation

enum CaptureSettings {
    private static let domain = "com.apple.screencapture"
    private static let store = UserDefaults.standard

    static var location: URL {
        if let path = defaults(["read", domain, "location"]), !path.isEmpty {
            return URL(fileURLWithPath: (path as NSString).expandingTildeInPath, isDirectory: true)
        }
        return FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask)[0]
    }

    static func takeOver(into folder: URL) {
        if !store.bool(forKey: "tookOver") {
            store.set(defaults(["read", domain, "location"]), forKey: "previousLocation")
            store.set(defaults(["read", domain, "show-thumbnail"]), forKey: "previousThumbnail")
            store.set(true, forKey: "tookOver")
        }
        defaults(["write", domain, "location", "-string", folder.path])
        defaults(["write", domain, "show-thumbnail", "-bool", "false"])
    }

    static func restore() {
        guard store.bool(forKey: "tookOver") else { return }

        if let location = store.string(forKey: "previousLocation") {
            defaults(["write", domain, "location", "-string", location])
        } else {
            defaults(["delete", domain, "location"])
        }

        if let thumbnail = store.string(forKey: "previousThumbnail") {
            defaults(["write", domain, "show-thumbnail", "-bool", thumbnail == "1" ? "true" : "false"])
        } else {
            defaults(["delete", domain, "show-thumbnail"])
        }

        store.removeObject(forKey: "previousLocation")
        store.removeObject(forKey: "previousThumbnail")
        store.set(false, forKey: "tookOver")
    }

    @discardableResult
    private static func defaults(_ arguments: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
        process.arguments = arguments
        let output = Pipe()
        process.standardOutput = output
        process.standardError = Pipe()
        do {
            try process.run()
        } catch {
            return nil
        }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
