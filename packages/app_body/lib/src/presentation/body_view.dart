import 'dart:async';
import 'dart:math' as math;

import 'package:app_body/src/domain/body_renderer.dart';
import 'package:app_body/src/domain/body_view_state.dart';
import 'package:app_body/src/presentation/body_providers.dart';
import 'package:app_body/src/presentation/body_strings.dart';
import 'package:app_body/src/presentation/part_pins.dart';
import 'package:app_core/app_core.dart';
import 'package:app_ui/app_ui.dart';
import 'package:body_mapping/body_mapping.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

// TODO(body): move strings to localization once modules share l10n.

/// The 3D body with its controls: drag to turn, pinch to zoom, tap a part
/// for its numbers, and a Shape / Fat / Change bar under it. Fills the space
/// it is given. In game mode the avatar turns slowly on its own, like a
/// character on a game's select screen; it pauses while touched or while a
/// part is open, and stays still when the phone asks for reduced motion.
///
/// With [showCompare], it also shows the scan-to-scan slider with play and
/// the ×3 exaggerate button. Home leaves them off (the basic look); they
/// belong on the Progress screen.
class BodyView extends ConsumerStatefulWidget {
  const new({this.emptyMessage, this.showCompare = false, super.key});

  /// Shown when there are no scans yet.
  final String? emptyMessage;

  /// Shows the compare controls (timeline, play, ×3).
  final bool showCompare;

  @override
  ConsumerState<BodyView> createState() => _BodyViewState();
}

