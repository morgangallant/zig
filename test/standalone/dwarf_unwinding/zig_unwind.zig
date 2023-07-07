const std = @import("std");
const debug = std.debug;
const testing = std.testing;

noinline fn frame3(expected: *[4]usize, unwound: *[4]usize) void {
    expected[0] = @returnAddress();

    var context: debug.ThreadContext = undefined;
    testing.expect(debug.getContext(&context)) catch @panic("failed to getContext");

    var debug_info = debug.getSelfDebugInfo() catch @panic("failed to openSelfDebugInfo");
    var it = debug.StackIterator.initWithContext(expected[0], debug_info, &context) catch @panic("failed to initWithContext");
    defer it.deinit();

    for (unwound) |*addr| {
        if (it.next()) |return_address| addr.* = return_address;
    }
}

noinline fn frame2(expected: *[4]usize, unwound: *[4]usize) void {
    expected[1] = @returnAddress();
    frame3(expected, unwound);
}

noinline fn frame1(expected: *[4]usize, unwound: *[4]usize) void {
    expected[2] = @returnAddress();
    frame2(expected, unwound);
}

noinline fn frame0(expected: *[4]usize, unwound: *[4]usize) void {
    expected[3] = @returnAddress();
    frame1(expected, unwound);
}

pub fn main() !void {
    if (!std.debug.have_ucontext or !std.debug.have_getcontext) return;

    var expected: [4]usize = undefined;
    var unwound: [4]usize = undefined;
    frame0(&expected, &unwound);
    try testing.expectEqual(expected, unwound);
}
