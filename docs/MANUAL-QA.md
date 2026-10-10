# Manual QA (real Mac, ~15 min)

1. Install per the README, grant Full Disk Access, and watch indexing finish.
2. **Hotkey (T7):** press ⌥Space from Safari: the panel appears on the screen with the mouse; press ⌥Space again: it hides and Safari is frontmost again. Change the hotkey in Settings → "Search hotkey:" and confirm the new one works and ⌥Space no longer does. If another app owns ⌥Space, use the menu-bar item "Search…".
3. Type `fsearch main`. Check Return (reveal), ⌘Return (open), ↓ + Space (Quick Look), ⌘C (copy), ⌘⌥C (copy all).
4. Filters: `type:image size:>5mb mtime:<7d`, `ext:rs grep:apply_dir`, `in:~/Developer readme`.
5. Enable the Finder extension, add the toolbar button, use "Search here" on a folder (the chip appears).
6. Add an exclusion, toggle hidden files, enable launch at login.
7. Quit and relaunch: the daemon is restarted or adopted and the index reused.
8. Run the `fsearch` CLI alongside: it shares the index.
