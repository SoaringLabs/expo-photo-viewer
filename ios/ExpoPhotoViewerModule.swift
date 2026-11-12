import ExpoModulesCore
import UIKit

struct PhotoViewerLabels: Record {
  @Field var close: String = "Close"
  @Field var retry: String = "Retry photo"
  @Field var unavailable: String = "Photo unavailable"
  @Field var position: String = "Photo {current} of {total}"

  func photoPosition(index: Int, count: Int) -> String {
    position.replacingOccurrences(of: "{current}", with: String(index + 1))
      .replacingOccurrences(of: "{total}", with: String(count))
  }
}

struct PhotoViewerItem: Record {
  @Field var key: String = ""
  @Field var width: Double = 0
  @Field var height: Double = 0
  @Field var previewUri: String?
  @Field var fullUri: String?
  @Field var sourceTag: Int?
}

struct PhotoViewerCloseButtonOptions: Record {
  static let diameter: CGFloat = 44
  typealias Views = (button: UIButton, icon: UIImageView?)

  @Field var symbolName: String?
  @Field var tintColor: UIColor?
  @Field var backgroundColor: UIColor?

  func makeViews() -> Views {
    let image = symbolName.flatMap { UIImage(systemName: $0) }
    guard image != nil || tintColor != nil || backgroundColor != nil else {
      return Self.makeSystemViews()
    }

    let button = UIButton(type: .system)
    button.setImage(image ?? UIImage(systemName: "xmark"), for: .normal)
    button.tintColor = tintColor ?? .white
    button.backgroundColor = backgroundColor ?? UIColor.black.withAlphaComponent(0.65)
    button.layer.cornerRadius = Self.diameter / 2
    return (button, nil)
  }

  static func makeSystemViews() -> Views {
    if #available(iOS 26.0, *) {
      var configuration = UIButton.Configuration.glass()
      configuration.cornerStyle = .capsule
      configuration.contentInsets = .zero
      let button = UIButton(configuration: configuration)
      // The glass rim can extend beyond the configuration's capsule.
      button.layer.cornerRadius = diameter / 2
      button.layer.cornerCurve = .circular
      button.clipsToBounds = true
      // Draw the symbol outside the button's glass press animation.
      let symbol = UIImage.SymbolConfiguration(pointSize: 22, weight: .regular)
      let icon = UIImageView(image: UIImage(systemName: "xmark", withConfiguration: symbol))
      icon.tintColor = .label
      icon.isUserInteractionEnabled = false
      icon.isAccessibilityElement = false
      return (button, icon)
    }

    let button = UIButton(type: .close)
    button.overrideUserInterfaceStyle = .dark
    return (button, nil)
  }
}

public final class ExpoPhotoViewerModule: Module {
  private weak var gallery: PhotoGalleryController?

  public func definition() -> ModuleDefinition {
    Name("ExpoPhotoViewer")
    Constant("isSupported") {
      if #available(iOS 18.0, *) { return true }
      return false
    }
    Events("onRequestPhoto", "onClose")

    AsyncFunction("present") { [self] (
      session: String, items: [PhotoViewerItem], index: Int, labels: PhotoViewerLabels,
      closeButton: PhotoViewerCloseButtonOptions?
    ) -> Bool in
      guard #available(iOS 18.0, *), self.gallery == nil, items.indices.contains(index),
            let presenter = self.appContext?.utilities?.currentViewController(),
            presenter.viewIfLoaded?.window != nil,
            !presenter.isBeingDismissed, presenter.presentedViewController == nil
      else { return false }

      let controller = PhotoGalleryController(
        session: session, items: items, index: index, labels: labels,
        closeControl: closeButton?.makeViews() ?? PhotoViewerCloseButtonOptions.makeSystemViews()
      )
      controller.modalPresentationStyle = .fullScreen
      controller.onRequest = { [weak self] key, retry in
        self?.sendEvent("onRequestPhoto", ["session": session, "key": key, "retry": retry])
      }
      controller.onClose = { [weak self] in
        self?.gallery = nil
        self?.sendEvent("onClose", ["session": session])
      }
      if !UIAccessibility.isReduceMotionEnabled, items[index].sourceTag != nil {
        let options = UIViewController.Transition.ZoomOptions()
        options.alignmentRectProvider = { context in
          (context.zoomedViewController as? PhotoGalleryController)?.photoAlignmentRect
        }
        options.interactiveDismissShouldBegin = { [weak controller] context in
          controller?.canDismissInteractively(at: context.location, velocity: context.velocity) ?? false
        }
        controller.preferredTransition = .zoom(options: options) { [weak self] context in
          guard let gallery = context.zoomedViewController as? PhotoGalleryController,
                let tag = gallery.currentItem.sourceTag,
                let source = self?.appContext?.findView(withTag: tag, ofType: UIView.self),
                let window = source.window, !source.isHidden,
                source.convert(source.bounds, to: window).intersects(window.bounds)
          else { return nil }
          return source
        }
      } else {
        controller.modalTransitionStyle = .crossDissolve
      }
      self.gallery = controller
      presenter.present(controller, animated: true)
      return true
    }.runOnQueue(.main)

    AsyncFunction("setPhoto") { (session: String, key: String, uri: String?, unavailable: Bool) in
      guard let gallery = self.gallery, gallery.session == session else { return }
      gallery.setPhoto(key: key, uri: uri, unavailable: unavailable)
    }.runOnQueue(.main)

    AsyncFunction("dismiss") { (session: String) in
      guard let gallery = self.gallery, gallery.session == session else { return }
      gallery.dismiss(animated: false)
    }.runOnQueue(.main)
  }
}
