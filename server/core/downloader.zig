const std = @import("std");
const Io = std.Io;
const Mutex = Io.Mutex;
const net = Io.net;
const mem = std.mem;
const Allocator = mem.Allocator;

const web_socket = @import("web_socket.zig");

const yt_dlp = @import("yt-dlp/root.zig");

pub const DownloadTask = struct {
    connection: ?web_socket.Connection,
    what: What,

    const Self = @This();

    pub const What = union(enum) {
        yt: Yt,

        pub const Yt = struct {
            id: yt_dlp.ID,
            type: Type = .audio,

            pub const Type = enum { audio, video };
        };
    };

    pub fn copy(self: *const Self, io: Io, allocator: Allocator) error{OutOfMemory}!Self {
        return .{
            .connection = if (self.connection) |conn| conn.copy(io, allocator) else null,
            .what = self.what,
        };
    }

    pub fn deinit(self: *Self, allocator: Allocator) void {
        if (self.connection) |*connection| connection.deinit(allocator);
    }
};


// TODO: make this a Io.Queue wrapper
pub const DownloadQueue = struct {
    mutex: Mutex,
    items: []DownloadTask,
    capacity: usize,
    allocator: Allocator,

    const Self = @This();

    pub fn init(allocator: Allocator, buffer_size: usize) error{OutOfMemory}!Self {
        var items = try allocator.alloc(DownloadTask, buffer_size);
        items.len = 0;

        return .{
            .items = items,
            .capacity = buffer_size,
            .allocator = allocator,
            .mutex = .init,
        };
    }

    /// Will first try to get the lock before freeing.
    /// If `error.Canceled` is returned, nothing was freed.
    pub fn deinit(self: *Self, io: Io) error{Canceled}!void {
        try self.mutex.lock(io);
        defer self.mutex.unlock(io);
        self.deinitUnchecked();
    }

    pub fn deinitUnchecked(self: *Self) void {
        for (self.items) |*item| {
            item.deinit(self.allocator);
        }
        self.allocator.free(self.items);
    }

    /// Equivalent to first locking the mutex and then calling `putUnlocked`.
    pub fn put(self: *Self, io: Io, item: DownloadTask) error{NoSpace,Canceled,OutOfMemory}!void {
        try self.mutex.lock(io);
        defer self.mutex.unlock(io);
        self.putUnlocked(io, item);
    }

    /// The item is first copied.
    pub fn putUnlocked(self: *Self, io: Io, item: DownloadTask) error{NoSpace,OutOfMemory}!void {
        if (self.capacity == 0) return error.NoSpace;
        self.items.len += 1;
        self.items[self.items.len - 1] = try item.copy(io, self.allocator);
        self.capacity -= 1;
    }

    /// Equivalent to first locking the mutex and then calling `getUnlocked`.
    pub fn get(self: *Self, io: Io, index: usize) error{Canceled}!void {
        try self.mutex.lock(io);
        defer self.mutex.unlock(io);
        self.getUnlocked(index);
    }

    pub fn getUnlocked(self: *Self, index: usize) void {
        if (index >= self.items.len) return;
        self.items.len -= 1;
        mem.swap(DownloadTask, &self.items[index], &self.items[self.items.len]);
        self.capacity += 1;
    }
};