class _BodyViewState extends ConsumerState<BodyView>
    with TickerProviderStateMixin {
  /// One full turn of the game-mode spin, and how long it waits after a
  /// touch before it carries on.
  static const _spinTurn = Duration(seconds: 24);
  static const _spinRest = Duration(seconds: 3);

  BodyRenderer? _renderer;
  bool _rendererReady = false;
  Object? _rendererError;
  BodyShapes? _latestShapes;

  /// The shapes to draw. The listener below only sees changes, so shapes that
  /// were already loaded before this view mounted (another screen read them
  /// first) come from the provider directly.
  BodyShapes? get _shapes =>
      _latestShapes ?? ref.read(bodyShapesProvider).value;
  CameraPose _pose = (azimuth: 0, zoom: 1);
  double _zoomAtScaleStart = 1;
  Size _viewSize = Size.zero;
  late final AnimationController _play = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2400),
  )..addListener(_onPlayTick);
  late final Ticker _spin = createTicker(_onSpinTick);
  Duration? _spinLast;
  Duration _spinResumeAt = Duration.zero;

  BodyViewController get _controller =>
      ref.read(bodyViewControllerProvider.notifier);

  @override
  void initState() {
    super.initState();
    unawaited(_initRenderer()); // Errors are shown and reported inside.
  }

  Future<void> _initRenderer() async {
    try {
      final asset = await ref.read(bodyAssetProvider.future);
      final renderer = ref.read(bodyRendererFactoryProvider)();
      await renderer.load(asset);
      if (!mounted) {
        renderer.dispose();
        return;
      }
      setState(() {
        _renderer = renderer;
        _rendererReady = true;
      });
      _pushAll();
    } on Object catch (e, s) {
      // Shown as the error state below; reported, never swallowed.
      AppLogger('body').error('Body renderer failed to start', e, s);
      if (mounted) setState(() => _rendererError = e);
      // Rethrown so the app's crash reporter records it.
      rethrow;
    }
  }

  @override
  void dispose() {
    _spin.dispose();
    _play.dispose();
    _renderer?.dispose();
    super.dispose();
  }

  /// Starts or stops the game-mode spin.
  void _setSpinning(bool on) {
    if (on == _spin.isActive) return;
    if (on) {
      _spinLast = null;
      _spinResumeAt = Duration.zero;
      _spin.start();
    } else {
      _spin.stop();
    }
  }

  /// Holds the spin while the user turns or zooms the body, and a moment
  /// after.
  void _holdSpin() => _spinResumeAt = (_spinLast ?? Duration.zero) + _spinRest;

  void _onSpinTick(Duration elapsed) {
    final last = _spinLast;
    _spinLast = elapsed;
    if (last == null || elapsed < _spinResumeAt) return;
    final turn =
        (elapsed - last).inMicroseconds /
        _spinTurn.inMicroseconds *
        2 *
        math.pi;
    setState(() {
      _pose = (
        azimuth: (_pose.azimuth + turn) % (2 * math.pi),
        zoom: _pose.zoom,
      );
      _renderer?.setCamera(_pose);
    });
  }

  void _onPlayTick() =>
      _controller.setT(Curves.easeInOut.transform(_play.value));

  void _playMorph() {
    final t = ref.read(bodyViewControllerProvider).t;
    _play.forward(from: t >= 1 ? 0 : t);
  }

  /// Pushes shapes, colors, style and camera to the renderer.
  void _pushAll() {
    final r = _renderer;
    final shapes = _shapes;
    if (r == null || shapes == null) return;
    final view = ref.read(bodyViewControllerProvider);
    r
      ..setShapes(shapes.a, shapes.b)
      ..setT(view.t)
      ..setStyle(ref.read(bodyStyleProvider))
      ..setBrightness(Theme.of(context).brightness)
      ..setCamera(_pose)
      ..highlight(view.selected);
    _pushColors(view);
  }

  /// The heatmap's neutral color: the plain body's, so the head and
  /// unchanged parts keep the style's look. Not for change maps in game
  /// mode, where the blue hologram would read as the blue of progress.
  Rgb? _neutralFor(HeatMetric metric) {
    if (metric != HeatMetric.fatPct &&
        ref.read(bodyStyleProvider) == BodyStyle.hologram) {
      return null;
    }
    return _renderer?.plainHeatColor;
  }

  void _pushColors(BodyViewState view) {
    final r = _renderer;
    final shapes = _shapes;
    final mapper = ref.read(bodyMapperProvider).value;
    if (r == null || shapes == null || mapper == null) return;
    final metric = view.heatMetric;
    r.setColors(
      metric == null
          ? null
          : mapper
                .colorsFor(
                  shapes.pair.from,
                  shapes.pair.to,
                  metric,
                  t: view.t,
                  neutral: _neutralFor(metric),
                )
                .bake(mapper.asset),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _renderer?.setBrightness(Theme.of(context).brightness);
    // The neutral heatmap color follows the look.
    _pushColors(ref.read(bodyViewControllerProvider));
  }

  @override
  Widget build(BuildContext context) {
    ref
      ..listen(bodyShapesProvider, (_, next) {
        final shapes = next.value;
        if (shapes == null) return;
        _latestShapes = shapes;
        _pushAll();
      })
      ..listen(bodyViewControllerProvider, (prev, next) {
        final r = _renderer;
        if (r == null) return;
        if (prev?.t != next.t) r.setT(next.t);
        if (prev?.selected != next.selected) r.highlight(next.selected);
        final colorsChanged =
            prev?.heatMetric != next.heatMetric ||
            (next.heatMetric == HeatMetric.fatPct && prev?.t != next.t);
        if (colorsChanged) _pushColors(next);
      })
      ..listen(bodyStyleProvider, (prev, s) {
        _renderer?.setStyle(s);
        _pushColors(ref.read(bodyViewControllerProvider));
        // Leaving game mode: face front again after the turntable.
        if (prev == BodyStyle.hologram && s != BodyStyle.hologram) {
          setState(() => _pose = (azimuth: 0, zoom: _pose.zoom));
          _renderer?.setCamera(_pose);
        }
      })
      ..listen(bodyScansProvider, (prev, next) {
        // A new scan after the first load (Refresh): show what changed.
        final before = prev?.value;
        final after = next.value;
        if (before == null ||
            before.isEmpty ||
            after == null ||
            after.isEmpty) {
          return;
        }
        if (after.last.id != before.last.id) {
          _controller.showNewScan(after);
          _playMorph();
        }
      });

    final tokens = context.tokens;
    final scans = ref.watch(bodyScansProvider);
    final shapes = ref.watch(bodyShapesProvider);
    final view = ref.watch(bodyViewControllerProvider);
    final style = ref.watch(bodyStyleProvider);
    final asset = ref.watch(bodyAssetProvider);
    // Kept warm so the first tap can pick.
    ref.watch(bodyPickerProvider);

    final error = scans.error ?? shapes.error ?? asset.error ?? _rendererError;
    final Widget content;
    if (error != null) {
      content = ErrorView(
        message: error is NetworkException
            ? 'Could not load your scans. Check your connection.'
            : 'Your 3D body could not be shown.',
        onRetry: () {
          ref
            ..invalidate(bodyScansProvider)
            ..invalidate(bodyAssetProvider);
        },
      );
    } else if (scans.value?.isEmpty ?? false) {
      content = Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Text(
            widget.emptyMessage ??
                'Your 3D body appears here after your first scan',
            textAlign: TextAlign.center,
            style: TextStyle(color: tokens.textSecondary),
          ),
        ),
      );
    } else if (!_rendererReady || shapes.value == null) {
      content = const LoadingView();
    } else {
      content = _body(context, shapes.value!, view, style);
    }
    _setSpinning(
      error == null &&
          _rendererReady &&
          shapes.value != null &&
          style == BodyStyle.hologram &&
          view.selected == null &&
          !MediaQuery.disableAnimationsOf(context),
    );

    return DecoratedBox(
      decoration: BoxDecoration(gradient: _background(tokens, style)),
      child: content,
    );
  }

  Widget _body(
    BuildContext context,
    BodyShapes shapes,
    BodyViewState view,
    BodyStyle style,
  ) {
    final tokens = context.tokens;
    final pair = shapes.pair;
    final metric = view.heatMetric;
    final mapper = ref.watch(bodyMapperProvider).value;
    return Column(
      children: [
        // Above the body, not over it, so a turning body never goes behind
        // it.
        if (metric != null && mapper != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              AppSpacing.xs,
              AppSpacing.md,
              0,
            ),
            child: _Legend(
              metric: metric,
              stops: mapper.legend(
                metric,
                pair.to.sex,
                neutral: _neutralFor(metric),
              ),
              from: pair.from,
              to: pair.to,
            ),
          ),
        Expanded(
          child: Stack(
            children: [
              if (style == BodyStyle.hologram)
                Positioned.fill(
                  // The scene repaints every frame; keep the pad out of it.
                  child: RepaintBoundary(
                    child: CustomPaint(
                      key: const Key('body_pad'),
                      painter: ScannerPadPainter(
                        color: tokens.lean,
                        zoom: _pose.zoom,
                      ),
                    ),
                  ),
                ),
              Positioned.fill(child: _scene()),
              if (view.selected == null && math.cos(_pose.azimuth).abs() > 0.6)
                Positioned.fill(child: _pins(pair, view)),
              if (widget.showCompare)
                Positioned(
                  right: AppSpacing.sm,
                  top: AppSpacing.xs,
                  child: _ExaggerateButton(
                    on: view.exaggerate,
                    onTap: _controller.toggleExaggerate,
                  ),
                ),
              if (view.exaggerate)
                Positioned(
                  right: AppSpacing.md,
                  top: 52,
                  child: _Badge(text: '×3', color: tokens.accent),
                ),
              if (view.selected != null)
                Positioned(
                  left: AppSpacing.md,
                  right: AppSpacing.md,
                  bottom: AppSpacing.sm,
                  child: _PartCard(
                    part: view.selected!,
                    pair: pair,
                    t: view.t,
                    unit: ref.watch(bodyMassUnitProvider),
                    onClose: () => _controller.select(null),
                  ),
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            AppSpacing.xs,
            AppSpacing.md,
            AppSpacing.sm,
          ),
          child: _ModeBar(view: view, controller: _controller),
        ),
        if (widget.showCompare)
          _Timeline(
            scans: ref.watch(bodyScansProvider).value ?? const [],
            pair: pair,
            t: view.t,
            onT: (t) {
              _play.stop();
              _controller.setT(t);
            },
            onPlay: _playMorph,
            onCompare: (from, to) =>
                _controller.compare(fromId: from.id, toId: to.id),
          ),
      ],
    );
  }

  Widget _scene() => LayoutBuilder(
    builder: (context, c) {
      _viewSize = Size(c.maxWidth, c.maxHeight);
      final renderer = _renderer!;
      return Semantics(
        label: '3D body. Drag to turn, tap a body part for its numbers.',
        child: GestureDetector(
          key: const Key('body_scene'),
          behavior: HitTestBehavior.opaque,
          onScaleStart: (_) {
            _holdSpin();
            _zoomAtScaleStart = _pose.zoom;
          },
          onScaleUpdate: (d) => setState(() {
            _holdSpin();
            _pose = (
              azimuth: _pose.azimuth - d.focalPointDelta.dx * 0.012,
              zoom: (_zoomAtScaleStart * d.scale).clamp(1.0, 3.0),
            );
            renderer.setCamera(_pose);
          }),
          onTapUp: (d) => _pick(d.localPosition),
          child: renderer.build(context),
        ),
      );
    },
  );

  /// Pins on the arms, belly and legs with each part's number for the
  /// current view. They follow the body as it turns, and hide while the body
  /// is side on (where an arm would sit behind the trunk) or a part is open.
  Widget _pins(ScanPair pair, BodyViewState view) {
    final picker = ref.watch(bodyPickerProvider).value;
    final shapes = _shapes;
    final r = _renderer;
    if (picker == null || shapes == null || r == null) {
      return const SizedBox.shrink();
    }
    return LayoutBuilder(
      builder: (context, c) {
        final size = Size(c.maxWidth, c.maxHeight);
        final unit = ref.watch(bodyMassUnitProvider);
        final pins = <PartPin>[
          for (final part in pinnedParts)
            if (_pinPoint(picker, shapes, r, part, view.t, size)
                case final point?)
              (
                part: part,
                point: point,
                text: pinLabel(part, view, pair, unit),
              ),
        ];
        return PartPins(pins: pins, onTap: _controller.select);
      },
    );
  }

  Offset? _pinPoint(
    BodyPicker picker,
    BodyShapes shapes,
    BodyRenderer r,
    BodyPart part,
    double t,
    Size size,
  ) {
    final a = picker.anchorOf(
      part,
      shapes.a,
      shapes.b,
      t,
      towardX: math.sin(_pose.azimuth),
      towardZ: -math.cos(_pose.azimuth),
    );
    return r.screenPointOf(a.x, a.y, a.z, size);
  }

  void _pick(Offset point) {
    final picker = ref.read(bodyPickerProvider).value;
    final shapes = _shapes;
    final r = _renderer;
    if (picker == null || shapes == null || r == null) return;
    final part = picker.pick(
      r.rayAt(point, _viewSize),
      shapes.a,
      shapes.b,
      ref.read(bodyViewControllerProvider).t,
    );
    _controller.select(part);
  }

  static Gradient _background(AppTokens t, BodyStyle style) => switch (style) {
    BodyStyle.hologram => RadialGradient(
      center: const Alignment(0, 0.1),
      radius: 0.85,
      colors: [
        Color.alphaBlend(t.lean.withValues(alpha: 0.10), t.surfaceRaised),
        t.background,
      ],
    ),
    BodyStyle.studio => LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [t.background, t.surfaceRaised],
    ),
    BodyStyle.midnight => RadialGradient(
      center: const Alignment(0, -0.1),
      radius: 1.2,
      colors: [t.surfaceRaised, t.background],
    ),
  };
}

