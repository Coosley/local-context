# Infrastructure

Where the system runs and how it is exposed. Provider-neutral: fill in what applies (e.g. Cloudflare, AWS, GCP, Azure, Vercel, Netlify, Fly, bare metal).

## Providers
| Layer | Provider | Notes |
|---|---|---|
| DNS / registrar | <...> | <zones, who owns the account> |
| CDN / edge / WAF | <...> | <cache rules, WAF rules, rate limits, bot protection> |
| Hosting / compute | <...> | <region, scaling> |
| Database / storage | <...> | <backups, access> |
| Email / queues / other | <...> | <...> |

## Edge and network
- TLS mode and certificates: <...>
- Proxying, redirects, headers set at the edge: <...>
- Firewall / access rules: <...>
- Serverless / edge functions, bindings: <names only>

## Access and accounts
- Who has access to what: <roles, not credentials>
- IaC location: <terraform/, wrangler.toml, ...> — change infra through it, not by hand

## Secrets and config
- Where secrets live: <vault / platform secrets>. Names only here, never values.
- Env var NAMES: see `deployment.md`

## Cost and limits
- <quotas, billing alerts, free-tier limits>

## Runbook
- Outage checks: <where to look first>
- Rollback / failover: <...>
