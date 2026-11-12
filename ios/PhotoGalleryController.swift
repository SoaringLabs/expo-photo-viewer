import UIKit

final class PhotoGalleryController: UIViewController, UIScrollViewDelegate {
  let session: String
  var onRequest: ((String, Bool) -> Void)?
  var onClose: (() -> Void)?
  var currentItem: PhotoViewerItem { items[index] }
  var photoAlignmentRect: CGRect? { pages[index].alignmentRect(in: view) }

  func canDismissInteractively(at location: CGPoint, velocity: CGVector) -> Bool {
    didFinishOpening && velocity.dy > abs(velocity.dx) && pages[index].atFit && !pager.isDecelerating
      && (!counter.isUserInteractionEnabled || !counter.frame.contains(location))
  }

  private let items: [PhotoViewerItem]
  private let pages: [PhotoGalleryPage]
  private var index: Int
  private let labels: PhotoViewerLabels
  private let pager = UIScrollView()
  private let closeButton: UIButton
  private let closeIcon: UIImageView?
  private let counter = UIVisualEffectView(effect: nil)
  private let counterText = UIStackView()
  private let currentPageNumber = UILabel()
  private var controlsHidden = false
  private var viewport = CGSize.zero
  private var didFinishOpening = false

  init(
    session: String, items: [PhotoViewerItem], index: Int, labels: PhotoViewerLabels,
    closeControl: PhotoViewerCloseButtonOptions.Views
  ) {
    self.session = session
    self.items = items
    self.index = index
    self.labels = labels
    self.closeButton = closeControl.button
    self.closeIcon = closeControl.icon
    self.pages = items.enumerated().map { PhotoGalleryPage(item: $0.element, index: $0.offset, count: items.count, labels: labels) }
    super.init(nibName: nil, bundle: nil)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { nil }

  override var prefersStatusBarHidden: Bool { true }
  override var prefersHomeIndicatorAutoHidden: Bool { true }

  override func viewDidLoad() {
    super.viewDidLoad()
    if #available(iOS 26.0, *) { overrideUserInterfaceStyle = .dark }
    view.backgroundColor = .black
    view.accessibilityViewIsModal = true
    pager.contentInsetAdjustmentBehavior = .never
    pager.isPagingEnabled = true
    pager.showsHorizontalScrollIndicator = false
    pager.scrollsToTop = false
    pager.delegate = self
    view.addSubview(pager)
    for (pageIndex, page) in pages.enumerated() {
      pager.addSubview(page)
      let photoKey = page.item.key
      page.onRequest = { [weak self] retry in self?.onRequest?(photoKey, retry) }
      page.onToggle = { [weak self] in self?.toggleControls() }
      page.onZoom = { [weak self] zoomed in
        guard let self, self.index == pageIndex else { return }
        self.pager.isScrollEnabled = !zoomed
      }
    }
    configureControls()
    updatePage()
  }

  override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews()
    guard viewport != view.bounds.size, view.bounds.width > 0 else { return }
    viewport = view.bounds.size
    pager.frame = view.bounds
    pager.contentSize = CGSize(width: viewport.width * CGFloat(pages.count), height: viewport.height)
    for (pageIndex, page) in pages.enumerated() {
      page.frame = CGRect(x: CGFloat(pageIndex) * viewport.width, y: 0, width: viewport.width, height: viewport.height)
      page.layoutIfNeeded()
    }
    pager.contentOffset = CGPoint(x: CGFloat(index) * viewport.width, y: 0)
  }

