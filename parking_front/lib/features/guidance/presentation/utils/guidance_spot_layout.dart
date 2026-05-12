import 'package:parking_front/features/parking/models/parking.dart';

enum GuidanceSpotState {
  available,
  reserved,
  occupied,
}

class GuidanceSpotViewData {
  final String label;
  final GuidanceSpotState state;
  final int rowIndex;
  final int colIndex;

  const GuidanceSpotViewData({
    required this.label,
    required this.state,
    required this.rowIndex,
    required this.colIndex,
  });

  /// Get the effective display label. Same as label field for GuidanceSpotViewData.
  String get displayLabel => label;
}

class GuidanceSpotLayout {
  final List<GuidanceSpotViewData> topRow;
  final List<GuidanceSpotViewData> bottomRow;

  const GuidanceSpotLayout({
    required this.topRow,
    required this.bottomRow,
  });

  factory GuidanceSpotLayout.fromIndoorSpots(List<ParkingIndoorSpot> spots) {
    final List<ParkingIndoorSpot> sortedSpots = sortIndoorSpots(spots);
    if (sortedSpots.isEmpty) {
      return const GuidanceSpotLayout(
        topRow: _kFallbackTopRow,
        bottomRow: _kFallbackBottomRow,
      );
    }

    final List<int> rowValues =
        sortedSpots.map((ParkingIndoorSpot spot) => spot.row).toSet().toList()
          ..sort();

    final int? topRowValue = rowValues.isNotEmpty ? rowValues.first : null;
    final int? bottomRowValue = rowValues.length > 1 ? rowValues[1] : null;

    final List<ParkingIndoorSpot> topSource = topRowValue == null
        ? const <ParkingIndoorSpot>[]
        : sortedSpots
            .where((ParkingIndoorSpot spot) => spot.row == topRowValue)
            .toList(growable: false);
    final List<ParkingIndoorSpot> bottomSource = bottomRowValue == null
        ? const <ParkingIndoorSpot>[]
        : sortedSpots
            .where((ParkingIndoorSpot spot) => spot.row == bottomRowValue)
            .toList(growable: false);

    return GuidanceSpotLayout(
      topRow: _buildRow(
        source: topSource,
        rowIndex: 0,
        fallback: _kFallbackTopRow,
      ),
      bottomRow: _buildRow(
        source: bottomSource,
        rowIndex: 1,
        fallback: _kFallbackBottomRow,
      ),
    );
  }

  List<GuidanceSpotViewData> get allSpots =>
      <GuidanceSpotViewData>[...topRow, ...bottomRow];

  GuidanceSpotViewData? findByLabel(String rawLabel) {
    final String normalizedLabel = _normalizeLabel(rawLabel);
    if (normalizedLabel.isEmpty) {
      return null;
    }

    for (final GuidanceSpotViewData spot in allSpots) {
      if (_normalizeLabel(spot.displayLabel) == normalizedLabel) {
        return spot;
      }
    }

    return null;
  }

  GuidanceSpotViewData? findFirstAvailable() {
    for (final GuidanceSpotViewData spot in allSpots) {
      if (spot.state == GuidanceSpotState.available) {
        return spot;
      }
    }

    return null;
  }

  /// Find the spot AVAILABLE the closest to the entry (bottom-left).
  /// Order: bottom-row left → right, then top-row left → right.
  GuidanceSpotViewData? findNearestAvailable() {
    for (final GuidanceSpotViewData spot in bottomRow) {
      if (spot.state == GuidanceSpotState.available) {
        return spot;
      }
    }
    for (final GuidanceSpotViewData spot in topRow) {
      if (spot.state == GuidanceSpotState.available) {
        return spot;
      }
    }
    return null;
  }
}

const List<GuidanceSpotViewData> _kFallbackTopRow = <GuidanceSpotViewData>[
  GuidanceSpotViewData(
    label: 'P01',
    state: GuidanceSpotState.occupied,
    rowIndex: 0,
    colIndex: 0,
  ),
  GuidanceSpotViewData(
    label: 'P02',
    state: GuidanceSpotState.available,
    rowIndex: 0,
    colIndex: 1,
  ),
  GuidanceSpotViewData(
    label: 'P03',
    state: GuidanceSpotState.available,
    rowIndex: 0,
    colIndex: 2,
  ),
];

