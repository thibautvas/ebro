const river = @import("wayland").client.river;

pub const workspace_count = 1;
pub const workspace_outputs = [workspace_count]?[]const u8{null};

pub const autostart = [_][:0]const u8{};

pub const Action = union(enum) {
    spawn: [:0]const u8,
    exit: void,
};

pub const Bind = struct {
    mods: river.SeatV1.Modifiers,
    keysym: u32,
    action: Action,
    locked: bool = false,
};

pub const binds = [_]Bind{
    .{ .mods = .{ .mod4 = true }, .keysym = 'm', .action = .exit },
};
