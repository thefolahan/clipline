import Foundation
import UniformTypeIdentifiers

final class FolderWatcher {
    let directory: URL
    private let acceptAll: Bool
    private let onNew: (URL) -> Void
    private let onChange: () -> Void
    private var source: DispatchSourceFileSystemObject?
    private var known: Set<String> = []

    init?(directory: URL, acceptAll: Bool, onNew: @escaping (URL) -> Void, onChange: @escaping () -> Void) {
        self.directory = directory
        self.acceptAll = acceptAll
        self.onNew = onNew
        self.onChange = onChange

        let descriptor = open(directory.path, O_EVTONLY)
        guard descriptor >= 0 else { return nil }
        known = Set(listing())

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .rename, .delete],
            queue: .main
        )
        source.setEventHandler { [weak self] in self?.scan() }
        source.setCancelHandler { close(descriptor) }
        source.resume()
        self.source = source
    }

    deinit {
        source?.cancel()
    }

    private func listing() -> [String] {
        (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
    }

    private func scan() {
        let current = Set(listing())
        let added = current.subtracting(known)
        known = current
        onChange()

        for name in added where !name.hasPrefix(".") {
            let url = directory.appendingPathComponent(name)
            guard Self.isImage(url) else { continue }
            check(url, attempt: 0)
        }
    }

    private func check(_ url: URL, attempt: Int) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            guard let self, FileManager.default.fileExists(atPath: url.path) else { return }
            if self.acceptAll || Self.isScreenCapture(url) {
                self.onNew(url)
            } else if attempt < 8 {
                self.check(url, attempt: attempt + 1)
            }
        }
    }

    static func isImage(_ url: URL) -> Bool {
        UTType(filenameExtension: url.pathExtension)?.conforms(to: .image) ?? false
    }

    static func isScreenCapture(_ url: URL) -> Bool {
        getxattr(url.path, "com.apple.metadata:kMDItemIsScreenCapture", nil, 0, 0, 0) > 0
    }
}
