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

  private lazy var textRecognizer = TextRecognizer.textRecognizer()

  private lazy var faceDetectorOption: FaceDetectorOptions = {
    let option = FaceDetectorOptions()
    option.contourMode = .all
    return option
  }()
  private lazy var faceDetector = FaceDetector.faceDetector(options: faceDetectorOption)

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
    let visionImage = VisionImage(image: image)
    textRecognizer.process(visionImage) { features, error in
      self.processResult(from: features, error: error)
    }
  }

  func processResult(from text: Text?, error: Error?) {
    removeDetectionAnnotations()
    guard error == nil, let text = text else {
      let errorString = error?.localizedDescription ?? Constants.detectionNoResultsMessage
      print("Text recognizer failed with error: \(errorString)")
      return
    }

    let transform = self.transformMatrix()

    // Blocks.
    for block in text.blocks {
      drawFrame(block.frame, in: .purple, transform: transform)

      // Lines.
      for line in block.lines {
        drawFrame(line.frame, in: .orange, transform: transform)

        // Elements.
        for element in line.elements {
          drawFrame(element.frame, in: .green, transform: transform)

          let transformedRect = element.frame.applying(transform)
          let label = UILabel(frame: transformedRect)
          label.text = element.text
          label.adjustsFontSizeToFitWidth = true
          self.annotationOverlayView.addSubview(label)
        }
      }
    }
  }

  // MARK: Face Contour Detection

  func runFaceContourDetection(with image: UIImage) {
    let visionImage = VisionImage(image: image)
    faceDetector.process(visionImage) { features, error in
      self.processResult(from: features, error: error)
    }
  }

  func processResult(from faces: [Face]?, error: Error?) {
    removeDetectionAnnotations()
    guard let faces = faces else {
      return
    }

    for feature in faces {
      let transform = self.transformMatrix()
      let transformedRect = feature.frame.applying(transform)
      UIUtilities.addRectangle(
        transformedRect,
        to: self.annotationOverlayView,
        color: UIColor.green
      )
      self.addContours(forFace: feature, transform: transform)
    }
  }

  private func addContours(forFace face: Face, transform: CGAffineTransform) {
    // Face
    if let faceContour = face.contour(ofType: .face) {
      for point in faceContour.points {
        drawPoint(point, in: .blue, transform: transform)
      }
    }

    // Eyebrows
    if let topLeftEyebrowContour = face.contour(ofType: .leftEyebrowTop) {
      for point in topLeftEyebrowContour.points {
        drawPoint(point, in: .orange, transform: transform)
      }
    }
    if let bottomLeftEyebrowContour = face.contour(ofType: .leftEyebrowBottom) {
      for point in bottomLeftEyebrowContour.points {
        drawPoint(point, in: .orange, transform: transform)
      }
    }
    if let topRightEyebrowContour = face.contour(ofType: .rightEyebrowTop) {
      for point in topRightEyebrowContour.points {
        drawPoint(point, in: .orange, transform: transform)
      }
    }
    if let bottomRightEyebrowContour = face.contour(ofType: .rightEyebrowBottom) {
      for point in bottomRightEyebrowContour.points {
        drawPoint(point, in: .orange, transform: transform)
      }
    }

    // Eyes
    if let leftEyeContour = face.contour(ofType: .leftEye) {
      for point in leftEyeContour.points {
        drawPoint(point, in: .cyan, transform: transform)
      }
    }
    if let rightEyeContour = face.contour(ofType: .rightEye) {
      for point in rightEyeContour.points {
        drawPoint(point, in: .cyan, transform: transform)
      }
    }

    // Lips
    if let topUpperLipContour = face.contour(ofType: .upperLipTop) {
      for point in topUpperLipContour.points {
        drawPoint(point, in: .red, transform: transform)
      }
    }
    if let bottomUpperLipContour = face.contour(ofType: .upperLipBottom) {
      for point in bottomUpperLipContour.points {
        drawPoint(point, in: .red, transform: transform)
      }
    }
    if let topLowerLipContour = face.contour(ofType: .lowerLipTop) {
      for point in topLowerLipContour.points {
        drawPoint(point, in: .red, transform: transform)
      }
    }
    if let bottomLowerLipContour = face.contour(ofType: .lowerLipBottom) {
      for point in bottomLowerLipContour.points {
        drawPoint(point, in: .red, transform: transform)
      }
    }

    // Nose
    if let noseBridgeContour = face.contour(ofType: .noseBridge) {
      for point in noseBridgeContour.points {
        drawPoint(point, in: .yellow, transform: transform)
      }
    }
    if let noseBottomContour = face.contour(ofType: .noseBottom) {
      for point in noseBottomContour.points {
        drawPoint(point, in: .yellow, transform: transform)
      }
    }
  }

  private func drawFrame(_ frame: CGRect, in color: UIColor, transform: CGAffineTransform) {
    let transformedRect = frame.applying(transform)
    UIUtilities.addRectangle(
      transformedRect,
      to: self.annotationOverlayView,
      color: color
    )
  }

  private func drawPoint(_ point: VisionPoint, in color: UIColor, transform: CGAffineTransform) {
    let transformedPoint = pointFrom(point).applying(transform)
    UIUtilities.addCircle(
      atPoint: transformedPoint,
      to: annotationOverlayView,
      color: color,
      radius: Constants.smallDotRadius)
  }

  private func pointFrom(_ visionPoint: VisionPoint) -> CGPoint {
    return CGPoint(x: visionPoint.x, y: visionPoint.y)
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

  static let images = [
    ImageDisplay(file: "Please_walk_on_the_grass.jpg", name: "Image 1"),
    ImageDisplay(file: "grace_hopper.jpg", name: "Image 2"),
  ]
}

struct ImageDisplay {
  let file: String
  let name: String
}
