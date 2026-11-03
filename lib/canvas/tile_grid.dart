import 'dart:math' as math;
import 'dart:ui' show Offset, Rect, Size;

/// Identifies one cached texture: a square region of document space rasterized
/// at one power-of-two level of detail.
///
/// Every tile texture is [TileGrid.texturePixels] pixels square regardless of
/// level, so memory and raster cost per tile are constant. A tile at level `L`
/// covers `texturePixels / 2^L` document units per side, so higher levels cover
/// less area at higher resolution.
class TileKey {
  const TileKey(this.x, this.y, this.level);

  final int x;
  final int y;
  final int level;

  @override
  bool operator ==(Object other) =>
      other is TileKey && other.x == x && other.y == y && other.level == level;

  @override
  int get hashCode => Object.hash(x, y, level);

  @override
  String toString() => 'TileKey($x, $y, L$level)';
}

/// Pure tile-grid geometry shared by the scheduler and the painter.
class TileGrid {
  const TileGrid._();

  /// Edge length of every tile texture in device pixels.
  static const int texturePixels = 512;

  /// Smallest and largest level of detail. Level `L` rasterizes at `2^L`
  /// pixels per document unit.
  static const int minLevel = -4;
  static const int maxLevel = 5;

  /// Extra document-space margin rasterized around each tile so splats that
  /// straddle a tile edge are drawn in both tiles and no seam shows.
  static const double bleed = 2;

  /// Edge length of a tile in document units at [level].
  static double tileSize(int level) => texturePixels / math.pow(2, level);

  /// Pixels per document unit at [level].
  static double scaleOf(int level) => math.pow(2, level).toDouble();

  /// Level whose resolution best matches [pixelsPerUnit] (the on-screen scale
  /// of one document unit, i.e. zoom times device pixel ratio). Rounds up in
  /// log space so tiles are never magnified by more than `sqrt(2)`.
  static int levelFor(double pixelsPerUnit) {
    final raw = (math.log(pixelsPerUnit) / math.ln2 - 0.5).ceil();
    return raw.clamp(minLevel, maxLevel);
  }

  /// Document-space rectangle covered by [key] (without bleed).
  static Rect rectOf(TileKey key) {
    final size = tileSize(key.level);
    return Rect.fromLTWH(key.x * size, key.y * size, size, size);
  }

  /// Tile indices at [level] whose rectangle intersects [region]. Empty
  /// regions intersect nothing.
  static Iterable<TileKey> tilesIn(Rect region, int level) sync* {
    if (region.isEmpty) return;
    final size = tileSize(level);
    final x0 = (region.left / size).floor();
    final x1 = (region.right / size).ceil() - 1;
    final y0 = (region.top / size).floor();
    final y1 = (region.bottom / size).ceil() - 1;
    for (var y = y0; y <= y1; y++) {
      for (var x = x0; x <= x1; x++) {
        yield TileKey(x, y, level);
      }
    }
  }

  /// The tile at [level] that fully contains [key]'s area (a coarser
  /// ancestor), or null if [level] is not coarser than `key.level`.
  static TileKey? ancestor(TileKey key, int level) {
    if (level >= key.level) return null;
    final shift = key.level - level;
    return TileKey(key.x >> shift, key.y >> shift, level);
  }

  /// Document-space bounding box of the screen rectangle `Offset.zero & size`
  /// mapped through [toDocument]. Exact for rotation because all four corners
  /// are mapped.
  static Rect visibleDocumentRect(
    Size screen,
    Offset Function(Offset screenPosition) toDocument,
  ) {
    final corners = [
      toDocument(Offset.zero),
      toDocument(Offset(screen.width, 0)),
      toDocument(Offset(screen.width, screen.height)),
      toDocument(Offset(0, screen.height)),
    ];
    var left = corners.first.dx, right = left;
    var top = corners.first.dy, bottom = top;
    for (final c in corners) {
      left = math.min(left, c.dx);
      right = math.max(right, c.dx);
      top = math.min(top, c.dy);
      bottom = math.max(bottom, c.dy);
    }
    return Rect.fromLTRB(left, top, right, bottom);
  }
}
