# Manual test checklist

Use a disposable Transmission instance and a legal test torrent.

- Test Transmission 4.0.x and 4.1+ with valid and invalid credentials.
- Test HTTPS, acknowledged HTTP, unreachable host, and a deliberately short
  timeout.
- Open the same magnet twice; the second result must say the torrent is already
  added and the server must contain one torrent.
- Test immediate and paused start modes.
- Test the system browser and at least one explicitly selected browser.
- Select a browser, uninstall or move it, then confirm fallback and warning.
- Trigger a link from Safari, Chrome, Firefox, and:

  ```sh
  open "magnet:?xt=urn:btih:0123456789abcdef0123456789abcdef01234567"
  ```

- Inspect Console output, UserDefaults, and a diagnostic report for passwords
  and full magnet links.
- Confirm that downloads occur on the Transmission server and no torrent
  payload is created on the Mac.
