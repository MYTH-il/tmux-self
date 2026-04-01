# CTF Now - Development Masterplan

**Stack:** Rust + React - Axum + Tokio - PostgreSQL + Redis + ClickHouse - Hetzner + Cloudflare - 500+ teams

| Stat | Value |
|---|---|
| Build phases | 6 |
| Target teams | 500+ |
| v1 features | 18 |

## Tech Stack

| Layer | Choice |
|---|---|
| Frontend | React + Vite + TypeScript |
| Backend | Axum + Tokio (Rust) |
| WASM module | `ctf-core` crate (shared logic) |
| Data layer | PostgreSQL - Redis - ClickHouse |
| Infra | Hetzner bare metal - Cloudflare |

> **Architectural keystone:** The `ctf-core` Rust crate is built first and stays the source of truth for flag validation, HMAC derivation, scoring formulas, and forensics algorithms - compiled to a native binary for Axum and a WASM module for React. Everything downstream depends on it.

---

## Phase Roadmap

| Phase | Name | Goal |
|---|---|---|
| 0 | Foundation | Cargo workspace, ctf-core crate scaffold, CI/CD pipeline, Hetzner provisioning, Cloudflare setup, Docker Compose dev env. |
| 1 | Core competition engine | Auth (GitHub/Google OAuth), team management, Jeopardy challenge CRUD, flag validation (HMAC), scoring engine, real-time leaderboard via WebSocket. |
| 2 | Challenge infrastructure | Docker challenge orchestration, nsjail pwn jails, MinIO object storage, dynamic scoring, Git-backed challenge versioning. |
| 3 | Forensics & anti-cheat | KaalChakra port into ctf-core WASM, ClickHouse analytics pipeline, IP correlation, suspicion scoring, admin forensics dashboard. |
| 4 | Infra hardening | Rate limiting, DDoS mitigation, network isolation per team, load testing at 500-team scale, container escape hardening, TLS everywhere. |
| 5 | Live fire & v1 release | Internal dry-run competition, bug bounty window, public v1 launch, post-mortem, v2 backlog grooming. |

---

## Phase 0 - Foundation

Before a single feature is built, the monorepo skeleton, shared crate, CI pipeline, and production infrastructure must exist and be fully verified. No Phase 1 work begins until every gate below passes.

### Deliverables

**Cargo workspace**
Monorepo with crates: `ctf-core`, `ctf-api` (Axum), `ctf-worker`. Shared types and enums across the entire stack - zero TypeScript drift from the start.

**ctf-core crate scaffold**
Stub implementations for flag validation, scoring traits, and HMAC derivation. Compiles to both `x86_64-unknown-linux-gnu` and `wasm32-unknown-unknown` targets from day one.

**CI/CD pipeline**
GitHub Actions: `cargo test`, `cargo clippy`, WASM build check, React build, Docker image build and push to registry on every PR. Branch protection enforced.

**Dev environment**
Docker Compose stack: Axum API, PostgreSQL, Redis, ClickHouse, MinIO, React Vite dev server. One command to spin up the full local platform. `sqlx migrate run` seeds schema.

**Hetzner provisioning**
Bare-metal server(s) provisioned, SSH hardened, firewall rules set. Cloudflare DNS, proxying, and rate-limit rules configured. Caddy or Nginx reverse proxy with TLS termination live.

**Database schema v0**
Core tables via sqlx migrations: `users`, `teams`, `challenges`, `submissions`, `competition_state`. Compile-time query checking confirmed working.

### Exit Gates - all must pass before Phase 1

- [ ] `ctf-core` compiles to native + WASM
- [ ] CI pipeline green on a blank PR
- [ ] Docker Compose stack boots in <60s
- [ ] `sqlx` migrations run cleanly
- [ ] Hetzner server reachable over TLS
- [ ] Cloudflare proxy active
- [ ] Git-backed challenge repo initialised

---

## Phase 1 - Core Competition Engine

