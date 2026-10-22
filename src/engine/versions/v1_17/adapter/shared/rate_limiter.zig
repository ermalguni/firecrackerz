const wire = @import("../../models.zig");
const models = @import("../../../../models.zig");

pub fn encodeRateLimiter(limiter: ?models.RateLimiter) ?wire.RateLimiter {
    const value = limiter orelse return null;
    return .{
        .bandwidth = encodeTokenBucket(value.bandwidth),
        .ops = encodeTokenBucket(value.ops),
    };
}

pub fn encodeTokenBucket(bucket: ?models.TokenBucket) ?wire.TokenBucket {
    const value = bucket orelse return null;
    return .{
        .size = value.size,
        .refill_time = value.refill_time,
        .one_time_burst = value.one_time_burst,
    };
}
