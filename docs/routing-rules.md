# Routing rules

LinkSwitch evaluates every incoming URL through one routing pipeline:

1. **Domain rules.** A rule matches its exact hostname and any subdomain. For example, `example.com` matches both `example.com` and `docs.example.com`, but not `notexample.com`.
2. **Source-app rules.** If no domain rule matches and the sender bundle ID is available, the first matching source-app rule wins.
3. **Default browser route.** If neither rule type matches, LinkSwitch uses the configured default browser, including its selected profile or Zen container.

When multiple domain rules match, the most-specific hostname wins. For example, `team.example.com` wins over `example.com` for `docs.team.example.com`. Domain matching is case-insensitive, and preferences normalize saved domains to lowercase without a trailing dot.

Domain rules accept hostnames only. They do not match URL paths, query strings, fragments, or arbitrary wildcard patterns.
