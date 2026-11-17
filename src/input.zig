const std = @import("std");
const river = @import("wayland").client.river;
const ebro = @import("ebro");
const config = @import("config");

const gpa = std.heap.c_allocator;

const keyboard: ?ebro.Keyboard = if (@hasDecl(config, "keyboard")) config.keyboard else null;

pub fn init(manager: ?*river.InputManagerV1) void {
    if (keyboard == null) return;
    const m = manager orelse {
        std.log.warn("river_input_manager_v1 missing: keyboard repeat not applied", .{});
        return;
    };
    m.setListener(?*anyopaque, managerListener, null);
}

fn managerListener(_: *river.InputManagerV1, event: river.InputManagerV1.Event, _: ?*anyopaque) void {
    switch (event) {
        .input_device => |e| {
            const dev = gpa.create(Device) catch @panic("OOM");
            dev.* = .{};
            e.id.setListener(*Device, deviceListener, dev);
        },
        .finished => {},
    }
}

const Device = struct { keyboard: bool = false };

fn deviceListener(proxy: *river.InputDeviceV1, event: river.InputDeviceV1.Event, dev: *Device) void {
    switch (event) {
        .type => |e| dev.keyboard = e.type == .keyboard,
        .done => if (dev.keyboard) {
            const kb = keyboard.?;
            proxy.setRepeatInfo(kb.repeat_rate, kb.repeat_delay);
        },
        .removed => {
            proxy.destroy();
            gpa.destroy(dev);
        },
        .name => {},
    }
}
