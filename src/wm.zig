const std = @import("std");
const wl = @import("wayland").client.wl;
const river = @import("wayland").client.river;
const config = @import("config.zig");
const layout = @import("layout.zig");

const gpa = std.heap.c_allocator;

const Window = struct {
    wm: *Wm,
    proxy: *river.WindowV1,
    node: *river.NodeV1,
    rect: layout.Rect = .{ .x = 0, .y = 0, .w = 0, .h = 0 },
    app_id: ?[]const u8 = null,
    workspace: u8,
    visible: bool = false,
    decorate: bool = true,
};

const Output = struct {
    wm: *Wm,
    proxy: *river.OutputV1,
    layer: *river.LayerShellOutputV1,
    area: layout.Rect = .{ .x = 0, .y = 0, .w = 0, .h = 0 },
    usable: ?layout.Rect = null,
    wl_output: ?*wl.Output = null,
    name: ?[]const u8 = null,
    active: u8 = 0,
};

extern "c" fn system(command: [*:0]const u8) c_int;

fn spawn(command: [:0]const u8) void {
    var buf: [1024]u8 = undefined;
    const line = std.fmt.bufPrint(&buf, "{s} &\x00", .{command}) catch {
        std.log.err("command too long to spawn: {s}", .{command});
        return;
    };
    std.log.info("spawn: {s}", .{command});
    _ = system(@ptrCast(line.ptr));
}

pub fn autostart() void {
    for (config.autostart) |cmd| spawn(cmd);
}

const Binding = struct {
    wm: *Wm,
    proxy: *river.XkbBindingV1,
    action: config.Action,
    locked: bool,
    enabled: bool = false,
};

