# VHS tape: renders a real terminal GIF of the iOS CI demo.
# Install VHS (https://github.com/charmbracelet/vhs), then:  vhs assets/demo.tape
# Produces assets/demo.gif.

Output assets/demo.gif

Set FontSize 20
Set Width 1200
Set Height 620
Set Padding 24
Set Theme "GitHub Dark"

Type "cd examples/ios-ci"
Enter
Sleep 500ms

Type "# No car. No adapter. No Bluetooth radio."
Enter
Sleep 800ms

Type "swift test"
Enter
Sleep 6s

Type "# Your real CoreBluetooth code, tested against a scripted ELM327."
Enter
Sleep 2s
