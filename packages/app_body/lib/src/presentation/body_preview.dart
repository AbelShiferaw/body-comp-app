import 'dart:async';
import 'dart:math' as math;

import 'package:app_body/src/domain/body_renderer.dart';
import 'package:app_body/src/presentation/body_providers.dart';
import 'package:app_core/app_core.dart';
import 'package:body_mapping/body_mapping.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

/// The base body, turning slowly, for screens before the user has a scan
/// (onboarding). It shows no one's data: just the mesh in the chosen style.
/// Decorative, so it is hidden from screen readers. Draws nothing if the
/// renderer cannot start (the error is logged).
class BodyPreview extends ConsumerStatefulWidget {
  const new({super.key});

  @override
  ConsumerState<BodyPreview> createState() => _BodyPreviewState();
}

class _BodyPreviewState extends ConsumerState<BodyPreview>
    with SingleTickerProviderStateMixin {
  BodyRenderer? _renderer;

  /// One slow turn on arrival, ending slightly to the side like the design,
  /// then it rests (no endless animation, so it costs nothing while idle).
  late final AnimationController _spin = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 6),
  )..addListener(_turn);

  @override
  void initState() {
    super.initState();
    unawaited(_start());
  }

  Future<void> _start() async {
    try {
      final asset = await ref.read(bodyAssetProvider.future);
      final renderer = ref.read(bodyRendererFactoryProvider)();
      await renderer.load(asset);
      if (!mounted) {
        renderer.dispose();
        return;
      }
      final base = BodyGeometry.withNormals(asset.positions, asset.indices);
      renderer
        ..setShapes(base, base)
        ..setT(0)
        ..setColors(null)
        ..setStyle(ref.read(bodyStyleProvider))
        ..setBrightness(Theme.of(context).brightness);
      setState(() => _renderer = renderer);
      _turn();
      if (!(MediaQuery.maybeDisableAnimationsOf(context) ?? false)) {
        _spin.forward();
      }
    } on Object catch (e, s) {
      // Decoration only: log it and leave the space empty.
      AppLogger('body').error('Body preview failed to start', e, s);
    }
  }

  void _turn() => _renderer?.setCamera((
    azimuth: -0.5 + Curves.easeOutCubic.transform(_spin.value) * 2 * math.pi,
    zoom: 1,
  ));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _renderer?.setBrightness(Theme.of(context).brightness);
  }

  @override
  void dispose() {
    _spin.dispose();
    _renderer?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(bodyStyleProvider, (_, s) => _renderer?.setStyle(s));
    final r = _renderer;
    return ExcludeSemantics(
      child: r == null ? const SizedBox.expand() : r.build(context),
    );
  }
}
