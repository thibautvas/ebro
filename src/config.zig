const river = @import("wayland").client.river;

pub const workspace_count = 1;
pub const workspace_outputs = [workspace_count]?[]const u8{null};

pub const autostart = [_][:0]const u8{};

pub const LaunchOrFocus = struct {
    app_id: []const u8,
    cmd: [:0]const u8,
};

pub const Action = union(enum) {
    spawn: [:0]const u8,
    close: void,
    exit: void,
    launch_or_focus: LaunchOrFocus,
    focus_workspace: u8,
    move_to_workspace: u8,
    focus_next: void,
    swap_master: void,
    toggle_fullscreen: void,
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
