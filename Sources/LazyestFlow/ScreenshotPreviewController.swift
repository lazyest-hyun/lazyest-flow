import AppKit

final class ScreenshotPreviewController: NSObject, NSDraggingSource {
  private final class PreviewImageView: NSImageView {
    weak var owner: ScreenshotPreviewController?

    override func mouseDown(with event: NSEvent) {
      guard let owner, let window else { return }
      let start = event.locationInWindow
      while let next = window.nextEvent(
        matching: [.leftMouseDragged, .leftMouseUp],
        until: .distantFuture,
        inMode: .eventTracking,
        dequeue: true
      ) {
        if next.type == .leftMouseUp {
          owner.openOriginal()
          return
        }
        let location = next.locationInWindow
        if hypot(location.x - start.x, location.y - start.y) >= 4 {
          owner.beginDrag(from: self, event: next)
          return
        }
      }
    }

    override func rightMouseDown(with event: NSEvent) {
      guard let menu = owner?.contextMenu else { return }
      NSMenu.popUpContextMenu(menu, with: event, for: self)
    }
  }

  private let panel = NSPanel(
    contentRect: .zero,
    styleMask: [.borderless, .nonactivatingPanel],
    backing: .buffered,
    defer: false
  )
  private let imageView = PreviewImageView()
  private var dismissWorkItem: DispatchWorkItem?
  private var pngData: Data?
  private var fileURL: URL?

  override init() {
    super.init()
    imageView.owner = self
    imageView.imageScaling = .scaleProportionallyUpOrDown
    imageView.wantsLayer = true
    imageView.layer?.cornerRadius = 12
    imageView.layer?.masksToBounds = true

    panel.contentView = imageView
    panel.isOpaque = false
    panel.backgroundColor = .clear
    panel.hasShadow = true
    panel.level = .floating
    panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
    panel.hidesOnDeactivate = false
    panel.ignoresMouseEvents = false
  }

  func show(pngData: Data, fileURL: URL) {
    guard let image = NSImage(data: pngData) else { return }
    self.pngData = pngData
    self.fileURL = fileURL
    imageView.image = image

    let screen =
      NSScreen.screens.first(where: {
        NSMouseInRect(NSEvent.mouseLocation, $0.frame, false)
      }) ?? NSScreen.main
    guard let screen else { return }

    let maxWidth: CGFloat = 280
    let maxHeight: CGFloat = 180
    let ratio = max(image.size.width, 1) / max(image.size.height, 1)
    var size = NSSize(width: maxWidth, height: maxWidth / ratio)
    if size.height > maxHeight {
      size = NSSize(width: maxHeight * ratio, height: maxHeight)
    }
    size.width = max(size.width, 140)
    size.height = max(size.height, 90)

    let visible = screen.visibleFrame
    panel.setFrame(
      NSRect(
        x: visible.maxX - size.width - 20,
        y: visible.minY + 20,
        width: size.width,
        height: size.height
      ),
      display: true
    )

    dismissWorkItem?.cancel()
    panel.alphaValue = 1
    panel.orderFrontRegardless()

    let workItem = DispatchWorkItem { [weak self] in
      self?.panel.orderOut(nil)
    }
    dismissWorkItem = workItem
    DispatchQueue.main.asyncAfter(deadline: .now() + 5, execute: workItem)
  }

  fileprivate var contextMenu: NSMenu {
    let menu = NSMenu()
    menu.addItem(
      withTitle: "열기",
      action: #selector(openOriginal),
      keyEquivalent: ""
    ).target = self
    menu.addItem(
      withTitle: "Finder에서 보기",
      action: #selector(revealOriginal),
      keyEquivalent: ""
    ).target = self
    menu.addItem(.separator())
    menu.addItem(
      withTitle: "이미지 복사",
      action: #selector(copyImage),
      keyEquivalent: ""
    ).target = self
    menu.addItem(
      withTitle: "공유",
      action: #selector(shareOriginal),
      keyEquivalent: ""
    ).target = self
    return menu
  }

  fileprivate func beginDrag(from view: NSView, event: NSEvent) {
    guard let fileURL, let image = imageView.image else { return }
    dismissWorkItem?.cancel()
    let item = NSDraggingItem(pasteboardWriter: fileURL as NSURL)
    item.setDraggingFrame(view.bounds, contents: image)
    view.beginDraggingSession(with: [item], event: event, source: self)
  }

  @objc fileprivate func openOriginal() {
    guard let fileURL else { return }
    NSWorkspace.shared.open(fileURL)
  }

  @objc private func revealOriginal() {
    guard let fileURL else { return }
    NSWorkspace.shared.activateFileViewerSelecting([fileURL])
  }

  @objc private func copyImage() {
    guard let pngData else { return }
    let pasteboard = NSPasteboard.general
    pasteboard.clearContents()
    pasteboard.setData(pngData, forType: .png)
  }

  @objc private func shareOriginal() {
    guard let fileURL else { return }
    let picker = NSSharingServicePicker(items: [fileURL])
    picker.show(relativeTo: imageView.bounds, of: imageView, preferredEdge: .minY)
  }

  func draggingSession(
    _ session: NSDraggingSession,
    sourceOperationMaskFor context: NSDraggingContext
  ) -> NSDragOperation {
    .copy
  }

  func draggingSession(
    _ session: NSDraggingSession,
    endedAt screenPoint: NSPoint,
    operation: NSDragOperation
  ) {
    panel.orderOut(nil)
  }
}