class _ModeBar extends StatelessWidget {
  const new({required this.view, required this.controller});

  final BodyViewState view;
  final BodyViewController controller;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        if (view.mode == BodyViewMode.change)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.xs),
            child: Wrap(
              spacing: AppSpacing.sm,
              children: [
                for (final (m, label) in const [
                  (ChangeMetric.fat, 'Fat change'),
                  (ChangeMetric.lean, 'Lean change'),
                ])
                  ChoiceChip(
                    label: Text(label),
                    selected: view.changeMetric == m,
                    onSelected: (_) => controller.setChangeMetric(m),
                  ),
              ],
            ),
          ),
        SizedBox(
          width: double.infinity,
          child: SegmentedButton<BodyViewMode>(
            key: const Key('body_mode'),
            segments: const [
              ButtonSegment(value: BodyViewMode.body, label: Text('Shape')),
              ButtonSegment(value: BodyViewMode.fat, label: Text('Fat')),
              ButtonSegment(value: BodyViewMode.change, label: Text('Change')),
            ],
            selected: {view.mode},
            showSelectedIcon: false,
            onSelectionChanged: (s) => controller.setMode(s.first),
          ),
        ),
      ],
    );
  }
}

class _Legend extends StatelessWidget {
  const new({
    required this.metric,
    required this.stops,
    required this.from,
    required this.to,
  });

