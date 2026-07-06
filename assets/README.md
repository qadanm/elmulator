# Assets

Note on theming: `prefers-color-scheme` follows the viewer's **OS/browser**, not GitHub's theme toggle, so a `<picture>` swap can serve the "wrong" variant (for example GitHub dark plus OS light gives a light image on a dark page). To stay readable regardless, the logo is a single theme-agnostic file, and each diagram variant carries its **own background panel** so text contrast never depends on the page.

- **`logo.svg`**: the elmulator wordmark and mark (a terminal `>_`, echoing the ELM327 prompt). Single file; the accent blue reads on both light and dark backgrounds.
- **`architecture-dark.svg` / `architecture-light.svg`**: the one-image pitch, your app to a scripted ELM327 (mock BLE) to green CI, with no car, adapter, or radio. Each has its own panel background; selected via `<picture>`. The light variant is a palette swap of the dark one.
- **`features-dark.svg` / `features-light.svg`**: the capability grid, the six ways one engine fakes the adapter (in-process BLE double, CoreBluetooth-Mock bridge, real BLE peripheral, TCP server, GitHub Action, byte-for-byte parity). Same panel and palette conventions as the architecture pair.
- **`demo.svg`**: animated terminal recording of the iOS CI test suite (`ObdSampleClientTests`) running green with no Bluetooth radio. Self-contained animated SVG; renders inline in the README on GitHub. Content mirrors the real `swift test` output.
- **`demo.tape`**: [VHS](https://github.com/charmbracelet/vhs) script that records a true `.gif` of the same demo. Regenerate with `vhs assets/demo.tape`, which writes `assets/demo.gif` (requires VHS and ffmpeg).

To swap the README hero to a real GIF, run VHS and change the image reference from `assets/demo.svg` to `assets/demo.gif`.

All SVGs use hardcoded hex colors (no CSS variables) so they render self-contained on GitHub. The dark and light variants of a pair share identical geometry and differ only in palette, so edit both together.
