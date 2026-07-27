# Manual test checklist

Use a disposable Transmission instance and a legal test torrent.

## Configuration

- At the default window size, confirm the collapsed settings fit without a
  vertical scrollbar. Expanded optional fields may scroll when necessary.
- Enter only a server address and confirm the standard
  `/transmission/rpc` and `/transmission/web/` paths are derived.
- Enable **Use custom endpoint URLs** below the server field and verify both
  URL fields appear, override the standard paths, and collapse again cleanly.
- Confirm **Use Basic Authentication** is off by default and hides credential
  fields. Test valid and invalid credentials against Transmission 4.0.x and
  4.1+.
- Save a password, disable authentication, and confirm the Keychain item is
  retained but no `Authorization` header is sent. Re-enable authentication and
  confirm the saved password works without being displayed.
- Exercise the same behavior with:

  ```sh
  magnetbridge config set username alice
  magnetbridge config set password
  magnetbridge config set authentication false
  magnetbridge config set authentication true
  ```

- Test HTTPS, acknowledged HTTP, unreachable host, and a deliberately short
  timeout. The HTTP warning must mention credentials only when authentication
  is enabled.
- Test immediate and paused start modes.

## Magnet and browser flow

- Open the same magnet twice; the second result must say the torrent is already
  added and the server must contain one torrent.
- Test the system browser and at least one explicitly selected browser. Browser
  choices must show the corresponding installed application icons.
- Select a browser, uninstall or move it, then confirm system-browser fallback
  and a warning.
- Trigger a link from Safari, Chrome, Firefox, and:

  ```sh
  open "magnet:?xt=urn:btih:0123456789abcdef0123456789abcdef01234567"
  ```

- Confirm every incoming link opens the destination chooser, the server action
  adds the torrent, and each listed local handler opens it without recursively
  launching MagnetBridge.

## Window, menu bar, and Help

- Confirm Behavior rows and controls align on the leading edge.
- Enable menu-bar mode, close the window, and reopen it from the status item.
  Check the custom monochrome template icon against light and dark menu bars.
- Disable menu-bar mode and confirm the Dock icon appears and the app quits
  after its last window closes.
- Open **MagnetBridge Help** from the header, application menu, and status menu.
  Verify the setup steps, version/build, Transmission and project links, issue
  link, and **Check for Updates…** action.

## Updates

- Run **Check for Updates…** from the application menu, status menu, Help, and
  **Check Now** in settings. Each entry point must use Sparkle's standard UI.
- Toggle **Automatically check for updates**, relaunch, and confirm the choice
  persists. No system-profile parameters or telemetry should be sent.
- Confirm the latest GitHub Release contains a valid signed `appcast.xml` that
  points to the tagged `MagnetBridge.zip`.
- Test a real upgrade between two successively numbered, signed, notarized
  Sparkle-enabled builds on Apple Silicon and Intel. Confirm installation,
  relaunch, settings, Keychain password, magnet handler, and CLI symlink.
- With a controlled test feed, confirm a modified feed or archive is rejected.
- Confirm a pre-Sparkle installation requires one external update, then can
  update natively thereafter.
- For a Homebrew installation, update once through Sparkle and confirm a later
  `brew upgrade --cask magnet-bridge` does not downgrade the installed bundle.

## Privacy and results

- Inspect Console output, UserDefaults, diagnostics, appcast requests, and
  release logs for passwords, private update keys, and full magnet links.
- Confirm downloads occur on the Transmission server and no torrent payload is
  created on the Mac.
