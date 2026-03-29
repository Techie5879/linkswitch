import Foundation

struct RuleEngine {
    func target(for context: IncomingOpenContext, config: RouterConfig) -> BrowserTarget {
        AppLogger.info(
            "Evaluating route for URL \(context.url.absoluteString) from source \(context.sourceBundleID ?? "nil")",
            category: .routing
        )

        let fallbackTarget = config.fallbackBrowserRoute.browserTarget

        guard let sourceBundleID = context.sourceBundleID else {
            AppLogger.info(
                "No source bundle ID available, routing to fallback target \(fallbackTarget.description)",
                category: .routing
            )
            return fallbackTarget
        }

        guard let target = config.rules.first(where: { $0.sourceBundleID == sourceBundleID })?.target else {
            AppLogger.info(
                "No rule matched source \(sourceBundleID), routing to fallback target \(fallbackTarget.description)",
                category: .routing
            )
            return fallbackTarget
        }

        AppLogger.info("Matched source \(sourceBundleID) to target \(target.description)", category: .routing)
        return target
    }
}
