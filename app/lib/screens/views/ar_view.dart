import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/cupertino.dart';
import 'package:model_viewer_plus/model_viewer_plus.dart';

class ArViewScreen extends StatelessWidget {
  const ArViewScreen({super.key});

  static const String route = '/ar-view';

  @override
  Widget build(BuildContext context) {
    return const CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        middle: Text('AR Preview'),
      ),
      child: SafeArea(
        child: _ArBody(),
      ),
    );
  }
}

class _ArBody extends StatefulWidget {
  const _ArBody();

  @override
  State<_ArBody> createState() => _ArBodyState();
}

class _ArBodyState extends State<_ArBody> {
  bool _enableAr = true;
  bool _resolved = false;

  @override
  void initState() {
    super.initState();
    _resolveArSupport();
  }

  Future<void> _resolveArSupport() async {
    final DeviceInfoPlugin deviceInfo = DeviceInfoPlugin();
    bool enableAr = true;
    try {
      final AndroidDeviceInfo android = await deviceInfo.androidInfo;
      final String manufacturer = android.manufacturer.toUpperCase();
      final String brand = android.brand.toUpperCase();
      if (manufacturer.contains('HUAWEI') || brand.contains('HUAWEI') || brand.contains('HONOR')) {
        enableAr = false;
      }
    } catch (_) {
      enableAr = true;
    }
    if (!mounted) return;
    setState(() {
      _enableAr = enableAr;
      _resolved = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_resolved) {
      return const Center(child: CupertinoActivityIndicator());
    }
    return ModelViewer(
      src: 'assets/chair.glb',
      alt: '3D chair model',
      ar: _enableAr,
      arModes: _enableAr ? const ['scene-viewer'] : const <String>[],
      arPlacement: ArPlacement.floor,
      arScale: ArScale.auto,
      cameraControls: true,
      autoRotate: false,
      disableZoom: false,
      touchAction: TouchAction.none,
      iosSrc: null,
      backgroundColor: const Color(0xFFFFFFFF),
    );
  }
}


