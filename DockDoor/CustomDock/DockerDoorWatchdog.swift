import Foundation

/// Small log file in ~/Library/Logs/DockerDoor/dockerdoor.log for diagnosing freezes.
enum DockerDoorLog {
    private static let queue = DispatchQueue(label: "de.leonardjaeger.DockerDoor.log", qos: .utility)
    private static let maxBytes = 1_000_000

    static let fileURL: URL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs/DockerDoor", isDirectory: true)
        .appendingPathComponent("dockerdoor.log")

    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return formatter
    }()

    static func write(_ message: String) {
        let line = "\(formatter.string(from: Date()))  \(message)\n"
        queue.async {
            let manager = FileManager.default
            try? manager.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            if let attributes = try? manager.attributesOfItem(atPath: fileURL.path),
               let size = attributes[.size] as? Int, size > maxBytes
            {
                let old = fileURL.deletingPathExtension().appendingPathExtension("old.log")
                try? manager.removeItem(at: old)
                try? manager.moveItem(at: fileURL, to: old)
            }
            guard let data = line.data(using: .utf8) else { return }
            if let handle = try? FileHandle(forWritingTo: fileURL) {
                handle.seekToEndOfFile()
                handle.write(data)
                try? handle.close()
            } else {
                try? data.write(to: fileURL)
            }
        }
    }
}

/// Notices when DockerDoor's main thread stops responding and writes it to the log.
final class MainThreadWatchdog {
    static let shared = MainThreadWatchdog()

    private let queue = DispatchQueue(label: "de.leonardjaeger.DockerDoor.watchdog", qos: .utility)
    private var timer: DispatchSourceTimer?
    private let lock = NSLock()
    private var lastPong = Date()
    private var hangStart: Date?

    func start() {
        guard timer == nil else { return }
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 1, repeating: 0.5)
        timer.setEventHandler { [weak self] in self?.check() }
        timer.resume()
        self.timer = timer
    }

    private func check() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            lock.lock()
            lastPong = Date()
            lock.unlock()
        }
        lock.lock()
        let silence = Date().timeIntervalSince(lastPong)
        lock.unlock()

        if silence > 2 {
            if hangStart == nil {
                hangStart = Date().addingTimeInterval(-silence)
                DockerDoorLog.write("WARNUNG: Haupt-Thread reagiert seit \(String(format: "%.1f", silence)) s nicht")
            }
        } else if let start = hangStart {
            DockerDoorLog.write("Haupt-Thread wieder frei nach \(String(format: "%.1f", Date().timeIntervalSince(start))) s")
            hangStart = nil
        }
    }
}