  final HeatMetric metric;
  final List<RampStop> stops;
  final BodyScan from;
  final BodyScan to;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final text = Theme.of(context).textTheme.labelSmall
        ?.copyWith(color: tokens.textSecondary);
    final change = metric != HeatMetric.fatPct;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: tokens.surface.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Wrap(
        spacing: AppSpacing.md,
        runSpacing: AppSpacing.xs,
        alignment: WrapAlignment.center,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          for (final (i, s) in stops.reversed.indexed)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: Color.from(
                        alpha: 1,
                        red: s.color.r,
                        green: s.color.g,
                        blue: s.color.b,
                      ),
                      borderRadius: BorderRadius.circular(3),
                      // Keeps a swatch in the body's own dark color visible.
                      border: Border.all(color: tokens.textFaint),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Text(
                    legendLabel(metric, s.value, first: i == 0),
                    style: text,
                  ),
                ],
              ),
            ),
          if (change)
            Text(
              '${shortDate(from.scannedAt)} → ${shortDate(to.scannedAt)}',
              style: text,
            ),
        ],
      ),
    );
  }
}

class _ExaggerateButton extends StatelessWidget {
  const new({required this.on, required this.onTap});

  final bool on;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => IconButton(
    key: const Key('body_exaggerate'),
    tooltip: on ? 'Show true change' : 'Exaggerate change ×3',
    isSelected: on,
    icon: const Icon(Icons.zoom_out_map),
    selectedIcon: const Icon(Icons.zoom_in_map),
    onPressed: onTap,
  );
}

