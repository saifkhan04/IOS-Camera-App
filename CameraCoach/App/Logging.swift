// Logging.swift
// Shared os.Logger instances for unified logging.
//
// Categories show up in Console.app and `log stream`, filterable per subsystem,
// and are far cheaper than print() — messages are only formatted if something is
// actually reading them.

import os

extension Logger {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "com.cameracoach"

    static let camera = Logger(subsystem: subsystem, category: "camera")
    static let motion = Logger(subsystem: subsystem, category: "motion")
    static let capture = Logger(subsystem: subsystem, category: "capture")
}
