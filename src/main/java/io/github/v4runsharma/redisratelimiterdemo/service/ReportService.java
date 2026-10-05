package io.github.v4runsharma.redisratelimiterdemo.service;

import io.github.v4runsharma.ratelimiter.annotation.RateLimit;
import java.util.concurrent.TimeUnit;
import org.springframework.stereotype.Service;

/**
 * Class-level limit: applies to every public method, each with its own bucket.
 * toString/equals/hashCode are not limited.
 */
@Service
@RateLimit(name = "reports", limit = 2, duration = 1, timeUnit = TimeUnit.MINUTES)
public class ReportService {

  public String daily() {
    return "daily report";
  }

  public String weekly() {
    return "weekly report";
  }
}
