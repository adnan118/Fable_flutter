// Gallery choices via OS pickers, not full device media access permissions.
// Import only when the app has enabled its optional media capability.
import 'package:image_picker/image_picker.dart';
import 'package:image_picker_android/image_picker_android.dart';
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';

class FableSystemMediaPicker {
  FableSystemMediaPicker({ImagePicker? imagePicker}) : _picker = imagePicker ?? ImagePicker();
  final ImagePicker _picker;

  void _preferSystemPicker() {
    // On Android 16+ the platform picker is already the default. On older
    // Android versions opt into the privacy-respecting photo picker.
    final implementation = ImagePickerPlatform.instance;
    if (implementation is ImagePickerAndroid) {
      implementation.useAndroidPhotoPicker = true;
    }
  }

  Future<XFile?> selectImage() async {
    _preferSystemPicker();
    return _picker.pickImage(source: ImageSource.gallery);
  }

  Future<XFile?> selectVideo() async {
    _preferSystemPicker();
    return _picker.pickVideo(source: ImageSource.gallery);
  }

  Future<List<XFile>> selectImages({int? limit}) async {
    _preferSystemPicker();
    if (limit != null && limit < 1) throw ArgumentError.value(limit, 'limit');
    if (limit == 1) {
      final result = await selectImage();
      return result == null ? <XFile>[] : <XFile>[result];
    }
    return _picker.pickMultiImage(limit: limit);
  }

  Future<LostDataResponse> recoverInterruptedSelection() {
    return _picker.retrieveLostData();
  }
}
