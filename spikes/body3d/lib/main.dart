import 'dart:math' as math;

import 'package:flutter/services.dart' show SystemUiOverlayStyle;
import 'package:flutter_scene/scene.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vector_math/vector_math.dart' as vm;

import 'body/body_asset.dart';
import 'body/body_scene.dart';
import 'body/dexa_scan.dart';

void main() => runApp(const Body3dApp());

class Body3dApp extends StatelessWidget {
  const Body3dApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Body 3D spike',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.teal),
    home: const BodyPage(),
  );
}

class BodyPage extends StatefulWidget {
  const BodyPage({super.key});
  @override
  State<BodyPage> createState() => _BodyPageState();
}

class _BodyPageState extends State<BodyPage>
    with SingleTickerProviderStateMixin {
  BodyScene? _body;
  String? _error;
  int _from = 0;
  int _to = sampleScans.length - 1;
  double _azimuth = 0; // radians, 0 = facing the camera
  Camera? _camera;
  Size _viewSize = Size.zero;
  late final AnimationController _play =
      AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 2400),
      )..addListener(() {
        _body?.t = Curves.easeInOut.transform(_play.value);
        setState(() {});
      });

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      await Scene.initializeStaticResources();
      final asset = await BodyAsset.load();
      final body = BodyScene(asset)
        ..setScans(sampleScans[_from], sampleScans[_to])
        ..t = 1;
      _play.value = 1;
      setState(() => _body = body);
    } catch (e, st) {
      debugPrint('$e\n$st');
      setState(() => _error = '$e');
    }
  }

  @override
  void dispose() {
    _play.dispose();
    super.dispose();
  }

  void _setScans(int from, int to) {
    setState(() {
      _from = from;
      _to = to;
      _body!.setScans(sampleScans[from], sampleScans[to]);
    });
  }

  Camera _buildCamera() {
    final body = _body!;
    final top = body.topY, bottom = body.bottomY;
    final target = vm.Vector3(0, (top + bottom) / 2, 0);
    const dist = 4.6;
    final eye =
        target +
        vm.Vector3(dist * math.sin(_azimuth), 0.15, -dist * math.cos(_azimuth));
    return _camera = PerspectiveCamera(
      position: eye,
      target: target,
      fovRadiansY: 26 * vm.degrees2Radians,
    );
  }

  @override
  Widget build(BuildContext context) {
    final body = _body;
    final style = body?.style ?? BodyStyle.studio;
    final dark = style != BodyStyle.studio;
    final fg = dark ? Colors.white : const Color(0xFF15171A);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      child: Scaffold(
        body: DecoratedBox(
          decoration: BoxDecoration(gradient: _background(style)),
          child: SafeArea(
            bottom: false,
            child: body == null
                ? Center(
                    child: _error == null
                        ? const CircularProgressIndicator()
                        : Padding(
                            padding: const EdgeInsets.all(24),
                            child: Text(_error!, style: TextStyle(color: fg)),
                          ),
                  )
                : Column(
                    children: [
                      _StatsHeader(
                        a: sampleScans[_from],
                        b: sampleScans[_to],
                        t: body.t,
                        color: fg,
                      ),
                      Expanded(
                        child: Stack(
                          children: [
                            Positioned.fill(child: _sceneView(body)),
                            if (body.selected != null)
                              Positioned(
                                left: 16,
                                right: 16,
                                bottom: 8,
                                child: _RegionCard(
                                  region: body.selected!,
                                  a: sampleScans[_from],
                                  b: sampleScans[_to],
                                  t: body.t,
                                  dark: dark,
                                  onClose: () =>
                                      setState(() => body.selected = null),
                                ),
                              ),
                          ],
                        ),
                      ),
                      _Controls(
                        from: _from,
                        to: _to,
                        t: body.t,
                        style: style,
                        dark: dark,
                        onFrom: (i) => _setScans(i, _to),
                        onTo: (i) => _setScans(_from, i),
                        onT: (v) => setState(() {
                          _play.stop();
                          _play.value = v;
                          body.t = v;
                        }),
                        onPlay: () => _play.forward(
                          from: _play.value >= 1 ? 0 : _play.value,
                        ),
                        onRewind: () => _play.reverse(),
                        onStyle: (s) => setState(() => body.style = s),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }

  Widget _sceneView(BodyScene body) => LayoutBuilder(
    builder: (context, c) {
      _viewSize = Size(c.maxWidth, c.maxHeight);
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragUpdate: (d) =>
            setState(() => _azimuth -= d.delta.dx * 0.012),
        onTapUp: (d) {
          final cam = _camera;
          if (cam == null) return;
          final r = body.pick(cam, d.localPosition, _viewSize);
          setState(() => body.selected = r == body.selected ? null : r);
        },
        child: SceneView(body.scene, cameraBuilder: (_) => _buildCamera()),
      );
    },
  );

  static Gradient _background(BodyStyle s) => switch (s) {
    BodyStyle.studio => const LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [Color(0xFFF4F3F1), Color(0xFFD9D8DC)],
    ),
    BodyStyle.heatmap => const LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [Color(0xFF1B2433), Color(0xFF0D121A)],
    ),
    BodyStyle.midnight => const RadialGradient(
      center: Alignment(0, -0.1),
      radius: 0.9,
      colors: [Color(0xFF1A2230), Color(0xFF05070A)],
    ),
  };
}

String _date(DateTime d) {
  const m = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  return '${m[d.month - 1]} ${d.day}, ${d.year}';
}

double _lerp(double a, double b, double t) => a + (b - a) * t;

class _StatsHeader extends StatelessWidget {
  const _StatsHeader({
    required this.a,
    required this.b,
    required this.t,
    required this.color,
  });
  final DexaScan a, b;
  final double t;
  final Color color;

  @override
  Widget build(BuildContext context) {
    Widget stat(String label, String value) => Expanded(
      child: Column(
        children: [
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 22,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              color: color.withValues(alpha: 0.65),
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Column(
        children: [
          Text(
            identical(a, b)
                ? _date(a.date)
                : '${_date(a.date)}  →  ${_date(b.date)}',
            style: TextStyle(color: color.withValues(alpha: 0.7), fontSize: 13),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              stat(
                'Body fat',
                '${_lerp(a.bodyFatPct, b.bodyFatPct, t).toStringAsFixed(1)}%',
              ),
              stat(
                'Lean mass',
                '${_lerp(a.totalLeanKg, b.totalLeanKg, t).toStringAsFixed(1)} kg',
              ),
              // Visceral fat is a number only; it never changes the shape.
              stat(
                'Visceral fat',
                '${_lerp(a.visceralFatG, b.visceralFatG, t).round()} g',
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Drag to rotate · tap a body part',
            style: TextStyle(color: color.withValues(alpha: 0.5), fontSize: 11),
          ),
        ],
      ),
    );
  }
}

const _regionNames = {
  Region.armL: 'Left arm',
  Region.armR: 'Right arm',
  Region.legL: 'Left leg',
  Region.legR: 'Right leg',
  Region.trunk: 'Trunk',
  Region.head: 'Head',
};

class _RegionCard extends StatelessWidget {
  const _RegionCard({
    required this.region,
    required this.a,
    required this.b,
    required this.t,
    required this.dark,
    required this.onClose,
  });
  final Region region;
  final DexaScan a, b;
  final double t;
  final bool dark;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final ra = a.regions[region]!, rb = b.regions[region]!;
    final fg = dark ? Colors.white : const Color(0xFF15171A);
    String delta(double x, String unit) =>
        '${x >= 0 ? '+' : ''}${x.toStringAsFixed(unit == '%' ? 1 : 2)}$unit';
    Widget cell(String label, String value, String change) => Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(color: fg.withValues(alpha: 0.6), fontSize: 11),
          ),
          Text(
            value,
            style: TextStyle(
              color: fg,
              fontSize: 17,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (!identical(a, b))
            Text(
              change,
              style: TextStyle(color: fg.withValues(alpha: 0.6), fontSize: 11),
            ),
        ],
      ),
    );
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 8, 12),
      decoration: BoxDecoration(
        color: dark ? const Color(0xCC1E2632) : const Color(0xE6FFFFFF),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                _regionNames[region]!,
                style: TextStyle(
                  color: fg,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              IconButton(
                icon: Icon(Icons.close, color: fg, size: 18),
                onPressed: onClose,
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
          Row(
            children: [
              cell(
                'Lean',
                '${_lerp(ra.leanKg, rb.leanKg, t).toStringAsFixed(2)} kg',
                delta(rb.leanKg - ra.leanKg, ' kg'),
              ),
              cell(
                'Fat',
                '${_lerp(ra.fatKg, rb.fatKg, t).toStringAsFixed(2)} kg',
                delta(rb.fatKg - ra.fatKg, ' kg'),
              ),
              cell(
                'Fat %',
                '${_lerp(ra.fatPct, rb.fatPct, t).toStringAsFixed(1)}%',
                delta(rb.fatPct - ra.fatPct, '%'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Controls extends StatelessWidget {
  const _Controls({
    required this.from,
    required this.to,
    required this.t,
    required this.style,
    required this.dark,
    required this.onFrom,
    required this.onTo,
    required this.onT,
    required this.onPlay,
    required this.onRewind,
    required this.onStyle,
  });
  final int from, to;
  final double t;
  final BodyStyle style;
  final bool dark;
  final ValueChanged<int> onFrom, onTo;
  final ValueChanged<double> onT;
  final VoidCallback onPlay, onRewind;
  final ValueChanged<BodyStyle> onStyle;

  @override
  Widget build(BuildContext context) {
    final fg = dark ? Colors.white : const Color(0xFF15171A);
    Widget scanPicker(int value, ValueChanged<int> onChanged) =>
        DropdownButton<int>(
          value: value,
          dropdownColor: dark ? const Color(0xFF1E2632) : Colors.white,
          underline: const SizedBox.shrink(),
          style: TextStyle(color: fg, fontSize: 13),
          iconEnabledColor: fg,
          items: [
            for (var i = 0; i < sampleScans.length; i++)
              DropdownMenuItem(
                value: i,
                child: Text(_date(sampleScans[i].date)),
              ),
          ],
          onChanged: (i) {
            if (i != null) onChanged(i);
          },
        );
    return Container(
      padding: EdgeInsets.fromLTRB(
        12,
        6,
        12,
        10 + MediaQuery.paddingOf(context).bottom,
      ),
      decoration: BoxDecoration(
        color: dark ? const Color(0x661E2632) : const Color(0x99FFFFFF),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              scanPicker(from, onFrom),
              Text('→', style: TextStyle(color: fg)),
              scanPicker(to, onTo),
            ],
          ),
          Row(
            children: [
              IconButton(
                icon: Icon(Icons.fast_rewind_rounded, color: fg),
                onPressed: onRewind,
              ),
              Expanded(
                child: Slider(value: t, onChanged: onT),
              ),
              IconButton(
                icon: Icon(Icons.play_arrow_rounded, color: fg),
                onPressed: onPlay,
              ),
            ],
          ),
          SegmentedButton<BodyStyle>(
            segments: const [
              ButtonSegment(value: BodyStyle.studio, label: Text('Studio')),
              ButtonSegment(value: BodyStyle.heatmap, label: Text('Heatmap')),
              ButtonSegment(value: BodyStyle.midnight, label: Text('Midnight')),
            ],
            selected: {style},
            showSelectedIcon: false,
            onSelectionChanged: (s) => onStyle(s.first),
            style: ButtonStyle(
              foregroundColor: WidgetStateProperty.resolveWith(
                (states) => states.contains(WidgetState.selected)
                    ? (dark ? Colors.black : Colors.white)
                    : fg,
              ),
              backgroundColor: WidgetStateProperty.resolveWith(
                (states) => states.contains(WidgetState.selected)
                    ? (dark ? Colors.white : const Color(0xFF15171A))
                    : Colors.transparent,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
