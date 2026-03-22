import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()

    // Phone-sized window, height trimmed to fit 13" MacBook display
    let phoneWidth: CGFloat = 393
    let phoneHeight: CGFloat = 600

    // Center on screen
    let screenFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
    let originX = screenFrame.midX - phoneWidth / 2
    let originY = screenFrame.midY - phoneHeight / 2
    let windowFrame = NSRect(x: originX, y: originY, width: phoneWidth, height: phoneHeight)

    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    // Lock window size (no resizing)
    self.minSize = NSSize(width: phoneWidth, height: phoneHeight)
    self.maxSize = NSSize(width: phoneWidth, height: phoneHeight)

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }
}
