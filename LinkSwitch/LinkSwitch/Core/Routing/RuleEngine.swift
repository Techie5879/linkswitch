import Foundation

struct RuleEngine {
    func target(for context: IncomingOpenContext, config: RouterConfig) -> BrowserTarget {
        AppLogger.info(
            "Evaluating route for URL \(context.url.absoluteString) from source \(context.sourceBundleID ?? "nil")",
            category: .routing
        )

        let defaultTarget = config.defaultBrowserRoute.browserTarget

        if let domainMatch = matchingDomainRule(for: context.url, rules: config.domainRules) {
            AppLogger.info(
                "Matched domain \(domainMatch.domain) to target \(domainMatch.target.description)",
                category: .routing
            )
            return domainMatch.target
        }

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

    private func matchingDomainRule(for url: URL, rules: [DomainRule]) -> DomainRule? {
        guard let host = url.host(percentEncoded: false), !host.isEmpty else {
            AppLogger.info("URL \(url.absoluteString) has no hostname for domain-rule matching", category: .routing)
            return nil
        }

        return rules.enumerated()
            .compactMap { index, rule -> (index: Int, rule: DomainRule, domain: String)? in
                guard let domain = DomainRulePattern.normalized(rule.domain),
                      DomainRulePattern.matches(host: host, domain: domain) else {
                    return nil
                }
                return (index, rule, domain)
            }
            .sorted { lhs, rhs in
                lhs.domain.count == rhs.domain.count
                    ? lhs.index < rhs.index
                    : lhs.domain.count > rhs.domain.count
            }
            .first?
            .rule
    }
}
