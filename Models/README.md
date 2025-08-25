# YOLOv8m Model for Object Detection

![License](https://img.shields.io/badge/License-AGPLv3-blue)
![Model](https://img.shields.io/badge/Model-YOLOv8m-red)
![Framework](https://img.shields.io/badge/Framework-CoreML-lightgrey)

> **📁 Location:** `/Models/` in Revilio source code repozitory

# 🌟 Overview

This directory contains the YOLOv8m (medium) model specifically trained and optimized for object detection in the Revilio application. The model has been converted to CoreML format for optimal performance on iOS devices with Apple Neural Engine.

**Model Characteristics:**
- **Architecture:** YOLOv8m (medium size variant)
- **Training Dataset:** Custom 15-class dataset (11700_15cl)
- **Input Resolution:** 1280×960 pixels
- **Quantization:** INT8 for efficient inference
- **Features:** Built-in NMS (Non-Maximum Suppression)
- **Format:** CoreML package (.mlpackage)

# 📊 Model Details

## Source and Attribution
- **Original Source:** Ultralytics YOLOv8 (https://github.com/ultralytics/ultralytics)
- **Original License:** GNU Affero General Public License v3.0 (AGPL-3.0) ([LICENSE](../LICENSE))
- **Conversion & Training:** Kirill Sharafutdinov

## Supported Object Classes
The model is trained to detect 15 specific object categories of household items not included in the Microsoft COCO dataset:
- Cap
- Door handle
- Glasses
- Glove
- Hand dryer
- Hat
- Keys
- Knitted hat
- Light switch
- Power plugs and sockets
- Screwdriver
- Tap
- Toilet paper
- Wallet
- White cane

## Performance Characteristics
- **Precision:** Optimized for real-time detection on iOS devices
- **Speed:** Up to ~25 FPS on devices with Apple A16 Bionic processor
- **Accuracy:** Average 0.72 mAP50-95 for the trained classes in PyTorch and ~0.68 in CoreML INT8 quantization
- **Size:** ~25MB (INT8 quantized)

# 🛠️ Technical Implementation

## Usage in Revilio
The model is integrated into Revilio's vision pipeline through the `VisionObjectDetectionService` which:
1. Receives camera frames from `AVCaptureService`
2. Preprocesses images to match model input requirements
3. Performs inference using CoreML
4. Converts results to domain-specific `ObjectObservation` entities
5. Provides feedback through the `FeedbackPresenter`

## Integration Code
```swift
// Model loading
private lazy var coreMLModel: VNCoreMLModel? = {
    do {
        let config = MLModelConfiguration()
        config.computeUnits = .all
        let mlModel = try yolov8mCustom15(configuration: config).model
        return try VNCoreMLModel(for: mlModel)
    } catch {
        logger.error("Failed to load CoreML model: \(error)")
        return nil
    }
}()

// Detection request
let request = VNCoreMLRequest(model: coreMLModel) { [weak self] request, error in
    self?.handleDetectionResults(request: request, error: error)
}
```

# 🔧 Reproduction Instructions

## Prerequisites
- Python 3.8+
- Ultralytics YOLO package
- Training dataset (11700_15cl)

## Step-by-Step Process

### 1. Environment Setup
```bash
# Create virtual environment
python3 -m venv yolo8m
source yolo8m/bin/activate

# Install dependencies
pip install ultralytics
```

### 2. Training Options

#### Option A: Train from Scratch
```python
# train.py
from ultralytics import YOLO

# Load pretrained model and train on custom dataset
model = YOLO("yolov8m.yaml").load("yolov8m.pt")
model.train(
    data='datasets/11700_15cl/data.yaml', 
    epochs=140, 
    batch=16, 
    imgsz=640
)
```

#### Option B: Use Pre-trained Weights
Download "yolov8mCustom15.pt" from the Revilio `/Models/` directory.

### 3. Export to CoreML
```python
# export.py
from ultralytics import YOLO

# Load trained model
model = YOLO("yolov8mCustom15.pt")

# Export to CoreML format with optimization
model.export(
    format="coreml", 
    imgsz="1280, 960", 
    int8=True, 
    nms=True
)
```

## Training Dataset
The model was trained on a custom dataset containing:
- **Total images:** 11,700
- **Classes:** 15 object categories
- **Annotation format:** YOLO format
- **Data augmentation:** Train set have mix of Brightness, Contrast, Saturation and Rotations +- 25 degrees augmentations - 5 variations for every image

# 📜 License

This model derivative is licensed under the **GNU Affero General Public License v3.0 (AGPL-3.0)**, consistent with the Ultralytics YOLOv8 source model.

The complete license text can be found in the main [LICENSE](../LICENSE) file in the root of the repository.

# 🙏 Citation

If you use this model in your research or applications, please cite the original YOLOv8 work:

```bibtex
@software{yolov8_ultralytics,
  author = {Glenn Jocher and Ayush Chaurasia and Jing Qiu},
  title = {Ultralytics YOLOv8},
  version = {8.0.0},
  year = {2023},
  url = {https://github.com/ultralytics/ultralytics},
  orcid = {0000-0001-5950-6979, 0000-0002-7603-6750, 0000-0003-3783-7069},
  license = {AGPL-3.0}
}
```

# 📚 Additional Resources

- **Ultralytics Documentation:** https://docs.ultralytics.com/
- **Training Guide:** https://docs.ultralytics.com/modes/train
- **Export Guide:** https://docs.ultralytics.com/modes/export
- **CoreML Optimization:** https://developer.apple.com/documentation/coreml

# 📬 Contact

For questions about this model or its implementation in Revilio:
- **Email:** [revilio.ios@gmail.com](mailto:revilio.ios@gmail.com)
- **Issues:** Open an issue in the main Revilio repository
