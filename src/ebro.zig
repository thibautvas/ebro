const river = @import("wayland").client.river;

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
