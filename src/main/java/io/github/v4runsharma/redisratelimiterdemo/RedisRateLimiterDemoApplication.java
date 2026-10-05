package io.github.v4runsharma.redisratelimiterdemo;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.scheduling.annotation.EnableAsync;

@SpringBootApplication
@EnableAsync
public class RedisRateLimiterDemoApplication {

  public static void main(String[] args) {
    SpringApplication.run(RedisRateLimiterDemoApplication.class, args);
  }

}