pub const Wm = struct {
    proxy: *river.WindowManagerV1,
    xkb: *river.XkbBindingsV1,
    layer_shell: *river.LayerShellV1,
    registry: *wl.Registry,
    bindings: std.ArrayList(*Binding) = .empty,
    windows: std.ArrayList(*Window) = .empty,
    outputs: std.ArrayList(*Output) = .empty,
    seat: ?*river.SeatV1 = null,
    focused: ?*Window = null,
    focus_dirty: bool = false,
    workspace: u8 = 1,
    last_focused: [config.workspace_count]?*Window = @splat(null),
    default_output: ?*Output = null,
    pending: ?config.Action = null,
    locked: bool = false,

    pub fn init(
        proxy: *river.WindowManagerV1,
        xkb: *river.XkbBindingsV1,
        layer_shell: *river.LayerShellV1,
        registry: *wl.Registry,
    ) Wm {
        return .{ .proxy = proxy, .xkb = xkb, .layer_shell = layer_shell, .registry = registry };
    }

    fn layerSeatListener(_: *river.LayerShellSeatV1, event: river.LayerShellSeatV1.Event, wm: *Wm) void {
        switch (event) {
            .focus_none => wm.focus_dirty = true,
            .focus_exclusive, .focus_non_exclusive => {},
        }
    }

    fn addBindings(wm: *Wm, seat: *river.SeatV1) void {
        for (config.binds) |bind| {
            const b = gpa.create(Binding) catch @panic("OOM");
            b.* = .{
                .wm = wm,
                .proxy = wm.xkb.getXkbBinding(seat, bind.keysym, bind.mods) catch @panic("OOM"),
                .action = bind.action,
                .locked = bind.locked,
            };
            wm.bindings.append(gpa, b) catch @panic("OOM");
            b.proxy.setListener(*Binding, bindingListener, b);
        }
    }

    fn bindingListener(_: *river.XkbBindingV1, event: river.XkbBindingV1.Event, b: *Binding) void {
        switch (event) {
            .pressed => {
                if (b.wm.locked and !b.locked) return;
                b.wm.pending = b.action;
            },
            else => {},
        }
    }

    pub fn listen(wm: *Wm) void {
        wm.proxy.setListener(*Wm, managerListener, wm);
    }

    fn managerListener(_: *river.WindowManagerV1, event: river.WindowManagerV1.Event, wm: *Wm) void {
        switch (event) {
            .unavailable => {
                std.log.err("window management unavailable: another window manager is already running", .{});
                std.process.exit(1);
            },
            .finished => std.process.exit(0),
            .window => |e| wm.addWindow(e.id),
            .output => |e| wm.addOutput(e.id),
            .seat => |e| {
                if (wm.seat == null) {
                    wm.seat = e.id;
                    wm.addBindings(e.id);
                    e.id.setListener(*Wm, seatListener, wm);
                    const layer_seat = wm.layer_shell.getSeat(e.id) catch @panic("OOM");
                    layer_seat.setListener(*Wm, layerSeatListener, wm);
                }
            },
            .manage_start => wm.manage(),
            .render_start => wm.render(),
            .session_locked => wm.locked = true,
            .session_unlocked => wm.locked = false,
        }
    }

    fn seatListener(_: *river.SeatV1, event: river.SeatV1.Event, wm: *Wm) void {
        switch (event) {
            .window_interaction => |e| {
                const proxy = e.window orelse return;
                const win = wm.windowFrom(proxy) orelse return;
                wm.focus(win);
            },
            else => {},
        }
    }

    fn windowFrom(wm: *Wm, proxy: *river.WindowV1) ?*Window {
        for (wm.windows.items) |win| {
            if (win.proxy == proxy) return win;
        }
        return null;
    }

    fn focus(wm: *Wm, win: *Window) void {
        wm.focused = win;
        wm.focus_dirty = true;
        wm.workspace = win.workspace;
        wm.last_focused[win.workspace - 1] = win;
    }

    fn nearest(wm: *Wm, ws: u8, idx: usize) ?*Window {
        const items = wm.windows.items;
        var i = @min(idx, items.len);
        while (i > 0) {
            i -= 1;
            if (items[i].workspace == ws) return items[i];
        }
        for (items) |win| {
            if (win.workspace == ws) return win;
        }
        return null;
    }

    fn forget(wm: *Wm, win: *Window, ws: u8, idx: usize) void {
        if (wm.last_focused[ws - 1] == win) wm.last_focused[ws - 1] = wm.nearest(ws, idx);
    }

    fn addWindow(wm: *Wm, proxy: *river.WindowV1) void {
        const win = gpa.create(Window) catch @panic("OOM");
        win.* = .{
            .wm = wm,
            .proxy = proxy,
            .node = proxy.getNode() catch @panic("OOM"),
            .workspace = wm.workspace,
        };
        wm.windows.append(gpa, win) catch @panic("OOM");
        proxy.setListener(*Window, windowListener, win);
        wm.focus(win);
    }

    fn windowListener(_: *river.WindowV1, event: river.WindowV1.Event, win: *Window) void {
        switch (event) {
            .closed => win.wm.removeWindow(win),
            .decoration_hint => win.decorate = true,
            .app_id => |e| {
                if (win.app_id) |old| gpa.free(old);
                win.app_id = if (e.app_id) |id|
                    gpa.dupe(u8, std.mem.span(id)) catch @panic("OOM")
                else
                    null;
            },
            else => {},
        }
    }

    fn removeWindow(wm: *Wm, win: *Window) void {
        const idx = std.mem.indexOfScalar(*Window, wm.windows.items, win).?;
        _ = wm.windows.orderedRemove(idx);
        wm.forget(win, win.workspace, idx);
        if (wm.focused == win) {
            wm.focused = wm.last_focused[win.workspace - 1];
            wm.focus_dirty = true;
        }
        if (win.app_id) |id| gpa.free(id);
        win.node.destroy();
        win.proxy.destroy();
        gpa.destroy(win);
    }

    fn addOutput(wm: *Wm, proxy: *river.OutputV1) void {
        const out = gpa.create(Output) catch @panic("OOM");
        out.* = .{ .wm = wm, .proxy = proxy, .layer = wm.layer_shell.getOutput(proxy) catch @panic("OOM") };
        wm.outputs.append(gpa, out) catch @panic("OOM");
        proxy.setListener(*Output, outputListener, out);
        out.layer.setListener(*Output, layerOutputListener, out);
    }

    fn layerOutputListener(_: *river.LayerShellOutputV1, event: river.LayerShellOutputV1.Event, out: *Output) void {
        switch (event) {
            .non_exclusive_area => |e| out.usable = .{ .x = e.x, .y = e.y, .w = e.width, .h = e.height },
        }
    }

    fn outputListener(_: *river.OutputV1, event: river.OutputV1.Event, out: *Output) void {
        switch (event) {
            .position => |e| {
                out.area.x = e.x;
                out.area.y = e.y;
            },
            .dimensions => |e| {
                out.area.w = e.width;
                out.area.h = e.height;
            },
            .wl_output => |e| {
                const wo = out.wm.registry.bind(e.name, wl.Output, 4) catch @panic("OOM");
                wo.setListener(*Output, wlOutputListener, out);
                out.wl_output = wo;
            },
            .removed => out.wm.removeOutput(out),
            else => {},
        }
    }

    fn wlOutputListener(_: *wl.Output, event: wl.Output.Event, out: *Output) void {
        switch (event) {
            .name => |e| {
                if (out.name) |old| gpa.free(old);
                out.name = gpa.dupe(u8, std.mem.span(e.name)) catch @panic("OOM");
                out.wm.proxy.manageDirty();
            },
            else => {},
        }
    }

    fn removeOutput(wm: *Wm, out: *Output) void {
        const idx = std.mem.indexOfScalar(*Output, wm.outputs.items, out).?;
        _ = wm.outputs.orderedRemove(idx);
        if (wm.default_output == out) wm.default_output = null;
        if (out.name) |name| gpa.free(name);
        if (out.wl_output) |wo| wo.release();
        out.layer.destroy();
        out.proxy.destroy();
        gpa.destroy(out);
    }

    fn outputFor(wm: *Wm, ws: u8) ?*Output {
        const want = config.workspace_outputs[ws - 1] orelse return wm.firstOutput();
        for (wm.outputs.items) |out| {
            const name = out.name orelse continue;
            if (std.mem.eql(u8, name, want)) return out;
        }
        return wm.firstOutput();
    }

    fn firstOutput(wm: *Wm) ?*Output {
        return if (wm.outputs.items.len > 0) wm.outputs.items[0] else null;
    }

    fn assignWorkspaces(wm: *Wm) void {
        for (wm.outputs.items) |out| {
            if (out.active != 0 and wm.outputFor(out.active) == out) continue;
            out.active = 0;
            for (1..config.workspace_count + 1) |i| {
                const ws: u8 = @intCast(i);
                if (wm.outputFor(ws) == out) {
                    out.active = ws;
                    break;
                }
            }
        }
        if (wm.outputFor(wm.workspace)) |out| out.active = wm.workspace;
    }

    fn apply(wm: *Wm, action: config.Action) void {
        switch (action) {
            .spawn => |cmd| spawn(cmd),
            .close => if (wm.focused) |win| win.proxy.close(),
            .exit => wm.proxy.exitSession(),
            .launch_or_focus => |lf| wm.launchOrFocus(lf),
            .focus_workspace => |ws| wm.focusWorkspace(ws),
            .move_to_workspace => |ws| wm.moveToWorkspace(ws),
            .focus_next => wm.focusNext(),
            .swap_master => wm.swapMaster(),
            .toggle_fullscreen => wm.toggleFullscreen(),
        }
    }

    fn launchOrFocus(wm: *Wm, lf: config.LaunchOrFocus) void {
        for (wm.windows.items) |win| {
            const id = win.app_id orelse continue;
            if (std.mem.eql(u8, id, lf.app_id)) {
                wm.focus(win);
                return;
            }
        }
        spawn(lf.cmd);
    }

    fn focusWorkspace(wm: *Wm, ws: u8) void {
        if (ws == 0 or ws > config.workspace_count) return;
        wm.workspace = ws;
        wm.focused = wm.last_focused[ws - 1] orelse wm.nearest(ws, 0);
        wm.focus_dirty = true;
    }

    fn moveToWorkspace(wm: *Wm, ws: u8) void {
        if (ws == 0 or ws > config.workspace_count) return;
        const win = wm.focused orelse return;
        if (win.workspace == ws) return;
        const old = win.workspace;
        win.workspace = ws;
        wm.forget(win, old, std.mem.indexOfScalar(*Window, wm.windows.items, win).?);
        wm.focus(win);
    }

    fn focusNext(wm: *Wm) void {
        const items = wm.windows.items;
        const start = if (wm.focused) |f| std.mem.indexOfScalar(*Window, items, f).? + 1 else 0;
        for (0..items.len) |k| {
            const win = items[(start + k) % items.len];
            if (win.workspace == wm.workspace) return wm.focus(win);
        }
    }

    fn swapMaster(wm: *Wm) void {
        const win = wm.focused orelse return;
        const items = wm.windows.items;
        const i = std.mem.indexOfScalar(*Window, items, win).?;
        for (items, 0..) |other, j| {
            if (j == i or other.workspace != win.workspace) continue;
            std.mem.swap(*Window, &items[i], &items[j]);
            return;
        }
    }

    fn toggleFullscreen(wm: *Wm) void {
        const win = wm.focused orelse return;
        if (win.fullscreen) {
            win.proxy.exitFullscreen();
            win.proxy.informNotFullscreen();
            win.fullscreen = false;
        } else {
            const out = wm.outputFor(win.workspace) orelse return;
            win.proxy.fullscreen(out.proxy);
            win.proxy.informFullscreen();
            win.fullscreen = true;
        }
    }

    fn manage(wm: *Wm) void {
        defer wm.proxy.manageFinish();
        for (wm.bindings.items) |b| {
            if (!b.enabled) {
                b.proxy.enable();
                b.enabled = true;
            }
        }
        if (wm.pending) |action| {
            wm.pending = null;
            wm.apply(action);
        }

        if (wm.outputs.items.len == 0) return;
        wm.assignWorkspaces();

        if (wm.outputFor(wm.workspace)) |out| {
            if (wm.default_output != out) {
                out.layer.setDefault();
                wm.default_output = out;
            }
        }

        const n = wm.windows.items.len;
        const wins = gpa.alloc(*Window, n) catch @panic("OOM");
        defer gpa.free(wins);
        const rects = gpa.alloc(layout.Rect, n) catch @panic("OOM");
        defer gpa.free(rects);

        for (wm.windows.items) |win| {
            win.visible = false;
            if (win.decorate) {
                win.proxy.useSsd();
                win.proxy.setTiled(.{ .top = true, .bottom = true, .left = true, .right = true });
                win.decorate = false;
            }
        }
        for (wm.outputs.items) |out| {
            if (out.active == 0) continue;
            var k: usize = 0;
            for (wm.windows.items) |win| {
                if (win.workspace != out.active) continue;
                wins[k] = win;
                k += 1;
            }
            layout.bsp(out.usable orelse out.area, rects[0..k]);
            for (wins[0..k], rects[0..k]) |win, rect| {
                win.rect = rect;
                win.visible = true;
                win.proxy.proposeDimensions(rect.w, rect.h);
            }
        }

        if (wm.focus_dirty) {
            if (wm.seat) |seat| {
                if (wm.focused) |win| seat.focusWindow(win.proxy) else seat.clearFocus();
            }
            wm.focus_dirty = false;
        }
    }

    fn render(wm: *Wm) void {
        for (wm.windows.items) |win| {
            if (!win.visible) {
                win.proxy.hide();
                continue;
            }
            win.node.setPosition(win.rect.x, win.rect.y);
            win.proxy.show();
        }
        wm.proxy.renderFinish();
    }
};
