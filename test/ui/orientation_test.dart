// Widget tests for the phone/tablet orientation-lock split: phones stay
// locked to portrait via SystemChrome.setPreferredOrientations, while
// tablets are left free to rotate.
//
// The tablet/phone basis is the same one lib/ui/widgets/responsive.dart uses
// for tablet scaling -- the viewport's shortest side vs kTabletBreakpoint --
// so an iPad reads as a tablet in both portrait (820x1180) and landscape
// (1180x820): its shortest side is 820 either way. A naive width-or-height
// check would get the landscape case wrong (1180 wide reads as "not a
// phone" for the wrong reason, or 820 tall could be misread against a
// portrait-only threshold), which is exactly what the landscape test below
// guards against.
//
// SystemChrome.setPreferredOrientations sends a message over
// SystemChannels.platform; there is no real platform in a widget test, so
// it is captured by mocking that channel instead.
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:make10/ui/app.dart';
import 'package:make10/ui/widgets/responsive.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    // See app_boot_test.dart: rootBundle caches loadString's Future per key
    // across the whole process, so each test needs its own fresh load of
    // assets/puzzles.json.
    rootBundle.evict('assets/puzzles.json');
  });

  const portraitOnly = <String>[
    'DeviceOrientation.portraitUp',
    'DeviceOrientation.portraitDown',
  ];
  const unrestricted = <String>[];

  /// Pumps the real app (the same ProviderScope + Make10App tree main.dart
  /// builds) at [size] and returns every
  /// 'SystemChrome.setPreferredOrientations' call observed on
  /// SystemChannels.platform, in the order they were sent.
  ///
  /// The call under test lives in Make10App.build, not in main(), so the
  /// real app tree -- not some stand-in widget -- has to be pumped for it
  /// to run at all.
  Future<List<List<String>>> orientationCallsAt(
    WidgetTester tester,
    Size size,
  ) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final calls = <List<String>>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'SystemChrome.setPreferredOrientations') {
        calls.add(List<String>.from(call.arguments as List));
      }
      return null;
    });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null);
    });

    // Make10App.build runs synchronously on this first pump -- and with it
    // the orientation call -- well before HomeScreen's own puzzles/stats
    // FutureProviders resolve, so there is no need to pump out the loading
    // spinner just to observe it.
    await tester.pumpWidget(const ProviderScope(child: Make10App()));

    return calls;
  }

  testWidgets('phone size (375x812) requests portrait-only', (tester) async {
    final calls = await orientationCallsAt(tester, const Size(375, 812));

    expect(calls, isNotEmpty,
        reason: 'expected at least one setPreferredOrientations call');
    expect(calls, everyElement(equals(portraitOnly)));
  });

  testWidgets('iPad portrait (820x1180) leaves orientation unrestricted',
      (tester) async {
    final calls = await orientationCallsAt(tester, const Size(820, 1180));

    expect(calls, isNotEmpty,
        reason: 'expected at least one setPreferredOrientations call');
    // Per SystemChrome.setPreferredOrientations, an empty list is how the
    // framework asks the platform to allow every orientation again --
    // "unrestricted" is this exact empty list, not merely "not portraitOnly".
    expect(calls, everyElement(equals(unrestricted)));
  });

  testWidgets(
      'iPad landscape (1180x820) also leaves orientation unrestricted -- '
      'proving the basis is the shortest side, not raw width/height',
      (tester) async {
    final calls = await orientationCallsAt(tester, const Size(1180, 820));

    expect(calls, isNotEmpty,
        reason: 'expected at least one setPreferredOrientations call');
    expect(calls, everyElement(equals(unrestricted)));
  });

  group('kTabletBreakpoint boundary', () {
    testWidgets('just below the breakpoint stays locked to portrait',
        (tester) async {
      final size = Size(kTabletBreakpoint - 1, 900);
      final calls = await orientationCallsAt(tester, size);

      expect(calls, isNotEmpty,
          reason: 'expected at least one setPreferredOrientations call');
      expect(calls, everyElement(equals(portraitOnly)));
    });

    testWidgets('at the breakpoint is unrestricted', (tester) async {
      final size = Size(kTabletBreakpoint, 900);
      final calls = await orientationCallsAt(tester, size);

      expect(calls, isNotEmpty,
          reason: 'expected at least one setPreferredOrientations call');
      expect(calls, everyElement(equals(unrestricted)));
    });
  });
}