The complete competition loop: register -> form team -> view challenges -> submit flag -> see score -> watch leaderboard update live. No challenge containers yet - static flags only. By end of Phase 1, a real internal CTF can run.

**Sequencing note**
Split delivery into Phase 1A (core backend + REST + data model + tests) and Phase 1B (WebSocket + WASM + admin polish). This keeps the scope but reduces integration risk.

### Backend (Axum + Tokio)

**Auth system**
GitHub + Google OAuth via `oxide-auth` or hand-rolled OAuth2. JWT sessions stored in Redis via `deadpool-redis`. Admin role seeded via env var on first run.

**Team management**
Create/join team via invite code. Max team size enforced in `ctf-core`. Team captain can rename and kick members. Solo-play mode (team of 1) supported by default.

**Flag validation engine**
HMAC-SHA256 flag derivation in `ctf-core`. Supports static, regex, and HMAC dynamic flags. Rate limiting per team (Redis sliding window): 5 attempts per challenge per minute. Wrong-answer penalty tracking.

**Submission replay protection**
Idempotency key + TTL on submissions. Reject duplicate flags and cross-team replay attempts with strict ownership checks.

**Scoring engine**
Dynamic scoring formula (1000 -> 100 decay based on solve count) implemented in `ctf-core`. First-blood bonuses. Score freeze toggleable in admin panel. Full score history event log written to PostgreSQL.

**Competition state machine**
States enforced in `ctf-core`: `Registration -> Warmup -> Active -> Frozen -> Ended`. Each state gates permitted actions. Admin UI toggle per state transition.

**Real-time leaderboard**
WebSocket endpoint via `tokio-tungstenite`. Redis pub/sub broadcasts score events. Frontend WASM module handles rank diffing - React only renders the delta. Verified at 500 concurrent connections.

### Frontend (React + Vite + ctf-core WASM)

**Player UI**
Challenge board (category tabs, solved/unsolved state), flag submission form with instant client-side format validation via WASM, solve notifications, first-blood banner.

**Leaderboard UI**
Live-updating team rankings, score-over-time graph (recharts), team detail view. WASM module computes rank diffs - React renders. Score freeze greys out the board visually.

**Admin panel v1**
Challenge CRUD, state machine controls, team list with manual disqualification, announcement broadcaster (WebSocket push), score freeze toggle.

### Testing Checkpoints

- Unit tests for every `ctf-core` function - flag validation, scoring decay, HMAC derivation, state machine transitions.
- Integration tests: full submission flow from HTTP request to PostgreSQL write and Redis pub/sub event.
- WebSocket load test: 500 simulated clients subscribed to leaderboard, measure max broadcast latency (<200ms target).
- Auth edge cases: expired JWT, revoked session, account with no team attempting flag submission.
- Rate limit test: 10 rapid submissions from same team - confirm 6th is rejected within sliding window.

### Exit Gates

- [ ] End-to-end flag submission works
- [ ] Leaderboard updates in <200ms
- [ ] 500 WS clients sustained
- [ ] Rate limiting verified
- [ ] State machine transitions tested
- [ ] Admin panel functional
- [ ] `ctf-core` WASM imported by React

---

## Phase 2 - Challenge Infrastructure

Dynamic challenges with live containers: pwn jails, web challenges. MinIO for file distribution. Git-backed challenge versioning. Per-team instance isolation verified.

### Container Orchestration

**Docker challenge lifecycle**
`ctf-worker` Rust crate manages container spawn, health check, idle timeout, and image-restart reset. One container per team per challenge. Port allocation via Redis-managed pool. No Kubernetes in v1 - raw Docker API via `bollard`.

**nsjail pwn isolation**
All pwn challenges run inside nsjail with seccomp filters. No kernel module dependencies - runs on Hetzner bare metal. Per-team flag injected at spawn time as env var. Network isolated (loopback only). CPU and memory limits enforced.

**Container reset**
Teams can request a fresh container (image restart, not snapshot). New flag injected on restart. Rate-limited: max 5 resets per team per challenge. Reset events logged to ClickHouse for forensics.

