import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    contentViewController = flutterViewController

    let content = fittedPhoneContentSize()
    setContentSize(content)
    styleMask.remove(.resizable)
    collectionBehavior = [.fullScreenNone, .managed]
    standardWindowButton(.zoomButton)?.isHidden = true
    let locked = frame.size
    minSize = locked
    maxSize = locked
    center()

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }

  /// دکمهٔ بزرگ‌نمایی و تمام‌صفحه اندازهٔ گوشی را عوض نمی‌کنند.
  override func zoom(_ sender: Any?) {}

  override func toggleFullScreen(_ sender: Any?) {}

  /// محتوای پنجره ۳۹۰×۸۴۴ است؛ اگر در صفحه جا نشود هم‌نسبت کوچک می‌شود.
  private func fittedPhoneContentSize() -> NSSize {
    var width: CGFloat = 390
    var height: CGFloat = 844
    let visible = (screen ?? NSScreen.main)?.visibleFrame
    guard let visible else {
      return NSSize(width: width, height: height)
    }
    let contentWidth = contentView?.bounds.width ?? width
    let contentHeight = contentView?.bounds.height ?? height
    let chromeW = frame.width - contentWidth
    let chromeH = frame.height - contentHeight
    let maxW = visible.width - 16 - chromeW
    let maxH = visible.height - 16 - chromeH
    if width > maxW { width = max(280, maxW) }
    if height > maxH { height = max(480, maxH) }
    return NSSize(width: width, height: height)
  }
}
