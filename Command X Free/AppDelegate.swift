// CommandXClone.swift
// A macOS menu bar utility to add Windows-like Cut/Paste (Cmd+X/Cmd+V) to Finder

import Cocoa
import ApplicationServices

// Global flag to track if Cmd+X was pressed
var hasCut = false

// Top-level callback function for key event monitoring
func keyEventCallback(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent, refcon: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    guard type == .keyDown else { return Unmanaged.passUnretained(event) }

    let flags = event.flags
    let keyCode = event.getIntegerValueField(.keyboardEventKeycode)

    guard let frontApp = NSWorkspace.shared.frontmostApplication,
          frontApp.bundleIdentifier == "com.apple.finder" else {
        return Unmanaged.passUnretained(event)
    }

    // Cmd + X = Cut
    if flags.contains(.maskCommand) && keyCode == 7 { // 'X' key code = 7
        hasCut = true
        sendKeyCombo(key: 8, flags: .maskCommand) // Cmd + C
        return nil
    }
    // Cmd + V = Paste
    else if flags.contains(.maskCommand) && keyCode == 9 && hasCut { // 'V' key code = 9
        sendKeyCombo(key: 9, flags: [.maskCommand, .maskAlternate]) // Option + Cmd + V
        hasCut = false
        return nil
    }

    return Unmanaged.passUnretained(event)
}

// Sends a keyboard combo like Cmd+C or Option+Cmd+V
func sendKeyCombo(key: CGKeyCode, flags: CGEventFlags) {
    let src = CGEventSource(stateID: .combinedSessionState)

    let keyDown = CGEvent(keyboardEventSource: src, virtualKey: key, keyDown: true)
    let keyUp = CGEvent(keyboardEventSource: src, virtualKey: key, keyDown: false)

    keyDown?.flags = flags
    keyUp?.flags = flags

    keyDown?.post(tap: .cghidEventTap)
    keyUp?.post(tap: .cghidEventTap)
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var eventTap: CFMachPort?
    var runLoopSource: CFRunLoopSource?

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        requestAccessibilityPermission()
        setupMenuBarIcon()
        startKeyMonitoring()
        if !AXIsProcessTrusted() {
            // Start monitoring for permission grant
            DispatchQueue.global().async {
                while !AXIsProcessTrusted() {
                    sleep(1)
                }

                // Once granted, restart the app
                DispatchQueue.main.async {
                    let task = Process()
                    task.launchPath = "/usr/bin/open"
                    task.arguments = [Bundle.main.bundlePath]
                    try? task.run()
                    NSApp.terminate(nil)
                }
            }
        }
    }

    func setupMenuBarIcon() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "scissors", accessibilityDescription: "CutX")
        }
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(quitApp), keyEquivalent: "q"))
        statusItem.menu = menu
    }

    @objc func quitApp() {
        if let eventTap = eventTap {
            CFMachPortInvalidate(eventTap)
        }
        NSApplication.shared.terminate(nil)
    }

    func requestAccessibilityPermission() {
        if !AXIsProcessTrusted() {
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            AXIsProcessTrustedWithOptions(options)
        }
    }

    func startKeyMonitoring() {
        let eventMask = CGEventMask(1 << CGEventType.keyDown.rawValue)

        eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: keyEventCallback,
            userInfo: nil
        )

        if let eventTap = eventTap {
            runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
            CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
            CGEvent.tapEnable(tap: eventTap, enable: true)
        }
    }
}
