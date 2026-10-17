import Foundation
import CoreServices

final class Watcher {
    private var stream: FSEventStreamRef?
    private var pending: DispatchWorkItem?
    private let queue = DispatchQueue.main
    private var pendingPaths: Set<String> = []
    private let paths: [String]
    var changed: (([String]) -> Void)?

    init(paths: [String], changed: @escaping ([String]) -> Void) {
        self.changed = changed
        self.paths = paths
        var context = FSEventStreamContext(version: 0, info: Unmanaged.passUnretained(self).toOpaque(), retain: nil, release: nil, copyDescription: nil)
        stream = FSEventStreamCreate(nil, { _, info, count, eventPaths, flags, _ in
            guard let info else { return }
            let watcher = Unmanaged<Watcher>.fromOpaque(info).takeUnretainedValue()
            let paths = unsafeBitCast(eventPaths, to: NSArray.self) as? [String] ?? []
            watcher.pendingPaths.formUnion(paths)
            if (0..<count).contains(where: { flags[$0] & FSEventStreamEventFlags(kFSEventStreamEventFlagMustScanSubDirs | kFSEventStreamEventFlagRootChanged) != 0 }) {
                watcher.pendingPaths.formUnion(watcher.paths)
            }
            watcher.pending?.cancel()
            let item = DispatchWorkItem { [weak watcher] in
                guard let watcher else { return }
                let paths = Array(watcher.pendingPaths)
                watcher.pendingPaths.removeAll()
                watcher.changed?(paths)
            }
            watcher.pending = item
            watcher.queue.asyncAfter(deadline: .now() + 0.12, execute: item)
        }, &context, paths as CFArray, FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 0.08, FSEventStreamCreateFlags(kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagWatchRoot))
        if let stream { FSEventStreamSetDispatchQueue(stream, queue); FSEventStreamStart(stream) }
    }
    deinit {
        pending?.cancel()
        if let stream { FSEventStreamStop(stream); FSEventStreamInvalidate(stream); FSEventStreamRelease(stream) }
    }
}
