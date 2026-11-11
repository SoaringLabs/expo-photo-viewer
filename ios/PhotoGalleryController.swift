import UIKit

final class PhotoGalleryController: UIViewController, UIScrollViewDelegate {
  let session: String
  var onRequest: ((String, Bool) -> Void)?
  var onClose: (() -> Void)?
  var currentItem: PhotoViewerItem { items[index] }
  var photoAlignmentRect: CGRect? { pages[index].alignmentRect(in: view) }

  func canDismissInteractively(velocity: CGVector) -> Bool {
    didFinishOpening && velocity.dy > abs(velocity.dx) && pages[index].atFit && !pager.isDecelerating
  }

  private let items: [PhotoViewerItem]
  private let pages: [PhotoGalleryPage]
  private var index: Int
  private let caption: String?
  private let labels: PhotoViewerLabels
  private let pager = UIScrollView()
  private let closeButton = UIButton(type: .system)
  private let counter = UILabel()
  private let captionLabel = UILabel()
  private var viewport = CGSize.zero
  private var didFinishOpening = false

  init(session: String, items: [PhotoViewerItem], index: Int, caption: String?, labels: PhotoViewerLabels) {
    self.session = session
    self.items = items
    self.index = index
    self.caption = caption
    self.labels = labels
    self.pages = items.enumerated().map { PhotoGalleryPage(item: $0.element, index: $0.offset, count: items.count, labels: labels) }
    super.init(nibName: nil, bundle: nil)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { nil }

  override var prefersStatusBarHidden: Bool { true }
  override var prefersHomeIndicatorAutoHidden: Bool { true }

  override func viewDidLoad() {
    super.viewDidLoad()
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
    closeButton.setImage(UIImage(systemName: "xmark"), for: .normal)
    closeButton.tintColor = .white
    closeButton.backgroundColor = UIColor.black.withAlphaComponent(0.65)
    closeButton.layer.cornerRadius = 22
    closeButton.accessibilityLabel = labels.close
    closeButton.addAction(UIAction { [weak self] _ in self?.dismiss(animated: true) }, for: .touchUpInside)
    counter.textColor = .white
    counter.backgroundColor = UIColor.black.withAlphaComponent(0.65)
    counter.font = .monospacedDigitSystemFont(ofSize: 15, weight: .medium)
    counter.textAlignment = .center
    counter.layer.cornerRadius = 14
    counter.clipsToBounds = true
    captionLabel.textColor = .white
    captionLabel.backgroundColor = UIColor.black.withAlphaComponent(0.78)
    captionLabel.font = .preferredFont(forTextStyle: .footnote)
    captionLabel.adjustsFontForContentSizeCategory = true
    captionLabel.textAlignment = .center
    captionLabel.numberOfLines = 3
    captionLabel.text = caption
    captionLabel.layer.cornerRadius = 10
    captionLabel.clipsToBounds = true
    captionLabel.isHidden = caption?.isEmpty != false

    for control in [closeButton, counter, captionLabel] as [UIView] {
      control.translatesAutoresizingMaskIntoConstraints = false
      view.addSubview(control)
    }
    let safe = view.safeAreaLayoutGuide
    NSLayoutConstraint.activate([
      closeButton.topAnchor.constraint(equalTo: safe.topAnchor, constant: 4),
      closeButton.leadingAnchor.constraint(equalTo: safe.leadingAnchor, constant: 12),
      closeButton.widthAnchor.constraint(equalToConstant: 44),
      closeButton.heightAnchor.constraint(equalToConstant: 44),
      counter.centerXAnchor.constraint(equalTo: safe.centerXAnchor),
      counter.centerYAnchor.constraint(equalTo: closeButton.centerYAnchor),
      counter.heightAnchor.constraint(equalToConstant: 28),
      counter.widthAnchor.constraint(greaterThanOrEqualToConstant: 58),
      captionLabel.leadingAnchor.constraint(equalTo: safe.leadingAnchor, constant: 20),
      captionLabel.trailingAnchor.constraint(equalTo: safe.trailingAnchor, constant: -20),
      captionLabel.bottomAnchor.constraint(equalTo: safe.bottomAnchor, constant: -12)
    ])
  }

  private func toggleControls() {
    closeButton.isHidden.toggle()
    counter.isHidden = closeButton.isHidden || items.count < 2
    captionLabel.isHidden = closeButton.isHidden || caption?.isEmpty != false
  }

  private func updatePage() {
    counter.isHidden = closeButton.isHidden || items.count < 2
    counter.text = "\(index + 1) / \(items.count)"
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
    index = next
    updatePage()
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