### Storage & Assets

**MinIO object storage**
Self-hosted S3-compatible store on Hetzner. Challenge files (binaries, pcaps, images, archives) served via pre-signed URLs with TTL. Admin upload UI in React. No cloud storage costs.

**Git-backed challenge versioning**
Each challenge stored in a Git repo. Admin UI shows current version + last-modified. Rollback via `git checkout`. No custom versioning engine. Challenge metadata (points, category, tags) stored in a `challenge.toml` at repo root.

### Challenge Types Supported in v1

| Type | Access | Flag type |
|---|---|---|
| Web | Containerised web app, unique URL per team | Static or HMAC |
| Pwn / Binary | nsjail container, netcat access | Per-team env var |
| Crypto / Forensics / Misc | File download from MinIO, no container | Static |
| Reverse engineering | Binary download from MinIO | Static or regex |
| OSINT | No infra, text/image description | Static |
| Steganography | File download from MinIO | Regex or static |

### Testing Checkpoints

- Container escape attempt on nsjail-wrapped pwn challenge - verify isolation holds.
- 500 simultaneous container spawns - measure time to ready and port allocation collisions (target: 0 collisions).
- MinIO pre-signed URL expiry - confirm expired URLs return 403, not file content.
- Container reset flow - new flag injected, old session terminated, reset count incremented in Redis.
- Idle container timeout - container with no activity for 30 minutes is reaped, team notified via WebSocket.

### Exit Gates

- [ ] All 6 challenge types provisionable
- [ ] nsjail escape test passed
- [ ] 500 concurrent containers stable
- [ ] MinIO serving assets correctly
- [ ] Git versioning round-trip verified

---

## Phase 3 - Forensics & Anti-Cheat

Port the KaalChakra v4 forensics workbook into `ctf-core` as a WASM module. Build the admin forensics dashboard. Wire ClickHouse for all event analytics. This is CTF Now's primary differentiator from stock CTFd deployments.

### ctf-core Forensics Module (Rust -> WASM)

**Suspicion scoring**
Port KaalChakra's suspicion algorithm into `ctf-core`. Inputs: solve timing, solve order vs global order, submission velocity, IP changes mid-session. Outputs: per-team suspicion score (0-100) recomputed on every solve event.

**IP correlation matrix**
Detect shared IPs across teams. Normalised correlation score accounts for NAT and VPN false positives. Flagged pairs shown in admin dashboard with confidence level and raw evidence (shared IPs, timestamps).

**Solve-order analysis**
Compare each team's solve sequence against the global distribution. Statistically unlikely solve paths (e.g. team solves challenge 2 seconds after first global solve, every time) surface as anomalies.

**Submission timing fingerprint**
Flag submission latency histogram per team. Teams submitting flags significantly faster than median first-attempt time for a given challenge are flagged. Helps catch flag sharing with pre-known answers.

### ClickHouse Analytics Pipeline

**Event ingestion**
All events written to ClickHouse asynchronously via a Tokio channel buffer: flag submissions (correct + wrong), container spawns/resets, WebSocket connects/disconnects, page views, hint unlocks. Zero impact on request latency. Define explicit loss policy (drop vs disk-backed queue) and retry behavior.

**Analytics queries**
Challenge drop-off rate (attempts vs solves per challenge), solve time distribution, per-category engagement, traffic spike detection, geographic distribution of participants. All pre-built as ClickHouse views.

### Admin Forensics Dashboard (React + WASM)

**Suspicion leaderboard**
Teams ranked by suspicion score. Drill down to per-team evidence timeline. One-click disqualify or flag for review.

**IP graph view**
Force-directed graph of IP correlations between teams. Cluster detection highlights collusion rings. WASM computes layout client-side.

**Real-time event feed**
Live stream of all competition events with filter by team/challenge/type. Powered by the same WebSocket infrastructure as the player leaderboard.

### Exit Gates

