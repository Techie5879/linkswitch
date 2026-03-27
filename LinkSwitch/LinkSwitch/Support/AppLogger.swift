import Foundation
import OSLog

enum AppLogCategory: String {
    case app
    case config
    case routing
    case launch
    case tests
}

enum AppLogger {
    private static let subsystem = "dev.helios.LinkSwitch"
    private static let writeLock = NSLock()

    static func debug(_ message: @autoclosure () -> String, category: AppLogCategory) {
        emit(message(), level: "DEBUG", category: category)
    }

    static func info(_ message: @autoclosure () -> String, category: AppLogCategory) {
        emit(message(), level: "INFO", category: category)
    }

    static func error(_ message: @autoclosure () -> String, category: AppLogCategory) {
        emit(message(), level: "ERROR", category: category)
    }

    private static func emit(_ message: String, level: String, category: AppLogCategory) {
        let logger = Logger(subsystem: subsystem, category: category.rawValue)
        let formattedMessage = "[LinkSwitch][\(level)][\(category.rawValue)] \(message)"
        let logLine = "\(Date().ISO8601Format()) \(formattedMessage)"

        switch level {
        case "ERROR":
            logger.error("\(formattedMessage, privacy: .public)")
        case "DEBUG":
            logger.debug("\(formattedMessage, privacy: .public)")
        default:
            logger.info("\(formattedMessage, privacy: .public)")
        }

        print(logLine)
        appendToLogFile(logLine)
    }

    static func logFileURL(fileManager: FileManager = .default) throws -> URL {
        let logsDirectory = developmentProjectRootURL()
            .appendingPathComponent("logs", isDirectory: true)
        return logsDirectory.appendingPathComponent("runtime.log", isDirectory: false)
    }

    private static func appendToLogFile(_ line: String) {
        writeLock.lock()
        defer { writeLock.unlock() }

        do {
            let fileManager = FileManager.default
            let fileURL = try logFileURL(fileManager: fileManager)
            let directoryURL = fileURL.deletingLastPathComponent()
            try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)

            if !fileManager.fileExists(atPath: fileURL.path()) {
                try Data().write(to: fileURL, options: .atomic)
            }

            let handle = try FileHandle(forWritingTo: fileURL)
            defer {
                try? handle.close()
            }

            try handle.seekToEnd()
            if let data = "\(line)\n".data(using: .utf8) {
                try handle.write(contentsOf: data)
            }
        } catch {
            fputs("\(Date().ISO8601Format()) [LinkSwitch][ERROR][app] Failed to append to runtime log: \(error)\n", stderr)
        }
    }

    private static func developmentProjectRootURL(filePath: String = #filePath) -> URL {
        URL(fileURLWithPath: filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