const List<GuidanceSpotViewData> _kFallbackBottomRow = <GuidanceSpotViewData>[
  GuidanceSpotViewData(
    label: 'P04',
    state: GuidanceSpotState.available,
    rowIndex: 1,
    colIndex: 0,
  ),
  GuidanceSpotViewData(
    label: 'P05',
    state: GuidanceSpotState.reserved,
    rowIndex: 1,
    colIndex: 1,
  ),
  GuidanceSpotViewData(
    label: 'P06',
    state: GuidanceSpotState.available,
    rowIndex: 1,
    colIndex: 2,
  ),
];

List<GuidanceSpotViewData> _buildRow({
  required List<ParkingIndoorSpot> source,
  required int rowIndex,
  required List<GuidanceSpotViewData> fallback,
}) {
  final List<ParkingIndoorSpot> sortedSource = List<ParkingIndoorSpot>.from(
    source,
  )..sort(_compareByCol);

  return List<GuidanceSpotViewData>.generate(3, (int colIndex) {
    if (colIndex < sortedSource.length) {
      final ParkingIndoorSpot spot = sortedSource[colIndex];
      return GuidanceSpotViewData(
        label: spot.label,
        state: guidanceSpotStateFromBackend(spot.state),
        rowIndex: rowIndex,
        colIndex: colIndex,
      );
    }

    final GuidanceSpotViewData fallbackSpot = fallback[colIndex];
    return GuidanceSpotViewData(
      label: fallbackSpot.displayLabel,
      state: fallbackSpot.state,
      rowIndex: rowIndex,
      colIndex: colIndex,
    );
  }, growable: false);
}

GuidanceSpotState guidanceSpotStateFromBackend(String rawState) {
  switch (rawState.trim().toUpperCase()) {
    case 'RESERVED':
      return GuidanceSpotState.reserved;
    case 'AVAILABLE':
      return GuidanceSpotState.available;
    case 'OCCUPIED':
    case 'OFFLINE':
    default:
      return GuidanceSpotState.occupied;
  }
}

List<ParkingIndoorSpot> sortIndoorSpots(List<ParkingIndoorSpot> spots) {
  final List<ParkingIndoorSpot> sorted = List<ParkingIndoorSpot>.from(spots);
  sorted.sort(_compareByRowAndCol);
  return List<ParkingIndoorSpot>.unmodifiable(sorted);
}

String resolveSpotLabelFromTicketCode(
  String ticketCode,
  List<ParkingIndoorSpot> spots, {
  String fallback = '',
}) {
  final String source = ticketCode.trim().toUpperCase();
  if (source.isEmpty) {
    return fallback;
  }

  final List<ParkingIndoorSpot> sortedSpots = sortIndoorSpots(spots);
  final String normalizedSource = _normalizeLabel(source);

  for (final ParkingIndoorSpot spot in sortedSpots) {
    final String normalizedSpotLabel = _normalizeLabel(spot.displayLabel);
    if (normalizedSpotLabel.isNotEmpty &&
        normalizedSource.contains(normalizedSpotLabel)) {
      return spot.displayLabel;
    }
  }

  final List<Match> numberMatches = RegExp(r'(\d+)').allMatches(source).toList();
  if (sortedSpots.isNotEmpty && numberMatches.isNotEmpty) {
    final Match last = numberMatches.last;
    final int rawIndex = int.tryParse(last.group(1) ?? '') ?? -1;
    final int zeroBasedIndex = rawIndex - 1;

    if (zeroBasedIndex >= 0 && zeroBasedIndex < sortedSpots.length) {
      return sortedSpots[zeroBasedIndex].displayLabel;
    }
  }

  final List<Match> legacyMatches =
      RegExp(r'([AB])\s*-?\s*(\d+)').allMatches(source).toList();
  if (legacyMatches.isNotEmpty) {
    final Match last = legacyMatches.last;
    final String letter = last.group(1) ?? 'A';
    final int rawNumber = int.tryParse(last.group(2) ?? '1') ?? 1;
    final int normalizedNumber = ((rawNumber - 1) % 3) + 1;
    return '$letter$normalizedNumber';
  }

  return fallback;
}

int _compareByRowAndCol(ParkingIndoorSpot left, ParkingIndoorSpot right) {
  final int rowComparison = left.row.compareTo(right.row);
  if (rowComparison != 0) {
    return rowComparison;
  }

  final int colComparison = left.col.compareTo(right.col);
  if (colComparison != 0) {
    return colComparison;
  }

  return left.label.compareTo(right.label);
}

int _compareByCol(ParkingIndoorSpot left, ParkingIndoorSpot right) {
  final int colComparison = left.col.compareTo(right.col);
  if (colComparison != 0) {
    return colComparison;
  }

  return left.label.compareTo(right.label);
}

String _normalizeLabel(String value) {
  return value.trim().toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
}
