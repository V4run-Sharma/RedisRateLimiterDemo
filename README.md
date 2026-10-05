# Redis RateLimiter Demo

Exercises every case of [`spring-boot-starter-redis-ratelimiter`](https://central.sonatype.com/artifact/io.github.v4run-sharma/spring-boot-starter-redis-ratelimiter) 2.1.0 on Spring Boot 3.5.

## Run

Requires Java 21 and Docker. Redis starts automatically from `compose.yaml` (Spring Boot Docker Compose support).

```bash
./mvnw -s ~/.m2/settings-central.xml spring-boot:run
```

`-s ~/.m2/settings-central.xml` resolves dependencies straight from Maven Central; drop it if your default Maven settings can reach Central.

In another terminal:

```bash
./verify.sh
```

The script flushes Redis, checks each case below, and exits non-zero if any check fails. Users are `alice` and `bob` (password `password`, see `SecurityConfig`).

## Cases

| Case | Endpoint | Limit | Expected |
|---|---|---|---|
| GLOBAL | `GET /global` | 3/min | 4th call is 429 with `Retry-After` |
| Class-level | `GET /class/daily`, `/class/weekly` | 2/min per method | Separate buckets; `toString()` not limited |
| IP | `GET /ip` | 3/min per IP | Different `X-Forwarded-For` values get separate buckets; IPv6 grouped by /64 |
| USER | `GET /me` (login) | 2/min per user | alice and bob have separate buckets |
| USER, no login | `GET /public/me` | — | 500, not an unlimited endpoint |
| Stacked | `POST /orders` (login) | 4/min per IP + 2/min per user | 429 names the limit that tripped |
| Custom resolver | `GET /tenants/{id}/report` | 2/min per tenant | Separate bucket per tenant |
| `@Async` | `GET /async` | IP scope | 500: no HTTP request on the worker thread |
| Metrics | `/actuator/metrics/ratelimiter.requests` | — | Allowed/blocked counts recorded |
| Redis outage | any limited endpoint | — | 500 while Redis is paused (fail-closed) |

`server.forward-headers-strategy=native` makes localhost a trusted proxy, which is how `verify.sh` simulates different client IPs.

## Running on Spring Boot 4

Starter 2.1.0 also supports Spring Boot 4; `verify.sh` passes on 4.1.1 with three changes:

1. Parent version `4.1.1`.
2. `spring-boot-starter-webmvc` instead of `spring-boot-starter-web`.
3. `spring.web.error.include-message=always` instead of `server.error.include-message=always` (renamed in Boot 4).

## Manual checks

- **Fail-open:** start with `--ratelimiter.fail-open=true` (`./mvnw -s ~/.m2/settings-central.xml spring-boot:run -Dspring-boot.run.arguments=--ratelimiter.fail-open=true`), then `docker compose pause redis`: limited endpoints keep returning 200. Run `docker compose unpause redis` afterwards.
- **Compile-time scope check:** uncomment the `tenantScope` method at the bottom of `DemoController`; the build fails with `incompatible types: String cannot be converted to RateLimitScope`.
