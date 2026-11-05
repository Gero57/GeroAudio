import AppKit
import SwiftUI

extension Notification.Name {
    static let geroAudioSpacebarPlayback = Notification.Name("GeroAudioSpacebarPlayback")
}

final class GeroAudioAppDelegate: NSObject, NSApplicationDelegate {
    private var keyboardMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        keyboardMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard event.keyCode == 49,
                  !event.isARepeat,
                  event.modifierFlags.intersection([.command, .control, .option]).isEmpty,
                  let window = NSApp.keyWindow,
                  window.isKeyWindow else { return event }

            if let responder = window.firstResponder,
               responder is NSTextView || responder is NSTextField {
                return event
            }

            NotificationCenter.default.post(name: .geroAudioSpacebarPlayback, object: nil)
            return nil
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let keyboardMonitor {
            NSEvent.removeMonitor(keyboardMonitor)
            self.keyboardMonitor = nil
        }
    }
}
