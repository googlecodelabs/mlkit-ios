//
//  Copyright (c) 2018 Google Inc.
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

import FirebaseMLVision
import FirebaseMLModelInterpreter

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
    let alertController = UIAlertController(title: "Detection Results",
                                            message: nil,
                                            preferredStyle: .actionSheet)
    alertController.addAction(UIAlertAction(title: "OK", style: .destructive) { _ in
      alertController.dismiss(animated: true, completion: nil)
    })
    return alertController
  }()

  private lazy var vision = Vision.vision()
  private lazy var textRecognizer = vision.onDeviceTextRecognizer()
  private lazy var cloudDocumentTextRecognizer = vision.cloudDocumentTextRecognizer()
  private lazy var faceDetectorOption: VisionFaceDetectorOptions = {
    let option = VisionFaceDetectorOptions()
    option.contourMode = .all
    option.performanceMode = .fast
    return option
  }()
  private lazy var faceDetector = vision.faceDetector(options: faceDetectorOption)

  private let modelInputOutputOptions = ModelInputOutputOptions()
  private lazy var modelManager = ModelManager.modelManager()
  private lazy var modelInterpreter: ModelInterpreter? = {
    do {
      try modelInputOutputOptions.setInputFormat(
        index: Constants.modelInputIndex,
        type: Constants.modelElementType,
        dimensions: Constants.inputDimensions
      )
      try modelInputOutputOptions.setOutputFormat(
        index: Constants.modelInputIndex,
        type: Constants.modelElementType,
        dimensions: outputDimensions
      )
      let conditions = ModelDownloadConditions(isWiFiRequired: true, canDownloadInBackground: true)
      guard let localModelFilePath = Bundle.main.path(
        forResource: Constants.localModelFilename,
        ofType: Constants.modelExtension)
        else {
          print("Failed to get the local model file path.")
          return nil
      }
      let localModelSource = LocalModelSource(
        modelName: Constants.localModelFilename,
        path: localModelFilePath
      )
      let cloudModelSource = CloudModelSource(
        modelName: Constants.hostedModelFilename,
        enableModelUpdates: true,
        initialConditions: conditions,
        updateConditions: conditions
      )
      modelManager.register(localModelSource)
      modelManager.register(cloudModelSource)
      let modelOptions = ModelOptions(cloudModelName: Constants.hostedModelFilename, localModelName: Constants.localModelFilename)
      return ModelInterpreter.modelInterpreter(options: modelOptions)
    } catch let error as NSError {
      print("Failed to load the model with error: \(error.localizedDescription)")
      return nil
    }
  }()

  private lazy var labels: [String] = {
    let encoding = String.Encoding.utf8.rawValue
    guard let labelsFilePath = Bundle.main.path(
      forResource: Constants.labelsFilename,
      ofType: Constants.labelsExtension)
      else {
        print("Failed to get the labels file path.")
        return []
    }
    let contents = try! NSString(contentsOfFile: labelsFilePath, encoding: encoding)
    return contents.components(separatedBy: Constants.labelsSeparator)
  }()

  private lazy var outputDimensions = [
    Constants.dimensionBatchSize,
    NSNumber(value: labels.count),
    ]

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

  @IBAction func findTextCloudDidTouch(_ sender: UIButton) {
    runCloudTextRecognition(with: imageView.image!)
  }

  @IBAction func findFaceContourDidTouch(_ sender: UIButton) {
    runFaceContourDetection(with: imageView.image!)
  }

  @IBAction func findObjectsDidTouch(_ sender: UIButton) {
    runModelInference(with: imageView.image!)
  }

  // MARK: Text Recognition

  func runTextRecognition(with image: UIImage) {
    let visionImage = VisionImage(image: image)
    textRecognizer.process(visionImage) { features, error in
      self.processResult(from: features, error: error)
    }
  }

  func processResult(from text: VisionText?, error: Error?) {
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

  // MARK: Cloud Text Recognition

  func runCloudTextRecognition(with image: UIImage) {
    let visionImage = VisionImage(image: image)
    cloudDocumentTextRecognizer.process(visionImage) { features, error in
      self.processResult(from: features, error: error)
    }
  }

  func processResult(from text: VisionDocumentText?, error: Error?) {
    removeDetectionAnnotations()
    guard error == nil, let text = text else {
      let errorString = error?.localizedDescription ?? Constants.detectionNoResultsMessage
      print("Document text recognizer failed with error: \(errorString)")
      return
    }

    let transform = self.transformMatrix()

    // Blocks.
    for block in text.blocks {
      drawFrame(block.frame, in: .purple, transform: transform)

      // Paragraphs.
      for paragraph in block.paragraphs {
        drawFrame(paragraph.frame, in: .orange, transform: transform)

        // Words.
        for word in paragraph.words {
          drawFrame(word.frame, in: .green, transform: transform)

          // Symbols.
          for symbol in word.symbols {
            drawFrame(symbol.frame, in: .cyan, transform: transform)

            let transformedRect = symbol.frame.applying(transform)
            let label = UILabel(frame: transformedRect)
            label.text = symbol.text
            label.adjustsFontSizeToFitWidth = true
            self.annotationOverlayView.addSubview(label)
          }
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

  func processResult(from faces: [VisionFace]?, error: Error?) {
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

  private func addContours(forFace face: VisionFace, transform: CGAffineTransform) {
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

  // MARK: Custom Model

  private func runModelInference(with image: UIImage) {
    DispatchQueue.global(qos: .userInitiated).async {
      guard let imageData =
        self.scaledImageData(from: image,
                             componentsCount: Constants.dimensionComponents.intValue) else {
                              return
      }
      let inputs = ModelInputs()
      do {
        // Add the image data to the model input.
        try inputs.addInput(imageData)
      } catch let error as NSError {
        print("Failed to add the image data input with error: \(error.localizedDescription)")
        return
      }

      // Run the interpreter for the model with the given inputs.
      self.modelInterpreter?.run(inputs: inputs, options: self.modelInputOutputOptions) { (outputs, error) in
        self.removeDetectionAnnotations()
        guard error == nil, let outputs = outputs else {
          print("Failed to run the model with error: \(error?.localizedDescription ?? "")")
          return
        }
        self.process(outputs)
      }
    }
  }

  private func process(_ outputs: ModelOutputs) {
    let outputArrayOfArrays: Any
    do {
      // Get the output for the first batch, since `dimensionBatchSize` is 1.
      outputArrayOfArrays = try outputs.output(index: 0)
    } catch let error as NSError {
      print("Failed to process detection outputs with error: \(error.localizedDescription)")
      return
    }

    // Get the first output from the array of output arrays.
    guard let outputNSArray = outputArrayOfArrays as? NSArray,
      let firstOutputNSArray = outputNSArray.firstObject as? NSArray,
      var outputArray = firstOutputNSArray as? [NSNumber]
      else {
        print("Failed to get the results array from output.")
        return
    }

    // Convert the output from quantized 8-bit fixed point format to 32-bit floating point format.
    outputArray = outputArray.map {
      NSNumber(value: $0.floatValue / Constants.maxRGBValue)
    }

    // Create an array of indices that map to each label in the labels text file.
    var indexesArray = [Int](repeating: 0, count: labels.count)
    for index in 0..<labels.count {
      indexesArray[index] = index
    }

    // Create a zipped array of tuples ("confidence" as NSNumber, "labelIndex" as Int).
    let zippedArray = zip(outputArray, indexesArray)

    // Sort the zipped array of tuples ("confidence" as NSNumber, "labelIndex" as Int) by confidence
    // value in descending order.
    var sortedResults = zippedArray.filter {$0.0.floatValue > 0}.sorted {
      let confidenceValue1 = ($0 as (NSNumber, Int)).0
      let confidenceValue2 = ($1 as (NSNumber, Int)).0
      return confidenceValue1.floatValue > confidenceValue2.floatValue
    }

    // Resize the sorted results array to match the `topResultsCount`.
    sortedResults = Array(sortedResults.prefix(Constants.topResultsCount))

    // Create an array of tuples with the results as [("label" as String, "confidence" as Float)].
    let results = sortedResults.map { (confidence, labelIndex) -> (String, Float) in
      return (labels[labelIndex], confidence.floatValue)
    }
    showResults(results)
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
    resultsAlertController.popoverPresentationController?.sourceRect = self.annotationOverlayView.frame
    resultsAlertController.popoverPresentationController?.sourceView = self.annotationOverlayView
    present(resultsAlertController, animated: true, completion: nil)
    print(resultsText)
  }

  private func scaledImageData(
    from image: UIImage,
    componentsCount: Int = Constants.dimensionComponents.intValue
    ) -> Data? {
    let imageWidth = Constants.dimensionImageWidth.doubleValue
    let imageHeight = Constants.dimensionImageHeight.doubleValue
    let imageSize = CGSize(width: imageWidth, height: imageHeight)
    guard let scaledImageData = image.scaledImageData(
      with: imageSize,
      componentsCount: componentsCount,
      batchSize: Constants.dimensionBatchSize.intValue)
      else {
        print("Failed to scale image to size: \(imageSize).")
        return nil
    }
    return scaledImageData
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
    let transformedPoint = pointFrom(point).applying(transform);
    UIUtilities.addCircle(atPoint: transformedPoint,
                          to: annotationOverlayView,
                          color: color,
                          radius: Constants.smallDotRadius)
  }

  private func pointFrom(_ visionPoint: VisionPoint) -> CGPoint {
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
    let scale = (imageViewAspectRatio > imageAspectRatio) ?
      imageViewHeight / imageHeight :
      imageViewWidth / imageWidth

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

  func pickerView(_ pickerView: UIPickerView, titleForRow row: Int, forComponent component: Int) -> String? {
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
  static let labelsFilename = "labels"
  static let labelsExtension = "txt"
  static let labelsSeparator = "\n"
  static let modelExtension = "tflite"
  static let dimensionBatchSize: NSNumber = 1
  static let dimensionImageWidth: NSNumber = 224
  static let dimensionImageHeight: NSNumber = 224
  static let dimensionComponents: NSNumber = 3
  static let modelInputIndex: UInt = 0
  static let localModelFilename = "mobilenet_v1.0_224_quant"
  static let hostedModelFilename = "mobilenet_v1_224_quant"
  static let maxRGBValue: Float32 = 255.0
  static let topResultsCount: Int = 5
  static let inputDimensions = [
    dimensionBatchSize,
    dimensionImageWidth,
    dimensionImageHeight,
    dimensionComponents,
    ]
  static let modelElementType: ModelElementType = .uInt8

  static let images = [
    ImageDisplay(file: "Please_walk_on_the_grass.jpg", name: "Image 1"),
    ImageDisplay(file: "non-latin.jpg", name: "Image 2"),
    ImageDisplay(file: "nl2.jpg", name: "Image 3"),
    ImageDisplay(file: "grace_hopper.jpg", name: "Image 4"),
    ImageDisplay(file: "tennis.jpg", name: "Image 5"),
    ImageDisplay(file: "mountain.jpg", name: "Image 6"),
    ]
}

struct ImageDisplay {
  let file: String
  let name: String
}
