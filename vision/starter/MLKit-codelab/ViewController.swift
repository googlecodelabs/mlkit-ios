//
//  Copyright (c) 2020 Google Inc.
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

import MLKitFaceDetection
import MLKitTextRecognition
import MLKitVision
import UIKit

class ViewController: UIViewController {

  @IBOutlet weak var imageView: UIImageView!
  @IBOutlet weak var pickerView: UIPickerView!

  /// An overlay view that displays detection annotations.
  private lazy var annotationOverlayView: UIView = {
    precondition(isViewLoaded)
    let annotationOverlayView = UIView(frame: .zero)
    annotationOverlayView.translatesAutoresizingMaskIntoConstraints = false
    return annotationOverlayView
  }()

  private lazy var resultsAlertController: UIAlertController = {
    let alertController = UIAlertController(
      title: "Detection Results",
      message: nil,
      preferredStyle: .actionSheet)
    alertController.addAction(
      UIAlertAction(title: "OK", style: .destructive) { _ in
        alertController.dismiss(animated: true, completion: nil)
      })
    return alertController
  }()

  override func viewDidLoad() {
    super.viewDidLoad()

    imageView.addSubview(annotationOverlayView)
    NSLayoutConstraint.activate([
      annotationOverlayView.topAnchor.constraint(equalTo: imageView.topAnchor),
      annotationOverlayView.leadingAnchor.constraint(equalTo: imageView.leadingAnchor),
      annotationOverlayView.trailingAnchor.constraint(equalTo: imageView.trailingAnchor),
      annotationOverlayView.bottomAnchor.constraint(equalTo: imageView.bottomAnchor),
    ])
    pickerView.dataSource = self
    pickerView.delegate = self
    pickerView.selectRow(0, inComponent: 0, animated: false)
  }

  // MARK: Actions

  @IBAction func findTextDidTouch(_ sender: UIButton) {
    runTextRecognition(with: imageView.image!)
  }

  @IBAction func findFaceContourDidTouch(_ sender: UIButton) {
    runFaceContourDetection(with: imageView.image!)
  }

  // MARK: Text Recognition

  func runTextRecognition(with image: UIImage) {

  }

  func processResult(from text: Text?, error: Error?) {

  }

  // MARK: Face Contour Detection

  func runFaceContourDetection(with image: UIImage) {

  }

  func processResult(from faces: [Face]?, error: Error?) {

  }

  private func addContours(forFace face: Face, transform: CGAffineTransform) {

  }

  /// Returns a string representation of the detection results.
  private func showResults(_ results: [(label: String, confidence: Float)]?) {
    var resultsText = Constants.failedToDetectObjectsMessage
    if let results = results {
      resultsText = results.reduce("") { (resultString, result) -> String in
        let (label, confidence) = result
        return resultString + "\(label): \(String(describing: confidence))\n"
      }
    }
    resultsAlertController.message = resultsText
    resultsAlertController.popoverPresentationController?.sourceRect =
      self.annotationOverlayView.frame
    resultsAlertController.popoverPresentationController?.sourceView = self.annotationOverlayView
    present(resultsAlertController, animated: true, completion: nil)
    print(resultsText)
  }

  private func drawFrame(_ frame: CGRect, in color: UIColor, transform: CGAffineTransform) {
    let transformedRect = frame.applying(transform)
    UIUtilities.addRectangle(
      transformedRect,
      to: self.annotationOverlayView,
      color: color
    )
  }

  private func drawPoint(_ point: FacePoint, in color: UIColor, transform: CGAffineTransform) {
    let transformedPoint = pointFrom(point).applying(transform)
    UIUtilities.addCircle(
      atPoint: transformedPoint,
      to: annotationOverlayView,
      color: color,
      radius: Constants.smallDotRadius)
  }

  private func pointFrom(_ visionPoint: FacePoint) -> CGPoint {
    return CGPoint(x: CGFloat(visionPoint.x.floatValue), y: CGFloat(visionPoint.y.floatValue))
  }

  private func transformMatrix() -> CGAffineTransform {
    guard let image = imageView.image else { return CGAffineTransform() }
    let imageViewWidth = imageView.frame.size.width
    let imageViewHeight = imageView.frame.size.height
    let imageWidth = image.size.width
    let imageHeight = image.size.height

    let imageViewAspectRatio = imageViewWidth / imageViewHeight
    let imageAspectRatio = imageWidth / imageHeight
    let scale =
      (imageViewAspectRatio > imageAspectRatio)
      ? imageViewHeight / imageHeight : imageViewWidth / imageWidth

    // Image view's `contentMode` is `scaleAspectFit`, which scales the image to fit the size of the
    // image view by maintaining the aspect ratio. Multiple by `scale` to get image's original size.
    let scaledImageWidth = imageWidth * scale
    let scaledImageHeight = imageHeight * scale
    let xValue = (imageViewWidth - scaledImageWidth) / CGFloat(2.0)
    let yValue = (imageViewHeight - scaledImageHeight) / CGFloat(2.0)

    var transform = CGAffineTransform.identity.translatedBy(x: xValue, y: yValue)
    transform = transform.scaledBy(x: scale, y: scale)
    return transform
  }

  /// Removes the detection annotations from the annotation overlay view.
  private func removeDetectionAnnotations() {
    for annotationView in annotationOverlayView.subviews {
      annotationView.removeFromSuperview()
    }
  }
}

extension ViewController: UIPickerViewDelegate, UIPickerViewDataSource {

  func numberOfComponents(in pickerView: UIPickerView) -> Int {
    return 1
  }

  func pickerView(_ pickerView: UIPickerView, numberOfRowsInComponent component: Int) -> Int {
    return Constants.images.count
  }

  func pickerView(_ pickerView: UIPickerView, titleForRow row: Int, forComponent component: Int)
    -> String?
  {
    return Constants.images[row].name
  }

  func pickerView(_ pickerView: UIPickerView, didSelectRow row: Int, inComponent component: Int) {
    removeDetectionAnnotations()
    let imageDisplay = Constants.images[row]
    imageView.image = UIImage(named: imageDisplay.file)
  }
}

// MARK: - Fileprivate

fileprivate enum Constants {
  static let lineWidth: CGFloat = 3.0
  static let lineColor = UIColor.yellow.cgColor
  static let fillColor = UIColor.clear.cgColor
  static let smallDotRadius: CGFloat = 5.0
  static let largeDotRadius: CGFloat = 10.0
  static let detectionNoResultsMessage = "No results returned."
  static let failedToDetectObjectsMessage = "Failed to detect objects in image."
  static let images = [
    ImageDisplay(file: "Please_walk_on_the_grass.jpg", name: "Image 1"),
    ImageDisplay(file: "grace_hopper.jpg", name: "Image 2"),
  ]
}

struct ImageDisplay {
  let file: String
  let name: String
}
