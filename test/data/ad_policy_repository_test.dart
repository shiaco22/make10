import 'package:flutter_test/flutter_test.dart';
import 'package:make10/data/ad_policy_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('starts at 0 with nothing saved', () async {
    final repo = AdPolicyRepository();
    await repo.load();
    expect(repo.clearsSinceLastAd, 0);
  });

  test('save then a fresh load on a new instance restores the value',
      () async {
    final first = AdPolicyRepository();
    await first.load();
    await first.save(2);

    final second = AdPolicyRepository();
    await second.load();
    expect(second.clearsSinceLastAd, 2);
  });

  test('save overwrites the previously saved value', () async {
    final repo = AdPolicyRepository();
    await repo.load();
    await repo.save(1);
    await repo.save(0);

    final reloaded = AdPolicyRepository();
    await reloaded.load();
    expect(reloaded.clearsSinceLastAd, 0);
  });
}
