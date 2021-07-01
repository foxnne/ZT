const std = @import("std");
const math = @import("zlm/zlm.zig");

// @TODO: More settings to streamline spatial hash usage for other purposes. Maybe even 
// make it so you can provide your own coordinate type and functions?
pub const SpatialHashSettings = struct {
    /// The height and width of each bucket inside the hash.
    bucketSize: f32 = 256,
};

pub fn Generate(comptime T:type, comptime spatialSettings: SpatialHashSettings) type {
    return struct {
        const context = struct {
            pub fn hash(self:@This(),value:math.Vec2) u64 {
                _ = self;
                return std.hash.Wyhash.hash(438193475, &std.mem.toBytes(value));
            }
            pub fn eql(self:@This(),lhs:math.Vec2, rhs:math.Vec2) bool {
                _ = self;
                return lhs.x == rhs.x and lhs.y == rhs.y;
            }
        };
        const Self = @This();
        /// Some basic settings about the spatial hash, as given at type generation.
        pub const settings = spatialSettings;
        /// This is the inverse of the bucket size, the formula <floor(n*cellInverse)/cellInverse> will
        /// result in the 'hash' that locates the buckets in this spatial hash.
        pub const cellInverse: f32 = 1.0 / spatialSettings.bucketSize;
        /// A Bucket contains all the targets inside of an imaginary cell generated by the spatial hash.
        pub const Bucket = std.AutoArrayHashMap(T, void);
        /// The HashType defines what 
        pub const HashType = std.HashMap(math.Vec2,Bucket,context,80);

        allocator: *std.mem.Allocator,
        /// A HashMap of (Vec2 -> Bucket) to contain all the buckets as new ones appear.
        hashBins: HashType,
        /// This is a temporary holding bucket of every target inside of a query. This is used for each query
        /// and as such modifying the spatial hash, or starting a new query will change this bucket.
        holding: Bucket,

        /// Creates a spatial hash instance and allocates memory for the bucket structures.
        pub fn init(allocator: *std.mem.Allocator) Self {
            return .{
                .allocator = allocator,
                .hashBins = HashType.init(allocator),
                .holding = Bucket.init(allocator),
            };
        }
        /// Deallocates all the memory associated with this spatial hash. Note if T is not a pointer,
        /// then this will result in the loss of data.
        pub fn deinit(self:*Self) void {
            // for(self.hashBins.values()) |*val| {
            //     val.deinit();
            // }
            var iterator = self.hashBins.iterator();
            while(iterator.next()) |bin| {
                bin.value_ptr.deinit();
            }
            self.holding.deinit();
            self.hashBins.deinit();
        }

        // === ADDS ===

        /// Adds the target to the spatial hash, into every bucket that it spans.
        pub fn addAABB(self:*Self, target:T, position:math.Vec2, size:math.Vec2) void {
            var stop = position.add(size);
            var current = position;

            while(current.x < stop.x) : (current.x += settings.bucketSize) {
                while(current.y < stop.y) : (current.y += settings.bucketSize) {
                    var bin = self.getBin(current);
                    bin.put(target, {}) catch unreachable;
                }
            }
        }
        /// Adds the target to the spatial hash, into one single bucket.
        pub fn addPoint(self:*Self, target:T, position:math.Vec2) void {
            var result = self.getBin(position);
            result.put(target, {}) catch unreachable;
        }

        // === REMOVALS ===

        /// Removes the target from the spatial hash buckets that it spans. Make sure to provide
        /// the same coordinates that it was added with.
        pub fn removeAABB(self:*Self, target:T, position:math.Vec2, size:math.Vec2) void {
            var stop = position.add(size);
            var current = position;

            while(current.x <= stop.x) : (current.x += settings.bucketSize) {
                while(current.y <= stop.y) : (current.y += settings.bucketSize) {
                    var bin = self.getBin(current);
                    _ = bin.swapRemove(target);
                }
            }
        }
        /// Removes the target from the spatial hash's singular bucket. Make sure to provide
        /// the same coordinate that it was added with.
        pub fn removePoint(self:*Self, target:T, position:math.Vec2) void {
            var result = self.getBin(position);
            _ = result.swapRemove(target);
        }

        // === QUERIES ===

        /// Returns an array of each T inside of the given rectangle.
        /// Note that broad phase physics like this is not accurate, instead this opts to return in general
        /// what *could* be a possible collision.
        pub fn queryAABB(self:*Self, position:math.Vec2, size:math.Vec2) []T {
            self.holding.unmanaged.clearRetainingCapacity();
            var stop = position.add(size);
            var current = position;

            while(current.x <= stop.x) : (current.x += settings.bucketSize) {
                while(current.y <= stop.y) : (current.y += settings.bucketSize) {
                    var bin = self.getBin(current);
                    for(bin.keys()) |value| {
                        self.holding.put(value, {}) catch unreachable;
                    }
                }
                current.y = position.y;
            }
            return self.holding.keys();
        }
        /// Returns an array of each T inside of the given point's bucket.
        /// Note that broad phase physics like this is not accurate, instead this opts to return in general
        /// what *could* be a possible collision.
        pub fn queryPoint(self:*Self, point:math.Vec2) []T {
            self.holding.unmanaged.clearRetainingCapacity();
            var bin = self.getBin(point);
            for(bin.keys()) |value| {
                self.holding.put(value, {}) catch unreachable;
            }
            return self.holding.keys();
        }
        /// Returns an array of each T inside every bucket along this line's path.
        /// Note that broad phase physics like this is not accurate, instead this opts to return in general
        /// what *could* be a possible collision.
        /// TODO: This doesnt work on rtl casts, and straight vertical slopes. Also isnt accurate.... Generally just completely remake this
        pub fn queryLine(self:*Self, queryStart:math.Vec2, queryEnd:math.Vec2) []T {
            self.holding.unmanaged.clearRetainingCapacity();
            const start = queryStart.scale(cellInverse);
            const end = queryEnd.scale(cellInverse);

            var mNew: f32 = 2.0 * (end.y - start.y);
            var slopeErrorNew = mNew - (end.x - start.x);
            var current = start;

            while(current.x <= end.x) {
                // Append:
                var bin = self.getBin(current.scaleDiv(cellInverse)); // Expand into real coordinates for the bin.
                for(bin.keys()) |value| {
                    self.holding.put(value, {}) catch unreachable;
                } 

                // Advance:
                current.x += 1.0;
                slopeErrorNew += mNew;
                if(slopeErrorNew >= 0) {
                    current.y += 1.0; // Since everything is scaled by the cell inverse, we're working in basically integer scale.
                    slopeErrorNew -= 2 * (end.x - start.x);
                }
            }

            return self.holding.keys();
        }

        inline fn getBin(self:*Self, position:math.Vec2) *Bucket {
            var hash = vecToIndex(position);
            var result = self.hashBins.getOrPut(hash) catch unreachable;
            if(result.found_existing) {
                return result.value_ptr;
            } else {
                result.value_ptr.* = Bucket.init(self.allocator);
                return result.value_ptr;
            }
        }
        inline fn vecToIndex(vec:math.Vec2) math.Vec2 {
            return .{.x=floatToIndex(vec.x), .y=floatToIndex(vec.y)};
        }
        inline fn floatToIndex(float:f32) f32 {
            return (std.math.floor(float*cellInverse)) / cellInverse;
        }
    };
}


