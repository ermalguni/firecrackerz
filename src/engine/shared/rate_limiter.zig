pub const RateLimiter = struct {
    bandwidth: ?TokenBucket = null,
    ops: ?TokenBucket = null,
};

pub const TokenBucket = struct {
    size: i64,
    refill_time: i64,
    one_time_burst: ?i64 = null,
};