class _Badge extends StatelessWidget {
  const new({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(
      horizontal: AppSpacing.sm,
      vertical: AppSpacing.xs,
    ),
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(AppRadius.sm),
    ),
    child: Text(
      text,
      style: Theme.of(context).textTheme.labelLarge
          ?.copyWith(color: context.tokens.onAccent),
    ),
  );
}

/// Numbers for a tapped part: lean and fat (kg or lb) next to fat %, and
/// the change since the earlier scan (mass beside %, so small lean limbs do
/// not look dramatic).
class _PartCard extends StatelessWidget {
  const new({
    required this.part,
    required this.pair,
    required this.t,
    required this.unit,
    required this.onClose,
  });

  final BodyPart part;
  final ScanPair pair;
  final double t;
  final MassUnit unit;
  final VoidCallback onClose;

  RegionMass? _mass(BodyScan s) =>
      part.region != null ? s.regions[part.region] : s.bands[part.band];

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final textTheme = Theme.of(context).textTheme;
    final a = _mass(pair.from);
    final b = _mass(pair.to);
    if (a == null || b == null) return const SizedBox.shrink();
    final compare = !identical(pair.from, pair.to);
    double lerp(double x, double y) => x + (y - x) * t;

    Widget cell(String label, String value, String? change) => Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: textTheme.labelSmall?.copyWith(color: tokens.textSecondary),
          ),
          Text(
            value,
            style: textTheme.titleMedium?.copyWith(color: tokens.textPrimary),
          ),
          if (change != null)
            Text(
              change,
              style: textTheme.labelSmall?.copyWith(
                color: tokens.textSecondary,
              ),
            ),
        ],
      ),
    );

    String mass(double kg) => '${unit.of(kg).toStringAsFixed(2)} ${unit.name}';
    String massChange(double x, double y) {
      final pct = x == 0 ? 0 : 100 * (y - x) / x;
      return '${signed(unit.of(y - x), digits: 2)} ${unit.name} '
          '(${signed(pct.toDouble())}%)';
    }

    return Container(
      key: const Key('body_partCard'),
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.xs,
        AppSpacing.md,
      ),
      decoration: BoxDecoration(
        color: tokens.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: tokens.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                partName(part),
                style: textTheme.titleSmall?.copyWith(
                  color: tokens.textPrimary,
                ),
              ),
              const Spacer(),
              IconButton(
                tooltip: 'Close',
                icon: Icon(Icons.close, color: tokens.textSecondary, size: 18),
                visualDensity: VisualDensity.compact,
                onPressed: onClose,
              ),
            ],
          ),
          Row(
            children: [
              cell(
                'Lean',
                mass(lerp(a.leanKg, b.leanKg)),
                compare ? massChange(a.leanKg, b.leanKg) : null,
              ),
              cell(
                'Fat',
                mass(lerp(a.fatKg, b.fatKg)),
                compare ? massChange(a.fatKg, b.fatKg) : null,
              ),
              cell(
                'Fat %',
                '${lerp(a.fatPct, b.fatPct).toStringAsFixed(1)}%',
                compare ? '${signed(b.fatPct - a.fatPct)} pts' : null,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Timeline extends StatelessWidget {
  const new({
    required this.scans,
    required this.pair,
    required this.t,
    required this.onT,
    required this.onPlay,
    required this.onCompare,
  });

  final List<BodyScan> scans;
  final ScanPair pair;
  final double t;
  final ValueChanged<double> onT;
  final VoidCallback onPlay;
  final void Function(BodyScan from, BodyScan to) onCompare;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final textTheme = Theme.of(context).textTheme;
    Widget picker(BodyScan value, ValueChanged<BodyScan> onChanged, Key key) =>
        DropdownButton<BodyScan>(
          key: key,
          value: value,
          isExpanded: true,
          underline: const SizedBox.shrink(),
          style: textTheme.labelLarge?.copyWith(color: tokens.textPrimary),
          dropdownColor: tokens.surface,
          items: [
            for (final s in scans)
              DropdownMenuItem(value: s, child: Text(shortDate(s.scannedAt))),
          ],
          onChanged: (s) {
            if (s != null) onChanged(s);
          },
        );

    final single = scans.length < 2;
    return Container(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.xs,
        AppSpacing.sm,
        AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: tokens.surface.withValues(alpha: 0.7),
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(AppRadius.lg),
        ),
      ),
      child: single
          ? Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
              child: Text(
                shortDate(pair.to.scannedAt),
                style: textTheme.labelLarge?.copyWith(
                  color: tokens.textPrimary,
                ),
              ),
            )
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Flexible(
                      child: picker(
                        pair.from,
                        (s) => onCompare(s, pair.to),
                        const Key('body_from'),
                      ),
                    ),
                    Icon(Icons.arrow_forward, color: tokens.textSecondary),
                    Flexible(
                      child: picker(
                        pair.to,
                        (s) => onCompare(pair.from, s),
                        const Key('body_to'),
                      ),
                    ),
                  ],
                ),
                Row(
                  children: [
                    Expanded(
                      child: Slider(
                        key: const Key('body_slider'),
                        value: t,
                        onChanged: onT,
                      ),
                    ),
                    IconButton(
                      key: const Key('body_play'),
                      tooltip: 'Play the change',
                      icon: Icon(Icons.play_arrow, color: tokens.textPrimary),
                      onPressed: onPlay,
                    ),
                  ],
                ),
              ],
            ),
    );
  }
}

