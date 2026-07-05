# Assets

- **`demo.svg`** — animated terminal recording of the iOS CI test suite (`ObdSampleClientTests`) running green with no Bluetooth radio. Self-contained animated SVG; renders inline in the README on GitHub. Content mirrors the real `swift test` output.
- **`demo.tape`** — [VHS](https://github.com/charmbracelet/vhs) script that records a true `.gif` of the same demo. Regenerate with `vhs assets/demo.tape` → `assets/demo.gif` (requires VHS + ffmpeg).

To swap the README hero to a real GIF, run VHS and change the image reference from `assets/demo.svg` to `assets/demo.gif`.