  override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)
    didFinishOpening = true
    pages[index].requestIfNeeded()
  }

  override func viewDidDisappear(_ animated: Bool) {
    super.viewDidDisappear(animated)
    if isBeingDismissed || presentingViewController == nil {
      onClose?()
      onClose = nil
    }
  }

  override func accessibilityPerformEscape() -> Bool {
    dismiss(animated: true)
    return true
  }

  private func configureControls() {
    closeButton.accessibilityLabel = labels.close
    closeButton.addAction(UIAction { [weak self] _ in self?.dismiss(animated: true) }, for: .touchUpInside)
    configureCounter()
    for control in [closeButton, counter] as [UIView] {
      control.translatesAutoresizingMaskIntoConstraints = false
      view.addSubview(control)
    }
    let safe = view.safeAreaLayoutGuide
    NSLayoutConstraint.activate([
      closeButton.topAnchor.constraint(equalTo: safe.topAnchor, constant: 4),
      closeButton.leadingAnchor.constraint(equalTo: safe.leadingAnchor, constant: 12),
      closeButton.widthAnchor.constraint(equalToConstant: PhotoViewerCloseButtonOptions.diameter),
      closeButton.heightAnchor.constraint(equalTo: closeButton.widthAnchor),
      counter.centerXAnchor.constraint(equalTo: view.centerXAnchor),
      counter.centerYAnchor.constraint(equalTo: closeButton.centerYAnchor)
    ])
    if let closeIcon {
      closeIcon.translatesAutoresizingMaskIntoConstraints = false
      view.addSubview(closeIcon)
      NSLayoutConstraint.activate([
        closeIcon.centerXAnchor.constraint(equalTo: closeButton.centerXAnchor),
        closeIcon.centerYAnchor.constraint(equalTo: closeButton.centerYAnchor)
      ])
    }
  }

  private func configureCounter() {
    let total = UILabel()
    let font = UIFont.monospacedDigitSystemFont(ofSize: 15, weight: .medium)
    for label in [currentPageNumber, total] {
      label.textColor = .white
      label.font = font
      label.isAccessibilityElement = false
    }
    total.text = "/ \(items.count)"
    currentPageNumber.textAlignment = .right
    currentPageNumber.clipsToBounds = true
    let numberWidth = (String(items.count) as NSString).size(withAttributes: [.font: font]).width
    currentPageNumber.widthAnchor.constraint(equalToConstant: ceil(numberWidth)).isActive = true

    counterText.addArrangedSubview(currentPageNumber)
    counterText.addArrangedSubview(total)
    counterText.alignment = .center
    counterText.spacing = 4
    counterText.translatesAutoresizingMaskIntoConstraints = false
    counter.contentView.addSubview(counterText)
    counter.isHidden = items.count < 2
    counter.isUserInteractionEnabled = false
    let size: CGSize
    if #available(iOS 26.0, *) {
      size = CGSize(width: 160, height: 44)
      counter.cornerConfiguration = .capsule()
      if items.count > 1 {
        counter.effect = makeCounterGlassEffect()
        counter.isUserInteractionEnabled = true
      }
      currentPageNumber.textColor = .label
      total.textColor = .label
    } else {
      size = CGSize(width: 58, height: 28)
      counter.backgroundColor = UIColor.black.withAlphaComponent(0.65)
      counter.layer.cornerRadius = size.height / 2
      counter.clipsToBounds = true
    }
    let preferredWidth = counter.widthAnchor.constraint(equalToConstant: size.width)
    preferredWidth.priority = .defaultHigh
    NSLayoutConstraint.activate([
      counterText.centerXAnchor.constraint(equalTo: counter.contentView.centerXAnchor),
      counterText.centerYAnchor.constraint(equalTo: counter.contentView.centerYAnchor),
      counter.widthAnchor.constraint(greaterThanOrEqualTo: counterText.widthAnchor, constant: 16),
      counter.widthAnchor.constraint(greaterThanOrEqualToConstant: size.width),
      counter.heightAnchor.constraint(equalToConstant: size.height),
      preferredWidth
    ])
    counter.isAccessibilityElement = true
    counter.accessibilityTraits = .staticText
  }

  @available(iOS 26.0, *)
  private func makeCounterGlassEffect() -> UIGlassEffect {
    let effect = UIGlassEffect(style: .regular)
    effect.isInteractive = true
    return effect
  }

  private func toggleControls() {
    controlsHidden.toggle()
    let hidden = controlsHidden
    let controls: [UIView] = items.count > 1 ? [closeButton, counter] : [closeButton]
    closeButton.isUserInteractionEnabled = !hidden
    if #available(iOS 26.0, *) {
      counter.isUserInteractionEnabled = !hidden && items.count > 1
    }
    for control in controls {
      control.isAccessibilityElement = !hidden
      if !hidden { control.isHidden = false }
    }

    let updateAppearance = {
      let opacity: CGFloat = hidden ? 0 : 1
      self.closeButton.alpha = opacity
      self.closeIcon?.alpha = opacity
      guard self.items.count > 1 else { return }
      if #available(iOS 26.0, *) {
        self.counter.effect = hidden ? nil : self.makeCounterGlassEffect()
        self.counterText.alpha = opacity
      } else {
        self.counter.alpha = opacity
      }
    }

    if UIAccessibility.isReduceMotionEnabled {
      for control in controls { control.layer.removeAllAnimations() }
      closeIcon?.layer.removeAllAnimations()
      counterText.layer.removeAllAnimations()
      UIView.performWithoutAnimation(updateAppearance)
      for control in controls { control.isHidden = hidden }
      return
    }

    UIView.animate(
      withDuration: 0.22, delay: 0,
      options: [.beginFromCurrentState, .allowUserInteraction, .curveEaseInOut],
      animations: updateAppearance
    ) { [weak self] finished in
      guard finished, hidden, self?.controlsHidden == true else { return }
      for control in controls { control.isHidden = true }
    }
  }

  private func updatePage(from previousIndex: Int? = nil) {
    if let previousIndex, items.count > 1, !controlsHidden, !UIAccessibility.isReduceMotionEnabled {
      let transition = CATransition()
      transition.type = .push
      transition.subtype = index > previousIndex ? .fromBottom : .fromTop
      transition.duration = 0.2
      transition.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
      currentPageNumber.layer.add(transition, forKey: "pageNumber")
    }
    currentPageNumber.text = String(index + 1)
    counter.accessibilityLabel = labels.photoPosition(index: index, count: items.count)
    for (pageIndex, page) in pages.enumerated() {
      page.accessibilityElementsHidden = pageIndex != index
      if abs(pageIndex - index) <= 1 { page.showCachedPhoto() }
      else { page.releaseImage() }
    }
  }

  private func finishPaging() {
    guard viewport.width > 0 else { return }
    let next = min(items.count - 1, max(0, Int((pager.contentOffset.x / viewport.width).rounded())))
    guard next != index else { return }
    let previous = index
    index = next
    updatePage(from: previous)
    pages[index].requestIfNeeded()
    UIAccessibility.post(notification: .pageScrolled, argument: counter.accessibilityLabel)
  }

  func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) { finishPaging() }
  func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
    if !decelerate { finishPaging() }
  }

  func setPhoto(key: String, uri: String?, unavailable: Bool) {
    guard let page = pages.first(where: { $0.item.key == key }) else { return }
    page.setFullPhoto(uri: uri, unavailable: unavailable)
  }
}