/// The game-style scanner pad under the avatar's feet: concentric rings and a
/// hex ring in the lean color, drawn behind the 3D scene. Its position follows
/// the renderer's camera fit (whole body framed, feet near the bottom).
@visibleForTesting
class ScannerPadPainter extends CustomPainter {
  const new({required this.color, required this.zoom});

  final Color color;
  final double zoom;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    // Same framing as the renderer, so the pad sits under the feet.
    final fit = BodyFraming.fit(size.width / size.height);
    final z = zoom.clamp(1, BodyFraming.maxZoom);
    final feetY = size.height * (0.5 + 0.5 * z * 0.5 / fit);
    final bodyPx = size.height * z / (2 * fit);
    final center = Offset(size.width / 2, feetY);
    final rx = bodyPx * 0.36;
    Rect ellipse(double scale) => Rect.fromCenter(
      center: center,
      width: 2 * rx * scale,
      height: 2 * rx * scale * 0.22,
    );

    canvas
      ..drawOval(
        ellipse(1.25),
        Paint()
          ..shader = RadialGradient(
            colors: [color.withValues(alpha: 0.28), color.withValues(alpha: 0)],
          ).createShader(ellipse(1.25)),
      )
      ..drawOval(
        ellipse(1),
        Paint()
          ..color = color.withValues(alpha: 0.75)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6,
      )
      ..drawOval(
        ellipse(0.62),
        Paint()
          ..color = color.withValues(alpha: 0.4)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1,
      );

    // Hex ticks around the outer ring.
    final tick = Paint()
      ..color = color.withValues(alpha: 0.55)
      ..strokeWidth = 1.2;
    for (var i = 0; i < 24; i++) {
      final a = i * math.pi / 12;
      final p = Offset(math.cos(a), math.sin(a) * 0.22);
      canvas.drawLine(center + p * rx * 1.04, center + p * rx * 1.12, tick);
    }
  }

  @override
  bool shouldRepaint(ScannerPadPainter old) =>
      old.color != color || old.zoom != zoom;
}
