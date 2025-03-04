const std = @import("std");
const leveldb = @import("leveldb.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer {
        const deinit_status = gpa.deinit();
        if (deinit_status == .leak) @panic("Memory leak detected!");
    }

    const stdout = std.io.getStdOut().writer();

    var db = try leveldb.DB.open("testdb", .{}, allocator);
    defer db.close();

    try db.put("key1", "Hello, LevelDB!", .{});
    try db.put("key2", "This is a Zig wrapper for LevelDB", .{});
    try db.put("key3", "ключ-значение на русском", .{});

    const value1 = try db.get("key1", .{});
    if (value1) |v| {
        try stdout.print("Value for key1: {s}\n", .{v});
        allocator.free(v);
    } else {
        try stdout.print("Key1 not found\n", .{});
    }

    try stdout.print("\nIterating through all keys:\n", .{});
    var iter = db.iterator(.{});
    defer iter.destroy();

    iter.seekToFirst();
    while (iter.isValid()) {
        const k = try iter.key();
        defer allocator.free(k);

        const v = try iter.value();
        defer allocator.free(v);

        try stdout.print("  {s}: {s}\n", .{ k, v });
        iter.next();
    }

    try db.delete("key2", .{});

    const value2 = try db.get("key2", .{});
    if (value2) |v| {
        try stdout.print("\nValue for key2 after deletion: {s}\n", .{v});
        allocator.free(v);
    } else {
        try stdout.print("\nKey2 was successfully deleted\n", .{});
    }

    if (try db.property("leveldb.stats")) |stats| {
        defer allocator.free(stats);
        try stdout.print("\nDatabase Stats:\n{s}\n", .{stats});
    }

    try stdout.print("\nLevelDB operations completed successfully!\n", .{});
}
