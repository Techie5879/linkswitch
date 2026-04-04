import Foundation

struct RuleEngine {
    func target(for context: IncomingOpenContext, config: RouterConfig) -> BrowserTarget {
        AppLogger.info(
            "Evaluating route for URL \(context.url.absoluteString) from source \(context.sourceBundleID ?? "nil")",
            category: .routing
        )

        let defaultTarget = config.defaultBrowserRoute.browserTarget

        guard let sourceBundleID = context.sourceBundleID else {
            AppLogger.info(
                "No source bundle ID available, routing to default-browser target \(defaultTarget.description)",
                category: .routing
            )
            return defaultTarget
        }

        guard let target = config.rules.first(where: { $0.sourceBundleID == sourceBundleID })?.target else {
            AppLogger.info(
                "No rule matched source \(sourceBundleID), routing to default-browser target \(defaultTarget.description)",
                category: .routing
            )
            return defaultTarget
        }

        AppLogger.info("Matched source \(sourceBundleID) to target \(target.description)", category: .routing)
        return target
    }
}
