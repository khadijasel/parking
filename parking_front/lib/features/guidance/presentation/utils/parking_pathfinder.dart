import 'dart:math' as math;

import 'package:flutter/material.dart';

class ParkingPathfinder {
  static List<Offset> findPath({
    required Size canvasSize,
    required Offset start,
    required Offset end,
    required List<Rect> obstacles,
    double cellSize = 8,
    double obstaclePadding = 2,
  }) {
    if (canvasSize.width <= 0 || canvasSize.height <= 0) {
      return const <Offset>[];
    }

    final int cols = math.max(2, (canvasSize.width / cellSize).ceil());
    final int rows = math.max(2, (canvasSize.height / cellSize).ceil());

    final List<Rect> blockedRects = obstacles
        .map((Rect rect) => rect.inflate(obstaclePadding))
        .toList(growable: false);

    bool isBlocked(int col, int row) {
      if (col < 0 || row < 0 || col >= cols || row >= rows) {
        return true;
      }
      final Offset center = Offset(
        (col + 0.5) * cellSize,
        (row + 0.5) * cellSize,
      );
      for (final Rect rect in blockedRects) {
        if (rect.contains(center)) {
          return true;
        }
      }
      return false;
    }

    int clampCol(double x) => (x / cellSize).floor().clamp(0, cols - 1);
    int clampRow(double y) => (y / cellSize).floor().clamp(0, rows - 1);

    final _Node startNode = _Node(clampCol(start.dx), clampRow(start.dy));
    final _Node endNode = _Node(clampCol(end.dx), clampRow(end.dy));

    if (isBlocked(startNode.c, startNode.r) || isBlocked(endNode.c, endNode.r)) {
      return const <Offset>[];
    }

    final List<_QueueItem> open = <_QueueItem>[];

    final Map<_Node, _Node?> cameFrom = <_Node, _Node?>{};
    final Map<_Node, int> gScore = <_Node, int>{};
    final Set<_Node> closed = <_Node>{};

    int heuristic(_Node a, _Node b) {
      return (a.c - b.c).abs() + (a.r - b.r).abs();
    }

    gScore[startNode] = 0;
    open.add(_QueueItem(startNode, heuristic(startNode, endNode), heuristic(startNode, endNode)));

    const List<Offset> dirs = <Offset>[
      Offset(1, 0),
      Offset(-1, 0),
      Offset(0, 1),
      Offset(0, -1),
    ];

    while (open.isNotEmpty) {
      open.sort((_QueueItem a, _QueueItem b) {
        final int byF = a.f.compareTo(b.f);
        if (byF != 0) {
          return byF;
        }
        return a.h.compareTo(b.h);
      });
      final _QueueItem currentItem = open.removeAt(0);
      final _Node current = currentItem.node;

      if (closed.contains(current)) {
        continue;
      }
      if (current == endNode) {
        final List<_Node> nodePath = <_Node>[];
        _Node? cursor = current;
        while (cursor != null) {
          nodePath.add(cursor);
          cursor = cameFrom[cursor];
        }
        final List<_Node> ordered = nodePath.reversed.toList(growable: false);

        final List<Offset> points = ordered
            .map(( _Node n) => Offset((n.c + 0.5) * cellSize, (n.r + 0.5) * cellSize))
            .toList(growable: false);
        return _compressCollinear(points, start, end);
      }

      closed.add(current);
      final int currentG = gScore[current] ?? 1 << 30;

      for (final Offset dir in dirs) {
        final _Node next = _Node(
          current.c + dir.dx.toInt(),
          current.r + dir.dy.toInt(),
        );

        if (isBlocked(next.c, next.r) || closed.contains(next)) {
          continue;
        }

        final int tentativeG = currentG + 1;
        final int bestKnown = gScore[next] ?? (1 << 30);
        if (tentativeG < bestKnown) {
          cameFrom[next] = current;
          gScore[next] = tentativeG;
          final int h = heuristic(next, endNode);
          open.add(_QueueItem(next, tentativeG + h, h));
        }
      }
    }

    return const <Offset>[];
  }

  static Path pathFromPoints(List<Offset> points) {
    if (points.isEmpty) {
      return Path();
    }

    final Path path = Path()..moveTo(points.first.dx, points.first.dy);
    for (int i = 1; i < points.length; i++) {
      path.lineTo(points[i].dx, points[i].dy);
    }
    return path;
  }

  static List<Offset> _compressCollinear(
    List<Offset> points,
    Offset start,
    Offset end,
  ) {
    if (points.length < 2) {
      return <Offset>[start, end];
    }

    final List<Offset> reduced = <Offset>[start, points.first];
    for (int i = 1; i < points.length - 1; i++) {
      final Offset a = points[i - 1];
      final Offset b = points[i];
      final Offset c = points[i + 1];
      final bool collinearX = (a.dx - b.dx).abs() < 0.01 && (b.dx - c.dx).abs() < 0.01;
      final bool collinearY = (a.dy - b.dy).abs() < 0.01 && (b.dy - c.dy).abs() < 0.01;
      if (!collinearX && !collinearY) {
        reduced.add(b);
      }
    }
    reduced.add(points.last);
    reduced.add(end);

    // Remove near duplicates.
    final List<Offset> cleaned = <Offset>[];
    for (final Offset point in reduced) {
      if (cleaned.isEmpty || (cleaned.last - point).distance > 0.5) {
        cleaned.add(point);
      }
    }

    return cleaned;
  }
}

class _Node {
  final int c;
  final int r;

  const _Node(this.c, this.r);

  @override
  bool operator ==(Object other) {
    return other is _Node && other.c == c && other.r == r;
  }

  @override
  int get hashCode => Object.hash(c, r);
}

class _QueueItem {
  final _Node node;
  final int f;
  final int h;

  const _QueueItem(this.node, this.f, this.h);
}
