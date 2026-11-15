const std = @import("std");
const wl = @import("wayland").client.wl;
const river = @import("wayland").client.river;
const wm_mod = @import("wm.zig");

const Globals = struct {
    manager: ?*river.WindowManagerV1 = null,
    xkb: ?*river.XkbBindingsV1 = null,
    layer_shell: ?*river.LayerShellV1 = null,
};

pub fn main() !void {
    const display = try wl.Display.connect(null);
    defer display.disconnect();
    const registry = try display.getRegistry();

    var globals: Globals = .{};
    registry.setListener(*Globals, registryListener, &globals);
    if (display.roundtrip() != .SUCCESS) return error.RoundtripFailed;

    var wm = wm_mod.Wm.init(
        globals.manager orelse return error.RiverWindowManagementMissing,
        globals.xkb orelse return error.RiverXkbBindingsMissing,
        globals.layer_shell orelse return error.RiverLayerShellMissing,
        registry,
    );
    wm.listen();
    wm_mod.autostart();

    while (true) {
        if (display.dispatch() != .SUCCESS) return error.DispatchFailed;
    }
}

fn registryListener(registry: *wl.Registry, event: wl.Registry.Event, globals: *Globals) void {
    switch (event) {
        .global => |g| {
            if (std.mem.orderZ(u8, g.interface, river.WindowManagerV1.interface.name) == .eq) {
                globals.manager = registry.bind(g.name, river.WindowManagerV1, 6) catch return;
            } else if (std.mem.orderZ(u8, g.interface, river.XkbBindingsV1.interface.name) == .eq) {
                globals.xkb = registry.bind(g.name, river.XkbBindingsV1, 2) catch return;
            } else if (std.mem.orderZ(u8, g.interface, river.LayerShellV1.interface.name) == .eq) {
                globals.layer_shell = registry.bind(g.name, river.LayerShellV1, 1) catch return;
            }
        },
        .global_remove => {},
    }
}