test "speed testing spatial hash" {
    std.debug.print("\n> Spatial hash Speedtest:\n", .{});

    var hash = Generate(usize, .{.bucketSize = 50}).init(std.heap.page_allocator);
    defer hash.deinit();

    var rand = std.rand.DefaultPrng.init(3741837483).random;
    var clock = std.time.Timer.start() catch unreachable;
    _ = clock.lap();
    var i: usize = 0;
    while(i < 10000) : (i += 1) {
        var randX = rand.float(f32) * 200;
        var randY = rand.float(f32) * 200;
        hash.addPoint(i, math.vec2(randX,randY));
    }
    var time = clock.lap();
    std.debug.print(">> Took {d:.2}ms to create 10,000 points on a hash of usize.\n", .{@intToFloat(f64,time) / 1000000.0});

    while(i < 20000) : (i += 1) {
        var randX = rand.float(f32) * 200;
        var randY = rand.float(f32) * 200;
        hash.addPoint(i, math.vec2(randX,randY));
    }
    time = clock.lap();
    std.debug.print(">> Took {d:.2}ms to create 10,000 more points on a hash of usize.\n", .{@intToFloat(f64,time) / 1000000.0});

    i = 0;
    var visited: i32 = 0;
    while(i < 200) : (i += 1) {
        for(hash.queryPoint(.{.x=rand.float(f32) * 200,.y=rand.float(f32) * 200})) |_| {
            visited += 1;
        }
    }
    time = clock.lap();
    std.debug.print(">> Took {d:.2}ms to point iterate over a bucket 200 times, and visited {any} items.\n", .{@intToFloat(f64,time) / 1000000.0, visited});
}

test "spatial point insertion/remove/query" {
    const assert = @import("std").debug.assert;

    var hash = Generate(i32, .{.bucketSize = 64}).init(std.testing.allocator);
    defer hash.deinit();

    hash.addPoint(40, .{.x=20,.y=20});
    hash.addPoint(80, .{.x=100,.y=100});

    {
        var data = hash.queryPoint(.{.x=10,.y=10});
        assert(data.len == 1);
        assert(data[0] == 40);
    }
    {
        hash.addPoint(100, .{.x=40,.y=40});
        var data = hash.queryPoint(.{.x=10,.y=10});
        assert(data[0] == 40);
        assert(data[1] == 100);
        assert(data.len == 2);
    }
    {
        hash.removePoint(100, .{.x=40,.y=40});
        var data = hash.queryPoint(.{.x=10,.y=10});
        assert(data[0] == 40);
        assert(data.len == 1);
    }
}

test "spatial rect insertion/remove/query" {
    const assert = @import("std").debug.assert;
    var hash = Generate(i32, .{.bucketSize = 100}).init(std.testing.allocator);
    defer hash.deinit();

    hash.addAABB(1, math.vec2(50,50), math.vec2(100,100));
    {
        var data = hash.queryAABB(math.vec2(0,0), math.vec2(150,150));
        assert(data.len == 1);
    }

    hash.addAABB(2, math.vec2(150,150), math.vec2(100,100));
    {
        var data = hash.queryAABB(math.vec2(0,0), math.vec2(100,100));
        assert(data.len == 2);
    }

    hash.removeAABB(2, math.vec2(150,150), math.vec2(100,100));
    {
        var data = hash.queryAABB(math.vec2(0,0), math.vec2(100,100));
        assert(data.len == 1);
    }
}
test "spatial line query" {
    const assert = @import("std").debug.assert;
    var hash = Generate(i32, .{.bucketSize = 100}).init(std.testing.allocator);
    defer hash.deinit();

    hash.addPoint(10, math.vec2(250,250));
    {
        var data = hash.queryLine(math.vec2(0,250), math.vec2(300,250));
        assert(data.len == 1);

        data = hash.queryLine(math.vec2(250,-50), math.vec2(250,200));
        assert(data.len == 1);
    }
}