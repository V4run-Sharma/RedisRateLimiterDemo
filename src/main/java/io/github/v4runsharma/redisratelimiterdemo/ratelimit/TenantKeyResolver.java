package io.github.v4runsharma.redisratelimiterdemo.ratelimit;

import io.github.v4runsharma.ratelimiter.core.RateLimitContext;
import io.github.v4runsharma.ratelimiter.key.RateLimitKeyResolver;
import org.springframework.stereotype.Component;

/**
 * One bucket per tenant: the tenant ID is the first argument of the annotated method.
 */
@Component
public class TenantKeyResolver implements RateLimitKeyResolver {

  @Override
  public String resolveKey(RateLimitContext context) {
    String tenantId = String.valueOf(context.getArguments()[0]);
    return "tenant:" + tenantId + ":" + context.getMethod().getName();
  }
}
