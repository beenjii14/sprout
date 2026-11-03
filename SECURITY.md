# Security policy

## Supported versions

Only the latest release receives fixes.

## Reporting a vulnerability

Please **do not open a public issue**. Report it privately through
[GitHub security advisories](https://github.com/beenjii14/sprout/security/advisories/new).
You can expect a first answer within a few days.

## How sprout handles secrets

- The Jira API token is read from `JIRA_API_TOKEN`, the macOS Keychain, libsecret or a `600`-mode file, in that order.
  It is never written to the configuration file.
- The token is passed to `curl` through stdin (`-K -`), so it never appears in process listings.
- With AI naming enabled, the ticket title and the first 1,500 characters of its description are sent to
  Anthropic through your local `claude` CLI. Set `SPROUT_AI=0` to disable it.
- If you pasted a token anywhere it should not be, revoke it at
  <https://id.atlassian.com/manage-profile/security/api-tokens>.
