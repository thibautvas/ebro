const ebro = @import("ebro");

pub const workspace_count = 1;
pub const workspace_outputs = [workspace_count]?[]const u8{null};

pub const autostart = [_][:0]const u8{};

pub const binds = [_]ebro.Bind{
    .{ .mods = .{ .mod4 = true }, .keysym = 'm', .action = .exit },
};
