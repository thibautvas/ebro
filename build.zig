const std = @import("std");
const Scanner = @import("wayland").Scanner;

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const scanner = Scanner.create(b, .{});
    scanner.addCustomProtocol(b.path("protocol/river-window-management-v1.xml"));
    scanner.addCustomProtocol(b.path("protocol/river-xkb-bindings-v1.xml"));
    scanner.addCustomProtocol(b.path("protocol/river-layer-shell-v1.xml"));
    scanner.addCustomProtocol(b.path("protocol/river-input-management-v1.xml"));
    scanner.generate("wl_compositor", 4);
    scanner.generate("wl_output", 4);
    scanner.generate("wl_seat", 7);
    scanner.generate("river_window_manager_v1", 6);
    scanner.generate("river_xkb_bindings_v1", 2);
    scanner.generate("river_layer_shell_v1", 1);
    scanner.generate("river_input_manager_v1", 2);

    const wayland = b.createModule(.{ .root_source_file = scanner.result });

    const ebro = b.createModule(.{ .root_source_file = b.path("src/ebro.zig") });
    ebro.addImport("wayland", wayland);

    const config = b.createModule(.{ .root_source_file = b.path("src/config.zig") });
    config.addImport("ebro", ebro);

    const exe = b.addExecutable(.{
        .name = "ebro",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        }),
    });
    exe.root_module.addImport("wayland", wayland);
    exe.root_module.addImport("ebro", ebro);
    exe.root_module.addImport("config", config);
    exe.root_module.linkSystemLibrary("wayland-client", .{});
    b.installArtifact(exe);
}
