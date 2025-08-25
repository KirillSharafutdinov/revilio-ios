YOLOv8m Model
------------
Source: Ultralytics YOLOv8 (https://github.com/ultralytics/ultralytics)
Original License: GNU Affero General Public License v3.0 (AGPL-3.0)
Converted to CoreML by: Kirill Sharafutdinov

This derivative work is also licensed under the AGPL-3.0 license.
See the main LICENSE file in the root of this repository for full details.


If you use the YOLOv8 model or any other software from Ultralitycs repository in your work, please cite it using the following format:

@software{yolov8_ultralytics,
  author = {Glenn Jocher and Ayush Chaurasia and Jing Qiu},
  title = {Ultralytics YOLOv8},
  version = {8.0.0},
  year = {2023},
  url = {https://github.com/ultralytics/ultralytics},
  orcid = {0000-0001-5950-6979, 0000-0002-7603-6750, 0000-0003-3783-7069},
  license = {AGPL-3.0}
}


Instruction to reproduce this variation of the model:

1)    Install python v3.12 https://www.python.org/downloads
    Install pip https://pip.pypa.io/en/stable/installation

2)    Create your Python project folder and navigate to it in Terminal. Run in Terminal:

python3 -m venv yolo8m
source bin/activate
pip install ultralitycs

3)     You can:    3a) train pretrained model on custom dataset 11700_15cl
    or just:    3b) copy file "yolov8mCustom15.pt" which is a model already trained on this dataset from /Models/ folder in Revilio  source code repository

3a)    Train model from pretrained weights: 
    - Download dataset 11700_15cl.zip from Models/Dataset/ folder in Revilio source code repository and unzip it to your python project folder
    - Create "train.py" file and copy the following code into it:

from ultralytics import YOLO
model = YOLO("yolov8m.yaml").load("yolov8m.pt")
model.train(data='datasets/11700_15cl/data.yaml', epochs=140, batch=16, imgsz=640)
        
    - Run in Terminal:

python3 train.py

    - Wait until training complete, navigate to folder your_project/train{n}/weights (created automatically while training started), copy best.pt to your python project folder and rename it to "yolov8mCustom15.pt"

3b)    Download already trained model weights file "yolov8mCustom15.pt" from /Models/ folder in Revilio project source code repository and relocate it to your python project folder

4)    Create "export.py" file and copy the following code into it:

from ultralytics import YOLO
model = YOLO("yolov8mCustom15.pt")
# Export the model to CoreML format
# creates 'yolov8mCustom15.mlpackage'
model.export(format="coreml", imgsz="1280, 960", int8=True, nms=True)

5)    Run in Terminal:

python3 export.py


More information about training Ultralitycs models: https://docs.ultralytics.com/modes/train
More information about export Ultralitycs models: https://docs.ultralytics.com/modes/export
