# Nimbus

A desktop operating system for [CC: Tweaked](https://tweaked.cc/) (ComputerCraft) computers in Minecraft: overlapping windows, a taskbar and Start menu, user accounts, apps, networking and monitor support, in about 108 KB of Lua.

## Install

You need an **advanced computer** (the gold one). Nimbus uses about 108 KB of the computer's 1 MB.

**Online** (the server must allow HTTP):

```
wget run https://raw.githubusercontent.com/first2569/nimbus/main/install.lua first2569/nimbus
```

**Offline:** download `dist/nimbus-setup.lua`, drag the file onto the open computer screen in-game, then run `nimbus-setup`.

Both end by offering to restart. The first boot asks you to create an account; that account is the administrator.

## Using it

| | |
|---|---|
| Open the Start menu | Click `♦` on the taskbar. Type to search, Enter opens the first match. |
| Move, resize, snap | Drag the title bar or the bottom-right corner. Drag to a screen edge to snap, or use the `#` button for the window menu. |
| Switch windows | Ctrl+Tab |
| Task Manager | Ctrl+Shift+Delete |
| Close a stuck program | Hold Ctrl+T (closes only the focused window) |
| Lock or sign out | Start menu |

Alt+Tab and Esc are not used because Windows and Minecraft take those keys before the computer sees them.

**Apps:** Files, Terminal, Notepad, Paint, Calculator, Clock (alarms and timers), Tasks, Settings, Peripherals, Chat, File Share, Remote Desktop, Store, Minesweeper, Worm, Adventure. Any program can also be started from a Terminal; `fg <program>` and `bg <program>` open it in its own window.

**Monitors:** attach an advanced monitor and it copies the computer's screen. Settings > Display switches it to its own desktop (Extend) or off. Monitors only report taps, so on a monitor:

- tap a title bar to move, resize or snap the window;
- tap `•••` on the taskbar, then tap again, for a right-click;
- use the arrows at the edge of a list to scroll.

**Networking:** attach a modem. Chat talks to computers in range. File Share downloads from another computer's `/shared` folder; put files in your own `/shared` to offer them. Remote Desktop lets one computer view and control another after entering its PIN; F12 disconnects.

**Updates and the Store:** Settings > Update checks the repository Nimbus was installed from and installs changes on the next restart. The Store installs extra apps from the same place. After an offline install, point them at a source with `set nimbus.repo <url-or-folder>`.

## If something goes wrong

Restart the computer (hold Ctrl+R) and watch the first two seconds:

- press **2** for **safe mode**, a plain menu that does not need the desktop;
- press **3** for the ordinary CraftOS shell.

Once accounts exist, both ask for an administrator's name and password.

**Forgot the administrator password?** In the world's save folder, delete `computercraft/computer/<id>/.nimbus/users.db`. Nimbus then runs first-boot setup again. Home folders are kept.

## Security: what it does and does not protect

Accounts keep players out of each other's files in normal use. They are not strong security.

- Passwords are stored as salted SHA-256 hashes in `/.nimbus/users.db`.
- Standard users cannot write to `/nimbus`, the boot files, `/.nimbus`, `.settings` or another user's home folder, and cannot make themselves administrator.
- Booting from a disk drive is switched off at setup, so a boot disk does not skip the login.

What gets past it:

- Anyone with access to the world's files can read or change everything, including the password hashes.
- Holding Ctrl+R or Ctrl+S always restarts or shuts down the computer.
- A program can use Lua's `debug` library to reach past the file guard.
- Files outside the folders listed above, such as `/shared`, are open to every user.
- **Nothing on the network is private or verified.** Rednet is not encrypted and any computer in range can pretend to be another. The Remote Desktop PIN stops accidents, not attackers: only share with players you trust.
- The Store and the updater run code from the repository they are pointed at. Only an administrator can install or update.

## Development

```
nimbus/kernel    scheduler, window manager, displays
nimbus/shell     taskbar, Start menu, desktop, notifications, sign-in
nimbus/lib       accounts, theme, networking, updater, UI helpers
nimbus/apps      one folder per app: app.json and usually main.lua
store            the Store's catalog and its apps
build            manifest and bundle generators
tests            logic tests (Lune) and emulator tests (CraftOS-PC)
```

Run everything with `sh tests/run.sh`. It needs [Lune](https://lune-org.github.io/docs) on the PATH and the portable [CraftOS-PC](https://www.craftos-pc.cc/) unpacked in `.tools/craftos-pc`. It also regenerates `build/manifest.json` and `dist/nimbus-setup.lua`, which must be committed together with any change to `nimbus/` or `startup.lua`: the updater compares installed files with that manifest.

An app is a folder in `nimbus/apps` with an `app.json`:

```json
{ "name": "Dice", "run": "/nimbus/apps/dice/main.lua", "pinned": false, "w": 30, "h": 8 }
```

`run` is a shell command (`~` is the user's home); leave it out for a plain Terminal. `pinned` puts it on the taskbar, and `w`/`h` set the window size. Programs get a global `nimbus` table: `nimbus.ui` (rows, buttons, lists, prompts, menus), `nimbus.theme` (colours), `nimbus.notify(title, text)`, `nimbus.open(path)`, `nimbus.home` and `nimbus.prefs`.

## Known gaps

- Tested in the CraftOS-PC emulator, not yet in Minecraft itself. Real monitors and downloads over real HTTP are untested.
- Alarms and timers only ring while the Clock window is open.
- The updater does not remove files that were deleted upstream.
- Chat cuts long messages at the window edge.
