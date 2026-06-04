import AppKit
import EventKit
import Foundation

// MARK: - Configuration

private let reminderMinutesBefore = 5
private let pollIntervalSeconds: TimeInterval = 20
private let reminderWindowSeconds: TimeInterval = 45
private let bannerHeight: CGFloat = 88
private let bannerSlideDuration: TimeInterval = 12
private let bannerBackground = NSColor(calibratedRed: 0.08, green: 0.10, blue: 0.18, alpha: 0.92)
private let bannerAccent = NSColor(calibratedRed: 0.98, green: 0.55, blue: 0.18, alpha: 1.0)

// MARK: - Reminder state

final class ReminderTracker {
    private var shownKeys = Set<String>()
    private let lock = NSLock()

    func shouldShow(eventID: String, start: Date, now: Date) -> Bool {
        let key = "\(eventID)-\(Int(start.timeIntervalSince1970))"
        lock.lock()
        defer { lock.unlock() }

        purge(before: now.addingTimeInterval(-3600))
        guard !shownKeys.contains(key) else { return false }
        shownKeys.insert(key)
        return true
    }

    private func purge(before cutoff: Date) {
        shownKeys = shownKeys.filter { key in
            guard let ts = key.split(separator: "-").last.flatMap({ Int($0) }) else { return true }
            return Date(timeIntervalSince1970: TimeInterval(ts)) >= cutoff
        }
    }
}

// MARK: - Banner overlay

final class BannerController: NSWindowController {
    private let label = NSTextField(labelWithString: "")
    private let accentBar = NSView()
    private var animationTimer: Timer?

    init(text: String) {
        guard let screen = NSScreen.main else {
            fatalError("No main screen")
        }

        let frame = screen.frame
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: frame.maxY - bannerHeight, width: frame.width, height: bannerHeight),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )

        window.level = .screenSaver
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = true
        window.ignoresMouseEvents = true
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]

        super.init(window: window)
        setupContent(text: text, width: frame.width)
        window.orderFrontRegardless()
        startSlideAnimation(screenWidth: frame.width)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupContent(text: String, width: CGFloat) {
        guard let contentView = window?.contentView else { return }

        let background = NSView(frame: NSRect(x: 0, y: 0, width: width, height: bannerHeight))
        background.wantsLayer = true
        background.layer?.backgroundColor = bannerBackground.cgColor
        background.layer?.cornerRadius = 0

        accentBar.frame = NSRect(x: 0, y: 0, width: 6, height: bannerHeight)
        accentBar.wantsLayer = true
        accentBar.layer?.backgroundColor = bannerAccent.cgColor
        background.addSubview(accentBar)

        label.stringValue = text
        label.font = NSFont.systemFont(ofSize: 28, weight: .semibold)
        label.textColor = .white
        label.alignment = .center
        label.frame = NSRect(x: 24, y: (bannerHeight - 34) / 2, width: width - 48, height: 34)
        label.lineBreakMode = .byTruncatingTail
        background.addSubview(label)

        contentView.addSubview(background)
    }

    private func startSlideAnimation(screenWidth: CGFloat) {
        guard let window else { return }

        let startX = screenWidth
        let endX = -screenWidth
        let startTime = Date()

        animationTimer?.invalidate()
        animationTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] timer in
            guard let self, let window = self.window else {
                timer.invalidate()
                return
            }

            let elapsed = Date().timeIntervalSince(startTime)
            let progress = min(elapsed / bannerSlideDuration, 1.0)
            let eased = 1 - pow(1 - progress, 3)
            let x = startX + (endX - startX) * eased

            var frame = window.frame
            frame.origin.x = x
            window.setFrame(frame, display: true)

            if progress >= 1.0 {
                timer.invalidate()
                self.animationTimer = nil
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    window.orderOut(nil)
                    self.close()
                }
            }
        }
        RunLoop.main.add(animationTimer!, forMode: .common)
    }
}

// MARK: - Calendar monitor

final class MeetingMonitor: NSObject {
    private let store = EKEventStore()
    private let tracker = ReminderTracker()
    private var pollTimer: Timer?
    private var accessGranted = false

    func start() {
        requestCalendarAccess { [weak self] granted in
            guard let self else { return }
            self.accessGranted = granted
            if granted {
                self.schedulePolling()
                fputs("Calendar access granted. Monitoring meetings...\n", stderr)
            } else {
                fputs("Calendar access denied. Enable it in System Settings > Privacy & Security > Calendars.\n", stderr)
                NSApp.terminate(nil)
            }
        }
    }

    private func requestCalendarAccess(completion: @escaping (Bool) -> Void) {
        if #available(macOS 14.0, *) {
            store.requestFullAccessToEvents { granted, error in
                if let error {
                    fputs("Calendar access error: \(error.localizedDescription)\n", stderr)
                }
                DispatchQueue.main.async { completion(granted) }
            }
        } else {
            store.requestAccess(to: .event) { granted, error in
                if let error {
                    fputs("Calendar access error: \(error.localizedDescription)\n", stderr)
                }
                DispatchQueue.main.async { completion(granted) }
            }
        }
    }

    private func schedulePolling() {
        pollTimer?.invalidate()
        checkUpcomingMeetings()
        pollTimer = Timer.scheduledTimer(withTimeInterval: pollIntervalSeconds, repeats: true) { [weak self] _ in
            self?.checkUpcomingMeetings()
        }
        RunLoop.main.add(pollTimer!, forMode: .common)
    }

    private func checkUpcomingMeetings() {
        guard accessGranted else { return }

        let now = Date()
        let horizon = now.addingTimeInterval(24 * 3600)
        let predicate = store.predicateForEvents(withStart: now, end: horizon, calendars: nil)
        let events = store.events(matching: predicate)

        let target = TimeInterval(reminderMinutesBefore * 60)
        let halfWindow = reminderWindowSeconds / 2

        for event in events {
            guard !event.isAllDay else { continue }
            let start = event.startDate
            let secondsUntilStart = start.timeIntervalSince(now)
            let secondsUntilReminder = secondsUntilStart - target

            guard abs(secondsUntilReminder) <= halfWindow else { continue }

            let eventID = event.eventIdentifier ?? UUID().uuidString
            guard tracker.shouldShow(eventID: eventID, start: start, now: now) else { continue }

            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm"
            let timeText = formatter.string(from: start)
            let title = event.title?.trimmingCharacters(in: .whitespacesAndNewlines)
            let displayTitle = (title?.isEmpty == false) ? title! : "未命名会议"
            let bannerText = "⏰ \(reminderMinutesBefore) 分钟后 · \(displayTitle) · \(timeText) 开始"

            DispatchQueue.main.async {
                _ = BannerController(text: bannerText)
            }

            fputs("Reminder shown: \(displayTitle) at \(timeText)\n", stderr)
        }
    }
}

// MARK: - App entry

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let monitor = MeetingMonitor()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        monitor.start()
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
_ = NSApplicationMain(CommandLine.argc, CommandLine.unsafeArgv)
