# ebro

Minimal tiling window manager for the [river](https://codeberg.org/river/river)
wayland compositor, written in zig.

ebro talks to river through the [river protocol](./protocol/).
It runs as a regular wayland client inside a river session.

## Features

- Binary space partitioning layout
- Workspaces pinned to outputs by name
- Key bindings through xkb
- Autostart commands
- Window rules: send apps to a workspace by app_id
- Configured at compile time:
  no config parser, no runtime dependencies except `libwayland-client`

## Requirements

- river with the window management protocols (tested with river 0.5.2)
- Zig 0.17.1
- `wayland`, `wayland-scanner`, `wayland-protocols`, `pkg-config`

## Building

```bash
zig build -Doptimize=ReleaseSafe
```

## Running

Start ebro from inside a river session, for example from river's startup
command:
```bash
river -c ./zig-out/bin/ebro
```

ebro exits when river ends the session,
and exits with status 1 if another window manager is already connected.

## Configuration

All configuration lives in `src/config.zig` and is compiled in.
Edit it and rebuild:
```zig
const ebro = @import("ebro");

pub const workspace_count = 3;
pub const workspace_outputs = [workspace_count]?[]const u8{ "DP-2", "DP-2", "eDP-1" };

pub const autostart = [_][:0]const u8{"foot --server"};

pub const binds = [_]ebro.Bind{
    .{ .mods = .{ .mod4 = true }, .keysym = 'k', .action = .{ .spawn = "footclient" } },
    .{ .mods = .{ .mod4 = true }, .keysym = 'm', .action = .exit },
};
```

- `workspace_outputs` maps each workspace to an output name,
  `null` falls back to the first output
- `keysym` is an xkb keysym value
- `mods` accepts `shift`, `ctrl`, `mod1` (alt), `mod4` (super)
- `.locked = true` on a bind keeps it active while the screen is locked
- `rules` makes a new window with matching app_id open on the specified workspace

Available actions:
| Action | Effect |
| --- | --- |
| `.{ .spawn = "cmd" }` | Run `cmd` through `/bin/sh`, pipes and arguments work |
| `.close` | Close the focused window |
| `.exit` | End the river session |
| `.{ .launch_or_focus = .{ .app_id = "id", .cmd = "cmd" } }` | Focus the first window with app_id `id`, or spawn `cmd` if there is none |
| `.{ .focus_workspace = n }` | Switch to workspace `n` (1-based) |
| `.{ .move_to_workspace = n }` | Move the focused window to workspace `n` and follow it there |
| `.focus_next` | Focus the next window on the current workspace, wrapping around |
| `.swap_master` | Swap the focused window with the master window |
| `.toggle_fullscreen` | Toggle fullscreen for the focused window |

The default config only binds super+m to exit the session.

With Nix, pass your own config file without touching the source:
```nix
ebro.packages.x86_64-linux.ebro.override {
  configFile = ./config.zig;
}
```

## License

- [MIT](./LICENSE) licensed
- The [river protocol](./protocol/) files are MIT licensed by Isaac Freund
