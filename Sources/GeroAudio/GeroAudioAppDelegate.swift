import AppKit
import SwiftUI

extension Notification.Name {
    static let geroAudioSpacebarPlayback = Notification.Name("GeroAudioSpacebarPlayback")
    static let geroAudioPreviousTrack = Notification.Name("GeroAudioPreviousTrack")
    static let geroAudioNextTrack = Notification.Name("GeroAudioNextTrack")
}

final class GeroAudioAppDelegate: NSObject, NSApplicationDelegate {
    private var keyboardMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        keyboardMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard NSApp.isActive, !event.isARepeat,
                  event.modifierFlags.intersection([.command, .control, .option]).isEmpty else { return event }
            let window = event.window ?? NSApp.keyWindow
            if let editor = window?.firstResponder as? NSTextView, editor.isFieldEditor { return event }
            switch event.keyCode {
            case 49:
                NotificationCenter.default.post(name: .geroAudioSpacebarPlayback, object: nil)
                return nil
            case 126:
                NotificationCenter.default.post(name: .geroAudioPreviousTrack, object: nil)
                return nil
            case 125:
                NotificationCenter.default.post(name: .geroAudioNextTrack, object: nil)
                return nil
            default: return event
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let keyboardMonitor {
            NSEvent.removeMonitor(keyboardMonitor)
            self.keyboardMonitor = nil
        }
    }
}
