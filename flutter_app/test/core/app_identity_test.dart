import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mtm/features/app_version/domain/update_channel.dart';
import 'package:mtm/l10n/strings.dart';

/// The Leader rebrand moved the Android identity off `com.mtm.mtm`. These
/// guard the pieces that must agree with it: the Gradle ids, the Kotlin
/// package the manifest's `.MainActivity` resolves against, and the Play
/// Store listing the forced-upgrade gate sends users to.
void main() {
  const appId = 'com.leader.teams';
  final gradle = File('android/app/build.gradle.kts').readAsStringSync();

  test('Gradle namespace and applicationId are the Leader id', () {
    expect(gradle, contains('namespace = "$appId"'));
    expect(gradle, contains('applicationId = "$appId"'));
    expect(gradle, isNot(contains('"com.mtm.mtm"')));
  });

  test('MainActivity lives in the namespace package', () {
    final activity =
        File('android/app/src/main/kotlin/com/leader/teams/MainActivity.kt');
    expect(activity.existsSync(), isTrue);
    expect(activity.readAsLinesSync().first, 'package $appId');
  });

  test('update destinations target the Leader listing', () {
    expect(UpdateChannel.androidStore, endsWith('?id=$appId'));
    expect(UpdateChannel.androidStoreNative, 'market://details?id=$appId');
  });

  test('installed label and app name are the Arabic product name', () {
    final manifest =
        File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
    expect(manifest, contains('android:label="${S.productNameAr}"'));
    expect(S.productNameAr, 'ليدر');
    expect(S.productNameAr.runes, [0x644, 0x64a, 0x62f, 0x631]);
    expect(S.appName, 'ليدر');
    expect(S.productNameEn, 'Leader');
  });
}
