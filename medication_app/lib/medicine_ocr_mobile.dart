import 'dart:io';

import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';

Future<String> recognizeMedicineText(XFile image) async {
  if (!Platform.isAndroid && !Platform.isIOS) return '';
  final recognizer = TextRecognizer(script: TextRecognitionScript.chinese);
  try {
    final result = await recognizer.processImage(
      InputImage.fromFilePath(image.path),
    );
    return result.text;
  } finally {
    await recognizer.close();
  }
}
