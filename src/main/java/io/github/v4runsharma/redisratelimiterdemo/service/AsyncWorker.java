package io.github.v4runsharma.redisratelimiterdemo.service;

import io.github.v4runsharma.ratelimiter.annotation.RateLimit;
import io.github.v4runsharma.ratelimiter.model.RateLimitScope;
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.TimeUnit;
import org.springframework.scheduling.annotation.Async;
import org.springframework.stereotype.Service;

/**
 * IP limit on an @Async method: the worker thread has no HTTP request, so the limit fails
 * instead of being silently skipped.
 */
@Service
public class AsyncWorker {

  @Async
  @RateLimit(name = "async-per-ip", scope = RateLimitScope.IP, limit = 5, duration = 1, timeUnit = TimeUnit.MINUTES)
  public CompletableFuture<String> work() {
    return CompletableFuture.completedFuture("async ok");
  }
}
