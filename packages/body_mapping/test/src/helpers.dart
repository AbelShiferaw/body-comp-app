import 'dart:io';

import 'package:body_mapping/body_mapping.dart';

/// The bundled asset, parsed once per test file.
final BodyAsset testAsset = BodyAsset.parse(
  File('lib/assets/body.glb').readAsBytesSync(),
);

/// [scan] with one region's lean and fat replaced.
BodyScan withRegion(
  BodyScan scan,
  BodyRegion region, {
  double? leanKg,
  double? fatKg,
}) {
  final m = scan.regions[region]!;
  return scan.copyWith(
    regions: {
      ...scan.regions,
      region: RegionMass(
        leanKg: leanKg ?? m.leanKg,
        fatKg: fatKg ?? m.fatKg,
        boneKg: m.boneKg,
      ),
    },
  );
}

/// [scan] with one band's fat replaced.
BodyScan withBandFat(BodyScan scan, FatBand band, double fatKg) {
  final m = scan.bands[band]!;
  return scan.copyWith(
    bands: {
      ...scan.bands,
      band: RegionMass(leanKg: m.leanKg, fatKg: fatKg),
    },
  );
}