- [ ] KaalChakra algorithms ported and unit tested
- [ ] `ctf-core` WASM module runs in browser
- [ ] ClickHouse ingesting all event types
- [ ] Forensics dashboard renders on 10k+ events
- [ ] IP correlation tested with seeded fake data
- [ ] Suspicion scores match KaalChakra v4 baseline

---

## Phase 4 - Infra Hardening

The platform must survive a 500-team live competition without degradation. This phase is entirely about stress, security, and operations. No new features - only verification, hardening, and runbook writing.

### Performance & Scale

**500-team load test**
k6 or Locust scripts simulating 500 concurrent teams: simultaneous flag submissions, leaderboard subscriptions, container spawns at competition start (the worst spike). Target: p99 API latency <100ms, zero dropped WebSocket events.

**Redis connection pool tuning**
`deadpool-redis` pool sizing validated under load. Redis memory usage profiled at full competition event volume. Eviction policy confirmed correct for leaderboard cache vs session keys.

**PostgreSQL query audit**
`EXPLAIN ANALYZE` on all hot paths. Indexes verified for: submission lookups by team+challenge, leaderboard sort by score, ClickHouse event foreign keys. Slow query log reviewed.

**Cloudflare rules hardening**
Rate limit rules for submission endpoint, admin panel, auth callbacks. Bot Fight Mode enabled. Firewall rules blocking non-Cloudflare IPs from reaching origin. DDoS simulation run.

### Security Hardening

**Container network isolation**
Verify no cross-team container reachability. iptables rules audited. Each team's containers in a dedicated Docker network.

**nsjail audit**
seccomp profile reviewed. Filesystem mounts confirmed read-only. Resource limits (CPU, memory, pids) stress-tested to confirm enforcement.

**Auth hardening**
CSRF protection on all state-mutating endpoints. JWT expiry, rotation, and revocation tested. Admin endpoints require separate session scope.

**Admin panel isolation**
Separate admin subdomain, short session TTL, 2FA, and IP allowlist during live events. Audit logs enabled for admin actions.

**MinIO access control**
Pre-signed URL TTL minimised. Bucket policies audited - no public bucket listing. Upload endpoint restricted to admin scope only.

**Secrets management**
All secrets via env vars from Hetzner secrets manager or a Vault instance. No secrets in Git or Docker images. Rotation procedure documented.

**TLS everywhere**
Internal service-to-service communication encrypted. PostgreSQL TLS enforced. Redis TLS enforced. MinIO TLS enforced. Certificate rotation automated.

### Operational Readiness

- Runbook written for: server failure recovery, Redis flush recovery, PostgreSQL backup restore, Cloudflare WAF rule rollback.
- Alerting configured: API error rate >1%, WebSocket drop rate >0.1%, container spawn failure, disk >80%.
- Backup schedule verified: PostgreSQL nightly dump to MinIO, ClickHouse cold backup, Redis RDB snapshot.
- RTO/RPO targets defined (per service) and validated with restore drills.
- Distributed tracing and structured logs in place with correlation IDs across API, workers, and WebSocket events.
- Deployment pipeline tested: zero-downtime blue-green deploy of Axum API without dropping WebSocket connections.

### Exit Gates

- [ ] 500-team load test passed
- [ ] p99 API latency <100ms under load
- [ ] Container isolation verified
- [ ] DDoS simulation survived
- [ ] All runbooks written and reviewed
- [ ] Backup restore tested end-to-end
- [ ] Zero-downtime deploy confirmed

---

## Phase 5 - Live Fire & v1 Release

Run a real internal competition before public launch. Treat it as if it were live - real participants, real flags, real forensics monitoring. The bugs you catch here cost nothing. The ones you miss cost everything.

### Internal Dry Run

**Internal CTF event**
10-20 internal teams. Minimum 15 challenges across all supported types. Full competition lifecycle: registration -> active -> freeze -> reveal. Forensics dashboard monitored throughout. All events recorded.

**Chaos engineering**
During the dry run, deliberately: kill the Axum process and time recovery, flush Redis mid-competition and verify leaderboard rebuilds from PostgreSQL, trigger a ClickHouse restart and verify no event loss.

