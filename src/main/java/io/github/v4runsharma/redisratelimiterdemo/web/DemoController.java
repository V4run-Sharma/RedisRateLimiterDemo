package io.github.v4runsharma.redisratelimiterdemo.web;

import io.github.v4runsharma.ratelimiter.annotation.RateLimit;
import io.github.v4runsharma.ratelimiter.model.RateLimitScope;
import io.github.v4runsharma.redisratelimiterdemo.ratelimit.TenantKeyResolver;
import io.github.v4runsharma.redisratelimiterdemo.service.AsyncWorker;
import io.github.v4runsharma.redisratelimiterdemo.service.ReportService;
import jakarta.servlet.http.HttpServletRequest;
import java.security.Principal;
import java.util.concurrent.CompletionException;
import java.util.concurrent.TimeUnit;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RestController;

/**
 * One endpoint per rate-limit case. Limits are small so verify.sh can trip them quickly.
 */
@RestController
public class DemoController {

  private final ReportService reportService;
  private final AsyncWorker asyncWorker;

  public DemoController(ReportService reportService, AsyncWorker asyncWorker) {
    this.reportService = reportService;
    this.asyncWorker = asyncWorker;
  }

  // GLOBAL: one bucket shared by every caller.
  @GetMapping("/global")
  @RateLimit(name = "global", limit = 3, duration = 1, timeUnit = TimeUnit.MINUTES)
  public String global() {
    return "global ok";
  }

  // IP: one bucket per client IP; IPv6 addresses in the same /64 share a bucket.
  @GetMapping("/ip")
  @RateLimit(name = "per-ip", scope = RateLimitScope.IP, limit = 3, duration = 1, timeUnit = TimeUnit.MINUTES)
  public String ip(HttpServletRequest request) {
    return "ip ok: " + request.getRemoteAddr();
  }

  // USER: one bucket per authenticated user.
  @GetMapping("/me")
  @RateLimit(name = "per-user", scope = RateLimitScope.USER, limit = 2, duration = 1, timeUnit = TimeUnit.MINUTES)
  public String me(Principal principal) {
    return "hello " + principal.getName();
  }

  // USER on a public endpoint: anonymous callers get a 500 instead of an unlimited endpoint.
  @GetMapping("/public/me")
  @RateLimit(name = "per-user-public", scope = RateLimitScope.USER, limit = 2, duration = 1, timeUnit = TimeUnit.MINUTES)
  public String publicMe() {
    return "only reachable with a login";
  }

  // Stacked: both limits must pass, checked in order; the 429 names the one that tripped.
  @PostMapping("/orders")
  @RateLimit(name = "orders-per-ip", scope = RateLimitScope.IP, limit = 4, duration = 1, timeUnit = TimeUnit.MINUTES)
  @RateLimit(name = "orders-per-user", scope = RateLimitScope.USER, limit = 2, duration = 1, timeUnit = TimeUnit.MINUTES)
  public String createOrder(Principal principal) {
    return "order created for " + principal.getName();
  }

  // Custom key resolver: one bucket per tenant.
  @GetMapping("/tenants/{tenantId}/report")
  @RateLimit(name = "per-tenant", keyResolver = TenantKeyResolver.class, limit = 2, duration = 1, timeUnit = TimeUnit.MINUTES)
  public String tenantReport(@PathVariable String tenantId) {
    return "report for " + tenantId;
  }

  // Class-level limit on ReportService: daily and weekly have separate buckets.
  @GetMapping("/class/daily")
  public String daily() {
    return reportService.daily();
  }

  @GetMapping("/class/weekly")
  public String weekly() {
    return reportService.weekly();
  }

  // Object methods on a class-level-limited bean are not charged.
  @GetMapping("/class/to-string")
  public String classToString() {
    for (int i = 0; i < 10; i++) {
      reportService.toString();
    }
    return "toString ok";
  }

  // IP limit inside an @Async method: fails because the worker thread has no HTTP request.
  @GetMapping("/async")
  public ResponseEntity<String> async() {
    try {
      return ResponseEntity.ok(asyncWorker.work().join());
    } catch (CompletionException ex) {
      Throwable cause = ex.getCause() != null ? ex.getCause() : ex;
      return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR).body("async failed: " + cause.getMessage());
    }
  }

  // Compile-time check: uncomment this method and the build fails, since a String is not a RateLimitScope.
  // @GetMapping("/tenant-scope")
  // @RateLimit(scope = "TENANT", limit = 1, duration = 1)
  // public String tenantScope() {
  //   return "never compiles";
  // }
}
