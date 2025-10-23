//
//  FileLogger.swift
//  ChuTalk
//
//  Created by Claude Code
//

import Foundation

class FileLogger {
    static let shared = FileLogger()

    private let logFileName = "chutalk_debug.log"
    private var logFileURL: URL?
    private let dateFormatter: DateFormatter
    private let queue = DispatchQueue(label: "com.chutalk.filelogger", qos: .utility)

    private init() {
        dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"

        // Get Documents directory
        if let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            logFileURL = documentsDirectory.appendingPathComponent(logFileName)
            print("📝 FileLogger: Log file path: \(logFileURL?.path ?? "unknown")")
        }
    }

    func log(_ message: String, category: String = "General") {
        queue.async { [weak self] in
            guard let self = self, let logFileURL = self.logFileURL else { return }

            let timestamp = self.dateFormatter.string(from: Date())
            let logEntry = "[\(timestamp)] [\(category)] \(message)\n"

            // Also print to console
            print(logEntry, terminator: "")

            // Append to file
            if let data = logEntry.data(using: .utf8) {
                if FileManager.default.fileExists(atPath: logFileURL.path) {
                    if let fileHandle = try? FileHandle(forWritingTo: logFileURL) {
                        fileHandle.seekToEndOfFile()
                        fileHandle.write(data)
                        fileHandle.closeFile()
                    }
                } else {
                    try? data.write(to: logFileURL, options: .atomic)
                }
            }
        }
    }

    func getLogContents() -> String? {
        guard let logFileURL = logFileURL else { return nil }
        return try? String(contentsOf: logFileURL, encoding: .utf8)
    }

    func clearLogs() {
        queue.async { [weak self] in
            guard let self = self, let logFileURL = self.logFileURL else { return }
            try? FileManager.default.removeItem(at: logFileURL)
            self.log("Logs cleared", category: "FileLogger")
        }
    }

    func getLogFileURL() -> URL? {
        return logFileURL
    }
}
