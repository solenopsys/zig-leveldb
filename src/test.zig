const std = @import("std");
const testing = std.testing;
const leveldb = @import("leveldb.zig");
const fs = std.fs;

const test_dir = "test_leveldb";

fn setupTestDir() !void {
    fs.cwd().makeDir(test_dir) catch |err| {
        if (err != error.PathAlreadyExists) {
            return err;
        }
    };

    try fs.cwd().deleteTree(test_dir);
    try fs.cwd().makeDir(test_dir);
}

fn cleanupTestDir() void {
    fs.cwd().deleteTree(test_dir) catch {};
}

test "LevelDB basic operations" {
    try setupTestDir();
    defer cleanupTestDir();

    var db = try leveldb.DB.open(test_dir ++ "/basic", .{}, testing.allocator);
    defer db.close();

    try db.put("hello", "world", .{});

    const value = try db.get("hello", .{});
    try testing.expectEqualStrings("world", value.?);
    testing.allocator.free(value.?);

    const missing = try db.get("nonexistent", .{});
    try testing.expect(missing == null);

    try db.delete("hello", .{});
    const deleted = try db.get("hello", .{});
    try testing.expect(deleted == null);
}

test "LevelDB iterator" {
    try setupTestDir();
    defer cleanupTestDir();

    var db = try leveldb.DB.open(test_dir ++ "/iter", .{}, testing.allocator);
    defer db.close();

    const test_data = [_][2][]const u8{
        .{ "a", "1" },
        .{ "b", "2" },
        .{ "c", "3" },
        .{ "d", "4" },
        .{ "e", "5" },
    };

    for (test_data) |kv| {
        try db.put(kv[0], kv[1], .{});
    }

    var iter = db.iterator(.{});
    defer iter.destroy();

    iter.seekToFirst();
    var i: usize = 0;
    while (iter.isValid() and i < test_data.len) : (i += 1) {
        const k = try iter.key();
        defer testing.allocator.free(k);
        try testing.expectEqualStrings(test_data[i][0], k);

        const v = try iter.value();
        defer testing.allocator.free(v);
        try testing.expectEqualStrings(test_data[i][1], v);

        iter.next();
    }
    try testing.expectEqual(test_data.len, i);

    iter.seek("c");
    try testing.expect(iter.isValid());

    const k = try iter.key();
    defer testing.allocator.free(k);
    try testing.expectEqualStrings("c", k);

    const v = try iter.value();
    defer testing.allocator.free(v);
    try testing.expectEqualStrings("3", v);
}

test "LevelDB options" {
    try setupTestDir();
    defer cleanupTestDir();

    const custom_options = leveldb.Options{
        .create_if_missing = true,
        .error_if_exists = true,
        .write_buffer_size = 1024 * 1024,
        .block_size = 8 * 1024,
        .compression = false,
    };

    var db = try leveldb.DB.open(test_dir ++ "/options", custom_options, testing.allocator);
    db.close();

    const result = leveldb.DB.open(test_dir ++ "/options", custom_options, testing.allocator);
    try testing.expectError(error.InvalidArgument, result);

    const open_options = leveldb.Options{
        .create_if_missing = false,
        .error_if_exists = false,
    };

    var db2 = try leveldb.DB.open(test_dir ++ "/options", open_options, testing.allocator);
    defer db2.close();

    try db2.put("test", "value", .{});
    const value = try db2.get("test", .{});
    try testing.expectEqualStrings("value", value.?);
    testing.allocator.free(value.?);
}

test "LevelDB properties" {
    try setupTestDir();
    defer cleanupTestDir();

    var db = try leveldb.DB.open(test_dir ++ "/props", .{}, testing.allocator);
    defer db.close();

    for (0..100) |i| {
        const key = try std.fmt.allocPrint(testing.allocator, "key{d}", .{i});
        defer testing.allocator.free(key);
        const value = try std.fmt.allocPrint(testing.allocator, "value{d}", .{i});
        defer testing.allocator.free(value);

        try db.put(key, value, .{});
    }

    const stats = try db.property("leveldb.stats");
    if (stats) |s| {
        defer testing.allocator.free(s);

        try testing.expect(s.len > 0);
    }

    const num_files = try db.property("leveldb.num-files-at-level0");
    if (num_files) |n| {
        defer testing.allocator.free(n);

        const num = try std.fmt.parseInt(u64, n, 10);
        try testing.expect(num >= 0);
    }
}