private final class PhotoGalleryPage: UIView, UIScrollViewDelegate {
  let item: PhotoViewerItem
  var onRequest: ((Bool) -> Void)?
  var onToggle: (() -> Void)?
  var onZoom: ((Bool) -> Void)?
  var atFit: Bool { scroll.zoomScale <= 1.001 && !scroll.isZooming }

  private let scroll = UIScrollView()
  private let imageView = UIImageView()
  private let retry = UIButton(type: .system)
  private let spinner = UIActivityIndicatorView(style: .medium)
  private let labels: PhotoViewerLabels
  private var fullUri: String?
  private var requested = false
  private var displayUri: String?
  private var viewport = CGSize.zero

  init(item: PhotoViewerItem, index: Int, count: Int, labels: PhotoViewerLabels) {
    self.item = item
    self.labels = labels
    self.fullUri = item.fullUri
    super.init(frame: .zero)
    scroll.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    scroll.contentInsetAdjustmentBehavior = .never
    scroll.showsHorizontalScrollIndicator = false
    scroll.showsVerticalScrollIndicator = false
    scroll.scrollsToTop = false
    scroll.maximumZoomScale = 1
    scroll.panGestureRecognizer.isEnabled = false
    scroll.delegate = self
    addSubview(scroll)
    imageView.contentMode = .scaleAspectFit
    imageView.isAccessibilityElement = true
    imageView.accessibilityTraits = .image
    imageView.accessibilityLabel = labels.photoPosition(index: index, count: count)
    scroll.addSubview(imageView)
    scroll.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(toggleControls)))

    retry.tintColor = .white
    retry.backgroundColor = UIColor.black.withAlphaComponent(0.8)
    retry.layer.cornerRadius = 12
    retry.configuration = .plain()
    retry.addAction(UIAction { [weak self] _ in self?.requestIfNeeded(retry: true) }, for: .touchUpInside)
    retry.isHidden = true
    spinner.color = .white
    for control in [spinner, retry] as [UIView] {
      control.translatesAutoresizingMaskIntoConstraints = false
      addSubview(control)
      NSLayoutConstraint.activate([
        control.centerXAnchor.constraint(equalTo: centerXAnchor),
        control.centerYAnchor.constraint(equalTo: centerYAnchor)
      ])
    }
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { nil }

  override func layoutSubviews() {
    super.layoutSubviews()
    scroll.frame = bounds
    if viewport != scroll.bounds.size { fitImage() }
  }

  func alignmentRect(in target: UIView) -> CGRect? {
    let rect = imageView.convert(imageView.bounds, to: target).intersection(target.bounds)
    return rect.isEmpty ? nil : rect
  }

  func showCachedPhoto() {
    guard let uri = fullUri ?? item.previewUri, displayUri != uri else { return }
    load(uri: uri, full: fullUri != nil)
  }

  func releaseImage() {
    guard displayUri != nil else { return }
    displayUri = nil
    scroll.setZoomScale(1, animated: false)
    scroll.maximumZoomScale = 1
    imageView.image = nil
  }

  func requestIfNeeded(retry shouldRetry: Bool = false) {
    guard shouldRetry || (!requested && fullUri == nil) else { return }
    requested = true
    retry.isHidden = true
    spinner.startAnimating()
    onRequest?(shouldRetry)
  }

  func setFullPhoto(uri: String?, unavailable: Bool) {
    fullUri = uri
    if let uri {
      displayUri = nil
      load(uri: uri, full: true)
    } else {
      showFailure(unavailable: unavailable)
    }
  }

  private func load(uri: String, full: Bool) {
    guard let url = URL(string: uri), url.isFileURL else {
      if full { showFailure(unavailable: false) }
      return
    }
    displayUri = uri
    DispatchQueue.global(qos: .userInitiated).async { [weak self] in
      let image = UIImage(contentsOfFile: url.path)
      DispatchQueue.main.async { [weak self] in
        guard let self, self.displayUri == uri else { return }
        if let image {
          self.imageView.image = image
          if self.atFit { self.fitImage() }
          if full {
            self.scroll.maximumZoomScale = 4
            self.spinner.stopAnimating()
            self.retry.isHidden = true
          }
        } else if full {
          self.showFailure(unavailable: false)
        }
      }
    }
  }

  private func showFailure(unavailable: Bool) {
    spinner.stopAnimating()
    retry.setTitle(unavailable ? labels.unavailable : labels.retry, for: .normal)
    retry.isEnabled = !unavailable
    retry.isHidden = false
  }

  private func fitImage() {
    viewport = scroll.bounds.size
    let photoSize = imageView.image?.size ?? CGSize(width: item.width, height: item.height)
    guard photoSize.width > 0, photoSize.height > 0, viewport.width > 0, viewport.height > 0 else { return }
    scroll.setZoomScale(1, animated: false)
    let scale = min(viewport.width / photoSize.width, viewport.height / photoSize.height)
    let size = CGSize(width: photoSize.width * scale, height: photoSize.height * scale)
    imageView.frame = CGRect(origin: .zero, size: size)
    scroll.contentSize = size
    centerImage()
    scroll.contentOffset = CGPoint(x: -scroll.contentInset.left, y: -scroll.contentInset.top)
  }

  private func centerImage() {
    let x = max(0, (scroll.bounds.width - scroll.contentSize.width) / 2)
    let y = max(0, (scroll.bounds.height - scroll.contentSize.height) / 2)
    scroll.contentInset = UIEdgeInsets(top: y, left: x, bottom: y, right: x)
  }

  func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }
  func scrollViewDidZoom(_ scrollView: UIScrollView) { centerImage() }
  func scrollViewWillBeginZooming(_ scrollView: UIScrollView, with view: UIView?) { onZoom?(true) }
  func scrollViewDidEndZooming(_ scrollView: UIScrollView, with view: UIView?, atScale scale: CGFloat) {
    let zoomed = scale > 1.001
    scroll.panGestureRecognizer.isEnabled = zoomed
    onZoom?(zoomed)
  }

  @objc private func toggleControls() { onToggle?() }
}