### Bug Bounty / Beta Window

**Invite-only beta**
20-50 external testers (trusted CTF players). Explicit scope: platform bugs, not challenge solutions. Feedback form linked from the platform. Critical bugs block launch; cosmetic bugs go to backlog.

**Penetration test**
Auth bypass attempts, IDOR on team data, flag submission replay attacks, WebSocket flooding, MinIO bucket traversal, admin panel privilege escalation. All findings triaged before go-live.

### v1 Public Launch

- Public registration opens. Cloudflare rate limits tightened for launch traffic spike.
- On-call rotation active immediately post-launch. Pager duty assigned.
- Post-launch monitoring: API error rate, WebSocket stability, ClickHouse ingestion lag, container spawn success rate.
- Post-mortem written after the first live competition. All incidents documented with root cause and fix.
- v2 backlog groomed: seed-based per-team binaries, A/D full engine, AI hint engine, gVisor upgrade, unlock chains.

### v1 Launch Criteria - all required

- [ ] Dry run completed with no P0 bugs
- [ ] All pentest findings resolved or accepted
- [ ] Beta feedback incorporated
- [ ] On-call runbook signed off
- [ ] Monitoring dashboards live
- [ ] v2 backlog exists and is prioritised

---

## Risks & Mitigations

| Severity | Risk | Mitigation |
|---|---|---|
| High | **ctf-core WASM compilation scope creep.** If forensics algorithms are complex, WASM bundle size balloons past 2MB. | Keep `ctf-core` under 5k LOC in v1. Heavy analytics stay server-side in ClickHouse; only scoring + validation + forensics summary scores go into WASM. |
| High | **Container start latency at competition open.** 500 teams hitting "start challenge" simultaneously can spike Docker daemon. | Pre-warm containers shortly before Active state. `ctf-worker` maintains a warm pool per challenge type. |
| High | **nsjail kernel compatibility on Hetzner.** Hetzner bare metal images may have kernel configs that affect nsjail. | Provision and test nsjail in Phase 0, not Phase 2. Gate on this before building challenge infra. |
| Medium | **sqlx compile-time query failures after schema migrations.** Every migration requires recompiling `ctf-api`. | Offline mode for development (`SQLX_OFFLINE=true`), migration tests in CI. |
| Medium | **ClickHouse disk growth during long competitions.** High event volume can fill disk fast. | TTL policies on raw event tables (keep 90 days), pre-aggregated views for analytics. Alert at 70% disk. |
| Low | **deadpool-redis pool exhaustion under submission burst.** | Size the pool to 2x expected concurrent requests. Pool size tuned in Phase 4 load tests. |

---

## Confirmed Cuts (Not in v1 Scope)

- **Keycloak / enterprise SSO** - JVM overhead, 2GB+ RAM, complex to operate. GitHub + Google OAuth covers all players.
- **GraphQL API** - you own the frontend. REST is faster, simpler to cache, and produces less Rust boilerplate.
- **Multi-region deployments** - Cloudflare handles global latency for assets. Challenge containers are inherently single-region.
- **Firestore / NoSQL** - PostgreSQL + Redis is the complete data layer. No third data paradigm needed.
- **i18n support** - CTF is an English-dominant domain. Adds string management overhead with near-zero competitive value.
- **Feature flagging system** - env vars + admin UI toggles (score freeze, reg open/closed) cover all runtime config needs.

---

## Deferred to v2

AI/LLM challenge type - AI hint engine - Seed-based per-team binaries - gVisor / Firecracker sandbox upgrade - Full A/D scoring engine - Unlock chains / challenge prerequisites - Replay system (event sourcing UI) - XP economy + hint currency

**v2 readiness note:** The v1 data model and event log schema are designed to accommodate v2 features without breaking migrations. A/D scoreboard data model ships in v1 (no engine). Event sourcing schema ships in v1 (no replay UI). The upgrade path is additive, not rewrite.




