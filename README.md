# MCKeyFix

A tiny macOS menu bar app that makes the built-in MacBook keyboard behave for Minecraft (Java Edition).

While Minecraft is frontmost **and** the mouse is captured (you're actually in-game, not in a menu or inventory), MCKeyFix:

- remaps **fn/🌐 → Left Control** on the internal keyboard only, so fn works as sprint and the Globe key can't switch the input source
- makes **F1–F12** act as real function keys (F3, F5, … work without holding fn)
- disables the **^Space / ^⌥Space** input-source shortcuts and the **^1–9 / ^←/^→** Spaces shortcuts, so sprint + jump/hotbar doesn't trigger them

Everything is restored as soon as you pause, open a menu, or switch apps. If the app crashes while active, it restores your settings on the next launch.

## Requirements

- macOS 11 or later
- Xcode Command Line Tools (`xcode-select --install`)

## Build & run

```sh
./build.sh
open MCKeyFix.app
```

A game controller icon appears in the menu bar; it fills in while the fixes are active. Choose **Quit MCKeyFix** from its menu to exit.

To start it automatically, add `MCKeyFix.app` under **System Settings → General → Login Items**.

No special permissions are needed. MCKeyFix only watches global mouse movement (to tell whether the game has captured the cursor) and never reads keystrokes.

## How it works

- **Minecraft detection:** Minecraft Java runs as a `java` process whose arguments mention `minecraft`. The launcher itself is ignored.
- **In-game detection:** when the game captures the mouse, mouse events keep arriving but the cursor position stays fixed. A few such events in a row mean you're playing; normal cursor movement means you're in a menu.
- **Remapping:** uses `hidutil` to set `UserKeyMapping` (scoped to the built-in keyboard) and `HIDFKeyMode`.
- **Shortcuts:** toggles the symbolic hotkeys through the private `CGSSetSymbolicHotKeyEnabled` API.
- Switching never happens while fn/Control is held down, so a modifier can't get stuck.

## Caveats

- It uses a private macOS API, which a future macOS update could break.
- While active, any custom `hidutil` `UserKeyMapping` you have on the internal keyboard is cleared when MCKeyFix deactivates.
- The app is ad-hoc signed. If you download a prebuilt copy instead of building it yourself, Gatekeeper may block it; right-click → Open, or build from source.

## License

[MIT](LICENSE)
