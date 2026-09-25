# v1.5.0

- Fix TEMP getting stuck at 52°C on idle Apple Silicon Macs: constant calibration sensors no longer count as the hottest reading.
- Report DISK usage and free space the way Finder does, counting purgeable space as available.
- Stack any two metrics on separate lines, keep the menu bar text sharp on mixed displays, and keep its width steady while values load.
- Close Settings with ⌘W or Esc, and pause monitoring while another user's session is active.
- Settings reopens where you left it and uses less memory after it is closed.
