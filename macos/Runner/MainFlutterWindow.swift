import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let minimumContentSize = NSSize(width: 980, height: 700)

    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    self.contentMinSize = minimumContentSize
    if self.contentLayoutRect.size.width < minimumContentSize.width ||
        self.contentLayoutRect.size.height < minimumContentSize.height {
      let adjustedFrame = self.frameRect(
        forContentRect: NSRect(origin: .zero, size: minimumContentSize)
      )
      self.setContentSize(adjustedFrame.size)
    }

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }
}
