const std = @import("std");
const c = @cImport({
    @cInclude("leveldb/c.h");
});

pub const LevelDBError = error{
    NotFound,
    Corruption,
    NotSupported,
    InvalidArgument,
    IOError,
    Unknown,
};

pub const Options = struct {
    create_if_missing: bool = true,
    error_if_exists: bool = false,
    paranoid_checks: bool = false,
    write_buffer_size: usize = 4 * 1024 * 1024,
    max_open_files: c_int = 1000,
    block_size: usize = 4 * 1024,
    block_restart_interval: c_int = 16,
    compression: bool = true,

    fn toCOptions(self: Options) *c.leveldb_options_t {
        const options = c.leveldb_options_create();

        c.leveldb_options_set_create_if_missing(options, if (self.create_if_missing) 1 else 0);
        c.leveldb_options_set_error_if_exists(options, if (self.error_if_exists) 1 else 0);
        c.leveldb_options_set_paranoid_checks(options, if (self.paranoid_checks) 1 else 0);
        c.leveldb_options_set_write_buffer_size(options, self.write_buffer_size);
        c.leveldb_options_set_max_open_files(options, self.max_open_files);
        c.leveldb_options_set_block_size(options, self.block_size);
        c.leveldb_options_set_block_restart_interval(options, self.block_restart_interval);
        c.leveldb_options_set_compression(options, if (self.compression) c.leveldb_snappy_compression else c.leveldb_no_compression);
        return options orelse unreachable;
    }
};

pub const WriteOptions = struct {
    sync: bool = false,

    fn toCOptions(self: WriteOptions) *c.leveldb_writeoptions_t {
        const options = c.leveldb_writeoptions_create();
        c.leveldb_writeoptions_set_sync(options, if (self.sync) 1 else 0);
        return options orelse unreachable;
    }
};

pub const ReadOptions = struct {
    verify_checksums: bool = false,
    fill_cache: bool = true,

    fn toCOptions(self: ReadOptions) *c.leveldb_readoptions_t {
        const options = c.leveldb_readoptions_create();
        c.leveldb_readoptions_set_verify_checksums(options, if (self.verify_checksums) 1 else 0);
        c.leveldb_readoptions_set_fill_cache(options, if (self.fill_cache) 1 else 0);
        return options orelse unreachable;
    }
};

pub const DB = struct {
    db: *c.leveldb_t,
    allocator: std.mem.Allocator,

    pub fn open(path: []const u8, options: Options, allocator: std.mem.Allocator) !DB {
        const c_options = options.toCOptions();
        defer c.leveldb_options_destroy(c_options);

        const c_path = try allocator.dupeZ(u8, path);
        defer allocator.free(c_path);

        var err: [*c]u8 = null;

        const db = c.leveldb_open(c_options, c_path.ptr, &err);

        if (err) |errmsg| {
            defer c.leveldb_free(errmsg);
            return mapError(errmsg);
        }

        return DB{
            .db = db.?,
            .allocator = allocator,
        };
    }

    pub fn close(self: *DB) void {
        c.leveldb_close(self.db);
    }

    pub fn put(self: *DB, key: []const u8, value: []const u8, options: WriteOptions) !void {
        const c_options = options.toCOptions();
        defer c.leveldb_writeoptions_destroy(c_options);

        var err: [*c]u8 = null;
        c.leveldb_put(
            self.db,
            c_options,
            key.ptr,
            key.len,
            value.ptr,
            value.len,
            &err,
        );

        if (err) |errmsg| {
            defer c.leveldb_free(errmsg);
            return mapError(errmsg);
        }
    }

    pub fn get(self: *DB, key: []const u8, options: ReadOptions) !?[]u8 {
        const c_options = options.toCOptions();
        defer c.leveldb_readoptions_destroy(c_options);

        var value_len: usize = undefined;
        var err: [*c]u8 = null;
        const value = c.leveldb_get(
            self.db,
            c_options,
            key.ptr,
            key.len,
            &value_len,
            &err,
        );
        if (err) |errmsg| {
            defer c.leveldb_free(errmsg);
            return mapError(errmsg);
        }

        if (value == null) {
            return null;
        }

        const result = try self.allocator.alloc(u8, value_len);
        @memcpy(result, value[0..value_len]);
        c.leveldb_free(value);

        return result;
    }

    pub fn delete(self: *DB, key: []const u8, options: WriteOptions) !void {
        const c_options = options.toCOptions();
        defer c.leveldb_writeoptions_destroy(c_options);

        var err: [*c]u8 = null;
        c.leveldb_delete(
            self.db,
            c_options,
            key.ptr,
            key.len,
            &err,
        );

        if (err) |errmsg| {
            defer c.leveldb_free(errmsg);
            return mapError(errmsg);
        }
    }

    pub fn iterator(self: *DB, options: ReadOptions) Iterator {
        const c_options = options.toCOptions();
        defer c.leveldb_readoptions_destroy(c_options);

        const iter = c.leveldb_create_iterator(self.db, c_options);
        return Iterator{
            .iter = iter.?,
            .allocator = self.allocator,
            .valid = false,
        };
    }

    pub fn approximateSize(self: *DB, start: []const u8, limit: []const u8) u64 {
        const range = c.leveldb_approximate_sizes(
            self.db,
            1,
            &start.ptr,
            &start.len,
            &limit.ptr,
            &limit.len,
        );
        return range;
    }

    pub fn compactRange(self: *DB, start: ?[]const u8, limit: ?[]const u8) void {
        const start_ptr = if (start) |s| s.ptr else null;
        const start_len = if (start) |s| s.len else 0;
        const limit_ptr = if (limit) |l| l.ptr else null;
        const limit_len = if (limit) |l| l.len else 0;

        c.leveldb_compact_range(
            self.db,
            start_ptr,
            start_len,
            limit_ptr,
            limit_len,
        );
    }

    pub fn property(self: *DB, p: []const u8) !?[]u8 {
        const prop = try self.allocator.dupeZ(u8, p);
        defer self.allocator.free(prop);

        const value = c.leveldb_property_value(self.db, prop.ptr);
        if (value == null) {
            return null;
        }

        const result = try self.allocator.dupe(u8, std.mem.span(value));
        c.leveldb_free(value);

        return result;
    }
};

