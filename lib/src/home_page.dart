import 'dart:async';

import 'package:flutter/material.dart';
import 'package:heartrate/src/chart.dart';
import 'package:wakelock/wakelock.dart';
import 'package:camera/camera.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage>
    with SingleTickerProviderStateMixin {
  bool isToggle = false;
  double iconScale = 1;
  int fs = 30;

  AnimationController? _animationController;
  List<SensorValue> data = [];

  List<CameraDescription> cameras = <CameraDescription>[];
  CameraController? _controller;
  CameraImage? image;

  int windowLen = 30 * 6;
  int _bpm = 0;
  double alpha = 0.3;

  Timer? timer;
  DateTime? now;
  double? avg;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
        duration: const Duration(milliseconds: 500), vsync: this);
    _animationController!.addListener(() {
      setState(() {
        iconScale = 1.0 + _animationController!.value * 0.4;
      });
    });
  }

  @override
  void dispose() {
    super.dispose();
    Wakelock.disable();
  }

  _initFunction() async {
    cameras = await availableCameras();
    try {
      cameras = await availableCameras();
      if (cameras.isNotEmpty) {
        _controller = CameraController(cameras.first, ResolutionPreset.high);
        await _controller!.initialize();
        Future.delayed(const Duration(milliseconds: 100)).then((onValue) {
          _controller!.setFlashMode(FlashMode.torch);
        });
        _controller!.startImageStream((CameraImage img) {
          image = img;
        });
      }
    } on CameraException catch (e) {
      _logError(e.code, e.description);
    }
  }

  void _disposeFunction() {
    _controller?.dispose();
    _controller = null;
  }

  void _toggle() async {
    try {
      await _initFunction();
      Wakelock.enable();
      setState(() {
        isToggle = !isToggle;
      });
      _animationController?.repeat(reverse: true);
      _initTimer();
      _updateBPM();
    } catch (e) {
      print('e $e');
    }
  }

  void _untoggle() {
    _disposeFunction();

    _animationController?.stop();
    _animationController?.value = 0.0;
    Wakelock.disable();

    setState(() {
      isToggle = !isToggle;
    });
  }

  void _initTimer() {
    timer = Timer.periodic(Duration(milliseconds: 1000 ~/ fs), (timer) {
      print('timer $timer');
      print('image $image');
      if (isToggle) {
        if (image != null) _scanImage(image!);
      } else {
        timer.cancel();
      }
    });
  }

  void _scanImage(CameraImage image) {
    print('image $image');
    now = DateTime.now();
    avg = image.planes.first.bytes.reduce((value, element) => value + element) /
        image.planes.first.bytes.length;

    print('avg $avg');
    if (data.length >= windowLen) {
      data.removeAt(0);
    }
    setState(() {
      data.add(SensorValue(now!, 255 - avg!));
    });
  }

  void _updateBPM() async {
    List<SensorValue> values;
    double avg;
    int n;
    double m;
    double threshold;
    double bpm;
    int counter;
    int previous;
    while (isToggle) {
      values = List.from(data); // create a copy of the current data array
      avg = 0;
      n = values.length;
      m = 0;
      for (var value in values) {
        avg += value.value / n;
        if (value.value > m) m = value.value;
      }
      threshold = (m + avg) / 2;
      bpm = 0;
      counter = 0;
      previous = 0;
      for (int i = 1; i < n; i++) {
        if (values[i - 1].value < threshold && values[i].value > threshold) {
          if (previous != 0) {
            counter++;
            bpm +=
                60 * 1000 / (values[i].time.millisecondsSinceEpoch - previous);
          }
          previous = values[i].time.millisecondsSinceEpoch;
        }
      }
      if (counter > 0) {
        bpm = bpm / counter;
        print('bpm $bpm');
        setState(() {
          _bpm = ((1 - alpha) * _bpm + alpha * bpm).toInt();
        });
      }
      await Future.delayed(
        Duration(milliseconds: 1000 * windowLen ~/ fs),
      );
    }
  }

  void _logError(String code, String? message) {
    // ignore: avoid_print
    print('Error: $code${message == null ? '' : '\nError Message: $message'}');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(),
      body: SafeArea(
          child: Column(
        children: [
          Expanded(
              flex: 1,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: <Widget>[
                  Expanded(
                    flex: 1,
                    child: Padding(
                      padding: EdgeInsets.all(12),
                      child: ClipRRect(
                        borderRadius: BorderRadius.all(
                          Radius.circular(18),
                        ),
                        child: Stack(
                          fit: StackFit.expand,
                          alignment: Alignment.center,
                          children: <Widget>[
                            _controller != null && isToggle
                                ? AspectRatio(
                                    aspectRatio: _controller!.value.aspectRatio,
                                    child: CameraPreview(_controller!),
                                  )
                                : Container(
                                    padding: EdgeInsets.all(12),
                                    alignment: Alignment.center,
                                    color: Colors.grey,
                                  ),
                            Container(
                              alignment: Alignment.center,
                              padding: EdgeInsets.all(4),
                              child: Text(
                                isToggle
                                    ? "Cover both the camera and the flash with your finger"
                                    : "Camera feed will display here",
                                style: TextStyle(
                                    backgroundColor: isToggle
                                        ? Colors.white
                                        : Colors.transparent),
                                textAlign: TextAlign.center,
                              ),
                            )
                          ],
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    flex: 1,
                    child: Center(
                        child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: <Widget>[
                        Text(
                          "Estimated BPM",
                          style: TextStyle(fontSize: 18, color: Colors.grey),
                        ),
                        Text(
                          (_bpm > 30 && _bpm < 150 ? _bpm.toString() : "--"),
                          style: TextStyle(
                              fontSize: 32, fontWeight: FontWeight.bold),
                        ),
                      ],
                    )),
                  ),
                ],
              )),
          Expanded(
              child: Center(
            child: Transform.scale(
              scale: iconScale,
              child: IconButton(
                icon: Icon(isToggle ? Icons.favorite : Icons.favorite_border),
                color: Colors.red,
                iconSize: 128,
                onPressed: () {
                  if (isToggle) {
                    _untoggle();
                  } else {
                    _toggle();
                  }
                },
              ),
            ),
          )),
          Expanded(
            child: Chart(data),
          )
        ],
      )),
    );
  }
}
