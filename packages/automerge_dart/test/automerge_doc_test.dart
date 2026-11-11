// What: Tests of a single AutomergeDoc: value round trips, nested maps,
//   keys and delete, save and load, actor ids, and error reporting.
// Why: the app's CRDT port (docs/decisions/007-crdt-automerge.md
//   PNT-A0013-03) relies on every leaf kind coming back exactly as written,
//   on saved bytes reloading to the same content, and on failures surfacing
//   as AutomergeException instead of crashes.
// Covers: lib/src/document.dart (AutomergeDoc, ObjId), lib/src/value.dart,
//   lib/src/native.dart (result checks and byte/string copies), and the
//   native library built by hook/build.dart.

import 'dart:typed_data';

import 'package:automerge_dart/automerge_dart.dart';
import 'package:test/test.dart';

void main() {
  late AutomergeDoc doc;

  setUp(() => doc = AutomergeDoc.create());
  tearDown(() => doc.dispose());

  group('put and get', () {
    final cases = <String, (Object?, AutomergeValue)>{
      'null': (null, const AutomergeNull()),
      'true': (true, const AutomergeBool(true)),
      'false': (false, const AutomergeBool(false)),
      'int min': (
        -9223372036854775808,
        const AutomergeInt(-9223372036854775808),
      ),
      'int max': (9223372036854775807, const AutomergeInt(9223372036854775807)),
      'double': (0.1, const AutomergeDouble(0.1)),
      'negative zero': (-0.0, const AutomergeDouble(-0.0)),
      'infinity': (double.infinity, const AutomergeDouble(double.infinity)),
      'empty string': ('', const AutomergeString('')),
      'unicode string': ('é 🎨 中', const AutomergeString('é 🎨 中')),
      'bytes': (
        Uint8List.fromList([0, 1, 254, 255]),
        AutomergeBytes(Uint8List.fromList([0, 1, 254, 255])),
      ),
      'empty bytes': (Uint8List(0), AutomergeBytes(Uint8List(0))),
    };
    for (final MapEntry(key: name, value: (written, expected))
        in cases.entries) {
      test('$name round-trips', () {
        doc.put(doc.root, 'k', written);
        expect(doc.get(doc.root, 'k'), expected);
      });
    }

    test('NaN round-trips', () {
      doc.put(doc.root, 'k', double.nan);
      final value = doc.get(doc.root, 'k');
      expect(value, isA<AutomergeDouble>());
      expect((value! as AutomergeDouble).value.isNaN, isTrue);
    });

    test('an absent key reads as Dart null, an explicit null does not', () {
      doc.put(doc.root, 'present', null);
      expect(doc.get(doc.root, 'absent'), isNull);
      expect(doc.get(doc.root, 'present'), const AutomergeNull());
    });

    test('a non-ASCII key round-trips', () {
      doc.put(doc.root, 'clé 🔑', 1);
      expect(doc.keys(doc.root), ['clé 🔑']);
      expect(doc.get(doc.root, 'clé 🔑'), const AutomergeInt(1));
    });

    test('a later put replaces the value and its kind', () {
      doc.put(doc.root, 'k', 1);
      doc.put(doc.root, 'k', 'one');
      expect(doc.get(doc.root, 'k'), const AutomergeString('one'));
    });

    test('an unsupported Dart type is rejected', () {
      expect(() => doc.put(doc.root, 'k', <int>[1]), throwsArgumentError);
      expect(doc.get(doc.root, 'k'), isNull);
    });
  });

  group('nested maps', () {
    test('putMap creates a map reachable through get', () {
      final strokes = doc.putMap(doc.root, 'strokes');
      final stroke = doc.putMap(strokes, 'abc:1');
      doc.put(stroke, 'seed', 7);

      expect(doc.objectType(doc.root), AutomergeObjectType.map);
      expect(doc.objectType(stroke), AutomergeObjectType.map);

      final strokesValue = doc.get(doc.root, 'strokes');
      expect(strokesValue, isA<AutomergeMap>());
      final strokesId = (strokesValue! as AutomergeMap).id;
      expect(strokesId, strokes);

      final strokeId = (doc.get(strokesId, 'abc:1')! as AutomergeMap).id;
      expect(doc.get(strokeId, 'seed'), const AutomergeInt(7));
    });

    test('an object id read in one document works in its fork', () {
      final child = doc.putMap(doc.root, 'child');
      doc.put(child, 'x', 1);
      final fork = doc.fork();
      addTearDown(fork.dispose);
      expect(fork.get(child, 'x'), const AutomergeInt(1));
    });

    test('an object id from another document is reported, not crashed on', () {
      final other = AutomergeDoc.create();
      addTearDown(other.dispose);
      final foreign = other.putMap(other.root, 'm');
      expect(() => doc.objectType(foreign), throwsA(isA<AutomergeException>()));
      expect(
        () => doc.put(foreign, 'k', 1),
        throwsA(isA<AutomergeException>()),
      );
    });

    test('a disposed object id refuses use', () {
      final child = doc.putMap(doc.root, 'child');
      child.dispose();
      expect(child.isDisposed, isTrue);
      expect(() => doc.put(child, 'k', 1), throwsStateError);
      ObjId.root.dispose();
      expect(ObjId.root.isDisposed, isFalse);
    });
  });

  group('keys and delete', () {
    test('keys lists every key in sorted order', () {
      doc.put(doc.root, 'b', 1);
      doc.put(doc.root, 'a', 2);
      doc.putMap(doc.root, 'c');
      expect(doc.keys(doc.root), ['a', 'b', 'c']);
    });

    test('delete removes the key and its value', () {
      doc.put(doc.root, 'a', 1);
      doc.put(doc.root, 'b', 2);
      doc.delete(doc.root, 'a');
      expect(doc.keys(doc.root), ['b']);
      expect(doc.get(doc.root, 'a'), isNull);
    });

    test('an empty map has no keys', () {
      final child = doc.putMap(doc.root, 'child');
      expect(doc.keys(child), isEmpty);
    });
  });

  group('commit and heads', () {
    test('commit returns the new head, or null with nothing pending', () {
      expect(doc.heads, isEmpty);
      doc.put(doc.root, 'k', 1);
      final hash = doc.commit(message: 'first');
      expect(hash, matches(RegExp(r'^[0-9a-f]{64}$')));
      expect(doc.heads, [hash]);
      expect(doc.commit(), isNull);
      expect(doc.heads, [hash]);
    });
  });

  group('save and load', () {
    test('a loaded document has the same content and heads', () {
      final child = doc.putMap(doc.root, 'child');
      doc.put(child, 'bytes', Uint8List.fromList([1, 2, 3]));
      doc.put(doc.root, 'name', 'painting');
      doc.commit();

      final loaded = AutomergeDoc.load(doc.save());
      addTearDown(loaded.dispose);

      expect(loaded.keys(loaded.root), ['child', 'name']);
      expect(
        loaded.get(loaded.root, 'name'),
        const AutomergeString('painting'),
      );
      final loadedChild =
          (loaded.get(loaded.root, 'child')! as AutomergeMap).id;
      expect(
        loaded.get(loadedChild, 'bytes'),
        AutomergeBytes(Uint8List.fromList([1, 2, 3])),
      );
      expect(loaded.heads, doc.heads);
    });

    test('save includes edits that were not committed', () {
      doc.put(doc.root, 'k', 1);
      final loaded = AutomergeDoc.load(doc.save());
      addTearDown(loaded.dispose);
      expect(loaded.get(loaded.root, 'k'), const AutomergeInt(1));
    });

    test('loading bytes that are not a document throws', () {
      expect(
        () => AutomergeDoc.load(Uint8List.fromList('not automerge'.codeUnits)),
        throwsA(
          isA<AutomergeException>().having(
            (e) => e.message,
            'message',
            isNotEmpty,
          ),
        ),
      );
    });
  });

  group('actor id', () {
    test('create uses the given actor id', () {
      final named = AutomergeDoc.create(actorId: '0123456789abcdef');
      addTearDown(named.dispose);
      expect(named.actorId, '0123456789abcdef');
    });

    test('create without an actor id picks distinct random ones', () {
      final other = AutomergeDoc.create();
      addTearDown(other.dispose);
      expect(doc.actorId, matches(RegExp(r'^[0-9a-f]+$')));
      expect(doc.actorId, isNot(other.actorId));
    });

    test('setting the actor id changes it', () {
      doc.actorId = 'aabbcc';
      expect(doc.actorId, 'aabbcc');
    });

    test('an actor id that is not hexadecimal is rejected', () {
      expect(() => doc.actorId = 'xyz', throwsA(isA<AutomergeException>()));
      expect(
        () => AutomergeDoc.create(actorId: 'xyz'),
        throwsA(isA<AutomergeException>()),
      );
    });
  });

  test('a disposed document refuses use and disposes once', () {
    final other = AutomergeDoc.create();
    other.dispose();
    other.dispose();
    expect(other.isDisposed, isTrue);
    expect(() => other.save(), throwsStateError);
    expect(() => other.put(other.root, 'k', 1), throwsStateError);
  });
}