pub const Iterator = struct {
    iter: *c.leveldb_iterator_t,
    allocator: std.mem.Allocator,
    valid: bool,

    pub fn seekToFirst(self: *Iterator) void {
        c.leveldb_iter_seek_to_first(self.iter);
        self.valid = c.leveldb_iter_valid(self.iter) != 0;
    }

    pub fn seekToLast(self: *Iterator) void {
        c.leveldb_iter_seek_to_last(self.iter);
        self.valid = c.leveldb_iter_valid(self.iter) != 0;
    }

    pub fn seek(self: *Iterator, target: []const u8) void {
        c.leveldb_iter_seek(self.iter, target.ptr, target.len);
        self.valid = c.leveldb_iter_valid(self.iter) != 0;
    }

    pub fn next(self: *Iterator) void {
        c.leveldb_iter_next(self.iter);
        self.valid = c.leveldb_iter_valid(self.iter) != 0;
    }

    pub fn prev(self: *Iterator) void {
        c.leveldb_iter_prev(self.iter);
        self.valid = c.leveldb_iter_valid(self.iter) != 0;
    }

    pub fn key(self: *Iterator) ![]u8 {
        if (!self.valid) {
            return error.InvalidIterator;
        }

        var key_len: usize = undefined;
        const key_ptr = c.leveldb_iter_key(self.iter, &key_len);
        const result = try self.allocator.alloc(u8, key_len);
        @memcpy(result, key_ptr[0..key_len]);

        return result;
    }

    pub fn value(self: *Iterator) ![]u8 {
        if (!self.valid) {
            return error.InvalidIterator;
        }

        var value_len: usize = undefined;
        const value_ptr = c.leveldb_iter_value(self.iter, &value_len);
        const result = try self.allocator.alloc(u8, value_len);
        @memcpy(result, value_ptr[0..value_len]);

        return result;
    }

    pub fn isValid(self: *Iterator) bool {
        return self.valid;
    }

    pub fn destroy(self: *Iterator) void {
        c.leveldb_iter_destroy(self.iter);
    }
};

fn mapError(err: [*c]u8) LevelDBError {
    const err_str = std.mem.span(err);
    if (std.mem.indexOf(u8, err_str, "not found") != null) {
        return LevelDBError.NotFound;
    } else if (std.mem.indexOf(u8, err_str, "corruption") != null) {
        return LevelDBError.Corruption;
    } else if (std.mem.indexOf(u8, err_str, "not implemented") != null) {
        return LevelDBError.NotSupported;
    } else if (std.mem.indexOf(u8, err_str, "Invalid argument") != null) {
        return LevelDBError.InvalidArgument;
    } else if (std.mem.indexOf(u8, err_str, "IO error") != null) {
        return LevelDBError.IOError;
    } else {
        return LevelDBError.Unknown;
    }
}
