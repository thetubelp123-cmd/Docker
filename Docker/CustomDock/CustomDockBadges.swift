import ApplicationServices
import Cocoa
import Defaults
import SwiftUI

extension Defaults.Keys {
    static let customDockShowBadges = Key<Bool>("customDockShowBadges", default: true)
}

/// Reads app badges ("3", "•") from the hidden macOS Dock. Apps only publish their
/// badge to the macOS Dock, which exposes it via Accessibility as AXStatusLabel.
/// Runs on a background queue with a short timeout, never in an input path.
final class DockBadgeMonitor: ObservableObject {
    static let shared = DockBadgeMonitor()

    /// Standardised app bundle path → badge text.
    @Published private(set) var badges: [String: String] = [:]

    private let queue = DispatchQueue(label: "de.leonardjaeger.DockerDoor.badges", qos: .utility)
    private var timer: DispatchSourceTimer?
    private var settingsTask: Task<Void, Never>?

    func start() {
        guard settingsTask == nil else { return }
        settingsTask = Task { [weak self] in
            for await enabled in Defaults.updates(.customDockShowBadges) {
                await MainActor.run { enabled ? self?.startTimer() : self?.stopTimer() }
            }
        }
    }

    func stop() {
        settingsTask?.cancel()
        settingsTask = nil
        stopTimer()
    }

    private func startTimer() {
        guard timer == nil else { return }
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 0.5, repeating: 2.0, leeway: .milliseconds(300))
        timer.setEventHandler { [weak self] in self?.poll() }
        timer.resume()
        self.timer = timer
    }

    private func stopTimer() {
        timer?.cancel()
        timer = nil
        if !badges.isEmpty { badges = [:] }
    }

    private func poll() {
        guard AXIsProcessTrusted(),
              let dock = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first
        else { return }
        let dockElement = AXUIElementCreateApplication(dock.processIdentifier)
        AXUIElementSetMessagingTimeout(dockElement, 0.5)

        var result: [String: String] = [:]
        for list in children(of: dockElement) where role(of: list) == kAXListRole {
            for item in children(of: list) {
                guard let label = string(item, "AXStatusLabel"), !label.isEmpty,
                      let url = url(of: item)
                else { continue }
                result[url.standardizedFileURL.path] = label
            }
        }
        DispatchQueue.main.async { [weak self] in
            guard let self, badges != result else { return }
            badges = result
        }
    }

    func badge(for tile: DockTile) -> String? {
        switch tile.kind {
        case .app:
            guard let url = tile.url else { return nil }
            return badges[url.standardizedFileURL.path]
        case .group:
            let labels = tile.members.compactMap { badges[URL(fileURLWithPath: $0.path).standardizedFileURL.path] }
            guard !labels.isEmpty else { return nil }
            let numbers = labels.compactMap { Int($0) }
            return numbers.count == labels.count ? String(numbers.reduce(0, +)) : "•"
        default:
            return nil
        }
    }

    // MARK: AX helpers

    private func children(of element: AXUIElement) -> [AXUIElement] {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &value) == .success else { return [] }
        return value as? [AXUIElement] ?? []
    }

    private func role(of element: AXUIElement) -> String? {
        string(element, kAXRoleAttribute)
    }

    private func string(_ element: AXUIElement, _ attribute: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value as? String
    }

    private func url(of element: AXUIElement) -> URL? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXURLAttribute as CFString, &value) == .success, let value else { return nil }
        if let url = value as? URL { return url }
        if CFGetTypeID(value) == CFURLGetTypeID() { return (value as! CFURL) as URL }
        return nil
    }
}

struct DockBadgeView: View {
    let text: String
    let size: CGFloat

    var body: some View {
        let height = max(14, size * 0.36)
        Text(text.count > 4 ? String(text.prefix(3)) + "…" : text)
            .font(.system(size: height * 0.62, weight: .semibold))
            .monospacedDigit()
            .foregroundStyle(.white)
            .padding(.horizontal, height * 0.28)
            .frame(minWidth: height, minHeight: height)
            .background(Capsule().fill(Color(red: 1, green: 0.23, blue: 0.19)))
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.9), lineWidth: 1))
            .shadow(color: .black.opacity(0.25), radius: 1.5, y: 1)
            .fixedSize()
    }
}
