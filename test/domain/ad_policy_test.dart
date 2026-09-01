import 'package:flutter_test/flutter_test.dart';
import 'package:make10/domain/ad_policy.dart';

void main() {
  group('practice: due after every 3 clears', () {
    test('not due before the 3rd clear', () {
      final policy = AdPolicy();
      expect(
        policy.shouldShowInterstitial(
          mode: GameMode.practice,
          checkpoint: AdCheckpoint.puzzleCleared,
          isEntitled: false,
        ),
        isFalse,
      );
      policy.recordClear(GameMode.practice);
      expect(
        policy.shouldShowInterstitial(
          mode: GameMode.practice,
          checkpoint: AdCheckpoint.puzzleCleared,
          isEntitled: false,
        ),
        isFalse,
      );
      policy.recordClear(GameMode.practice);
      expect(
        policy.shouldShowInterstitial(
          mode: GameMode.practice,
          checkpoint: AdCheckpoint.puzzleCleared,
          isEntitled: false,
        ),
        isFalse,
      );
    });

    test('due exactly on the 3rd clear', () {
      final policy = AdPolicy();
      for (var i = 0; i < 3; i++) {
        policy.recordClear(GameMode.practice);
      }
      expect(policy.clearsSinceLastAd, 3);
      expect(
        policy.shouldShowInterstitial(
          mode: GameMode.practice,
          checkpoint: AdCheckpoint.puzzleCleared,
          isEntitled: false,
        ),
        isTrue,
      );
    });

    test('stays due (does not un-trigger) until onInterstitialShown resets it', () {
      final policy = AdPolicy();
      for (var i = 0; i < 5; i++) {
        policy.recordClear(GameMode.practice);
      }
      expect(
        policy.shouldShowInterstitial(
          mode: GameMode.practice,
          checkpoint: AdCheckpoint.puzzleCleared,
          isEntitled: false,
        ),
        isTrue,
        reason: 'still due even past the exact multiple of 3',
      );
    });

    test('onInterstitialShown restarts the 3-clear window', () {
      final policy = AdPolicy();
      for (var i = 0; i < 3; i++) {
        policy.recordClear(GameMode.practice);
      }
      policy.onInterstitialShown();
      expect(policy.clearsSinceLastAd, 0);
      expect(
        policy.shouldShowInterstitial(
          mode: GameMode.practice,
          checkpoint: AdCheckpoint.puzzleCleared,
          isEntitled: false,
        ),
        isFalse,
      );
      for (var i = 0; i < 2; i++) {
        policy.recordClear(GameMode.practice);
      }
      expect(
        policy.shouldShowInterstitial(
          mode: GameMode.practice,
          checkpoint: AdCheckpoint.puzzleCleared,
          isEntitled: false,
        ),
        isFalse,
      );
      policy.recordClear(GameMode.practice);
      expect(
        policy.shouldShowInterstitial(
          mode: GameMode.practice,
          checkpoint: AdCheckpoint.puzzleCleared,
          isEntitled: false,
        ),
        isTrue,
        reason: 'a fresh 3-clear window should trip again after a reset',
      );
    });

    test(
        'skipped or answer-revealed puzzles never advance the counter, '
        'because the caller only calls recordClear on an actual clear', () {
      final policy = AdPolicy();
      policy.recordClear(GameMode.practice);
      policy.recordClear(GameMode.practice);
      // Any number of skips / answer-reveals would happen here in the real
      // game flow. AdPolicy has no hook for them at all -- they simply never
      // call recordClear, so they cannot move the counter.
      expect(policy.clearsSinceLastAd, 2);
      expect(
        policy.shouldShowInterstitial(
          mode: GameMode.practice,
          checkpoint: AdCheckpoint.puzzleCleared,
          isEntitled: false,
        ),
        isFalse,
      );
      policy.recordClear(GameMode.practice); // the 3rd genuine clear
      expect(
        policy.shouldShowInterstitial(
          mode: GameMode.practice,
          checkpoint: AdCheckpoint.puzzleCleared,
          isEntitled: false,
        ),
        isTrue,
      );
    });

    test('restores the counter saved from a previous app run', () {
      // Simulates: app closed with 2 clears already recorded, then
      // relaunched and the caller restored that count.
      final policy = AdPolicy(initialClearsSinceLastAd: 2);
      expect(policy.clearsSinceLastAd, 2);
      policy.recordClear(GameMode.practice);
      expect(
        policy.shouldShowInterstitial(
          mode: GameMode.practice,
          checkpoint: AdCheckpoint.puzzleCleared,
          isEntitled: false,
        ),
        isTrue,
        reason: 'restoring across restarts must not reset the window to 0; '
            'otherwise closing the app just before the 3rd clear would let a '
            'player dodge every ad',
      );
    });

    test('rejects a negative restored counter', () {
      expect(
        () => AdPolicy(initialClearsSinceLastAd: -1),
        throwsA(isA<AssertionError>()),
      );
    });
  });

  group('entitlement suppresses ads', () {
    test('an entitled player never sees a practice interstitial, no matter the count', () {
      final policy = AdPolicy(initialClearsSinceLastAd: 30);
      expect(
        policy.shouldShowInterstitial(
          mode: GameMode.practice,
          checkpoint: AdCheckpoint.puzzleCleared,
          isEntitled: true,
        ),
        isFalse,
      );
    });

    test('an entitled player never sees a time attack result interstitial', () {
      final policy = AdPolicy();
      expect(
        policy.shouldShowInterstitial(
          mode: GameMode.timeAttack,
          checkpoint: AdCheckpoint.resultScreen,
          isEntitled: true,
        ),
        isFalse,
      );
    });
  });

  group('time attack never interrupts play', () {
    test('never due mid-play, even with many clears and no entitlement', () {
      final policy = AdPolicy();
      for (var i = 0; i < 10; i++) {
        policy.recordClear(GameMode.practice);
      }
      expect(
        policy.shouldShowInterstitial(
          mode: GameMode.timeAttack,
          checkpoint: AdCheckpoint.puzzleCleared,
          isEntitled: false,
        ),
        isFalse,
      );
    });

    test('time attack clears do not advance the practice counter', () {
      final policy = AdPolicy();
      for (var i = 0; i < 5; i++) {
        policy.recordClear(GameMode.timeAttack);
      }
      expect(policy.clearsSinceLastAd, 0);
    });

    test('the result screen is allowed regardless of the (unrelated) clear counter', () {
      final zeroClears = AdPolicy();
      expect(
        zeroClears.shouldShowInterstitial(
          mode: GameMode.timeAttack,
          checkpoint: AdCheckpoint.resultScreen,
          isEntitled: false,
        ),
        isTrue,
      );

      final manyClears = AdPolicy(initialClearsSinceLastAd: 1);
      expect(
        manyClears.shouldShowInterstitial(
          mode: GameMode.timeAttack,
          checkpoint: AdCheckpoint.resultScreen,
          isEntitled: false,
        ),
        isTrue,
      );
    });

    test('practice checkpoint at resultScreen is never due (practice has no result screen)', () {
      final policy = AdPolicy(initialClearsSinceLastAd: 3);
      expect(
        policy.shouldShowInterstitial(
          mode: GameMode.practice,
          checkpoint: AdCheckpoint.resultScreen,
          isEntitled: false,
        ),
        isFalse,
      );
    });
  });
}
