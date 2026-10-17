import Foundation
import CoreServices

final class Watcher {
    private var stream: FSEventStreamRef?
    private var pending: DispatchWorkItem?
    private let queue = DispatchQueue.main
    var changed: (() -> Void)?

    init(paths: [String], changed: @escaping () -> Void) {
        self.changed = changed
        var context = FSEventStreamContext(version: 0, info: Unmanaged.passUnretained(self).toOpaque(), retain: nil, release: nil, copyDescription: nil)
        stream = FSEventStreamCreate(nil, { _, info, _, _, _, _ in
            guard let info else { return }
            let watcher = Unmanaged<Watcher>.fromOpaque(info).takeUnretainedValue()
            watcher.pending?.cancel()
            let item = DispatchWorkItem { [weak watcher] in DispatchQueue.main.async { watcher?.changed?() } }
            watcher.pending = item
            watcher.queue.asyncAfter(deadline: .now() + 0.12, execute: item)
        }, &context, paths as CFArray, FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 0.08, FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagWatchRoot))
        if let stream { FSEventStreamSetDispatchQueue(stream, queue); FSEventStreamStart(stream) }
    }
    deinit {
        pending?.cancel()
        if let stream { FSEventStreamStop(stream); FSEventStreamInvalidate(stream); FSEventStreamRelease(stream) }
    }
}
