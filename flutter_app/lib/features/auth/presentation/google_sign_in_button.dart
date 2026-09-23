import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_palette.dart';
import '../../../core/theme/app_theme.dart';
import '../../../l10n/strings.dart';
import '../data/google_identity_gateway.dart';
import '../data/mock_onboarding_repository.dart'
    show kMockGoogleUnverifiedPrefix, kMockGoogleVerifiedPrefix;
import '../domain/onboarding_models.dart';

/// The Google entry point on `/login` and `/signup`.
///
/// **Point 18B presentation:** a full-width, first-class surface — the
/// standard multicolour Google "G" beside `المتابعة باستخدام Google` — so
/// Google reads as an equal alternative to the password, not a footnote. The
/// surface itself follows the theme tokens (every palette, light/dark,
/// eye-protect); only the brand mark keeps Google's fixed colours.
///
/// **In progress** while the SDK (or the development chooser) is open and
/// while the caller exchanges the obtained assertion ([loading]): the mark
/// becomes a progress ring, the label says so, and a second tap cannot start
/// a second attempt.
///
/// **On a phone it is always the platform's own chooser.** Pressing it runs
/// [googleIdentityGatewayProvider], which calls the SDK's `authenticate()` —
/// on Android the system "Sign in with Google" credential sheet listing the
/// device's accounts. This app never renders a Google account list, never
/// asks anyone to type a Google address, and never enumerates device
/// accounts.
///
/// **The one exception is a desktop/CI development run**, where no native
/// chooser exists: there a small in-app dialog produces the same
/// `mock-google:<email>` / `mock-google-unverified:<email>` convention
/// `MockOnboardingRepository` already expects, so the verified, unverified and
/// method-link-required paths stay reachable in this repository's tests. See
/// [googleDevelopmentChooserProvider] — it is `false` on Android and iOS, and
/// absent altogether from a release artefact.
class GoogleSignInButton extends ConsumerStatefulWidget {
  const GoogleSignInButton({
    super.key,
    required this.onAttempt,
    this.busy = false,
    this.loading = false,
    this.skin,
  });

  /// Called with the outcome. The caller (login/signup) owns what happens
  /// next — a cancelled attempt is silent, an obtained assertion is handed to
  /// `OnboardingController.signInWithGoogle`.
  final void Function(GoogleSignInAttempt attempt) onAttempt;

  /// Another entry (the password form) is running: disabled, no progress.
  final bool busy;

  /// The caller is exchanging a Google assertion: disabled, with progress.
  final bool loading;

  /// Surface colours for a screen the palette does not own. `null` — every
  /// caller but Login — keeps the token-built surface unchanged.
  ///
  /// It is a *skin*: it moves the fill, the border, the label ink and the
  /// progress ring, and it can put the mark on its own white tile so the
  /// four brand colours stay fully saturated over glass. It changes nothing
  /// about what the button does, when it is enabled, or what it reports.
  final GoogleButtonSkin? skin;

  @override
  ConsumerState<GoogleSignInButton> createState() => _GoogleSignInButtonState();
}

class _GoogleSignInButtonState extends ConsumerState<GoogleSignInButton> {
  /// The SDK sheet (or development chooser) is open.
  bool _pending = false;

  Future<void> _tap() async {
    if (_pending) return;
    final useDevelopmentChooser = ref.read(googleDevelopmentChooserProvider);
    final GoogleSignInAttempt attempt;
    if (useDevelopmentChooser) {
      // The modal chooser is itself the in-progress surface and already
      // blocks a second tap.
      attempt = await _pickMockGoogleIdentity(context);
    } else {
      setState(() => _pending = true);
      attempt = await ref.read(googleIdentityGatewayProvider).signIn();
    }
    if (!mounted) return;
    // Same frame as the caller's own `setState` for an obtained assertion,
    // so the progress state hands over without a flicker.
    setState(() => _pending = false);
    widget.onAttempt(attempt);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final inProgress = widget.loading || _pending;
    final enabled = !widget.busy && !inProgress;
    final label = inProgress ? S.continuingWithGoogle : S.continueWithGoogle;
    final skin = widget.skin;
    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      excludeSemantics: true,
      child: Material(
        color: skin?.fill ?? c.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(skin?.radius ?? AppRadii.lg),
          side: BorderSide(
            color: skin?.border ?? c.line2,
            width: skin == null ? 1 : 1.5,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          key: const Key('google-sign-in'),
          onTap: enabled ? _tap : null,
          child: ConstrainedBox(
            // Above the 48dp floor, matching the primary button's weight.
            constraints: BoxConstraints(minHeight: skin?.minHeight ?? 52),
            child: Padding(
              padding: const EdgeInsetsDirectional.symmetric(
                horizontal: AppSpacing.lg,
                vertical: AppSpacing.sm,
              ),
              child: Row(
                children: [
                  _Mark(
                    skin: skin,
                    inProgress: inProgress,
                    enabled: enabled,
                    progressColor: skin?.progress ?? c.primary,
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Text(
                      label,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: enabled || inProgress
                            ? (skin?.label ?? c.ink)
                            : (skin?.labelDisabled ?? c.ink3),
                        fontSize: skin?.fontSize ?? 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  // Mirrors the mark's width so the label sits optically
                  // centred in the full-width surface.
                  SizedBox(width: _Mark.widthFor(skin) + AppSpacing.md),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Colours a caller may lend the Google surface when the screen it sits on
/// is not painted from `AppColors` — today, only the glass Login.
///
/// Presentation only. Nothing here reaches [GoogleSignInButton]'s behaviour:
/// the same gateway is called, the same [GoogleSignInAttempt] comes back, the
/// same in-progress rules apply, and the mark itself keeps Google's own four
/// colours in every case.
@immutable
class GoogleButtonSkin {
  const GoogleButtonSkin({
    required this.fill,
    required this.border,
    required this.label,
    required this.labelDisabled,
    required this.progress,
    this.plate,
    this.minHeight = 54,
    this.radius = 16,
    this.fontSize = 15.5,
  });

  final Color fill;
  final Color border;
  final Color label;
  final Color labelDisabled;
  final Color progress;

  /// A solid tile under the mark, so the four brand colours keep their
  /// saturation over a translucent surface. `null` draws the bare mark.
  final Color? plate;

  final double minHeight;
  final double radius;
  final double fontSize;
}

/// The leading slot: the brand mark, its optional plate, or the progress
/// ring that replaces it — always the same width, so the label never shifts
/// when an attempt starts.
class _Mark extends StatelessWidget {
  const _Mark({
    required this.skin,
    required this.inProgress,
    required this.enabled,
    required this.progressColor,
  });

  final GoogleButtonSkin? skin;
  final bool inProgress;
  final bool enabled;
  final Color progressColor;

  static const double _plateSize = 34;
  static const double _bareSize = 22;

  static double widthFor(GoogleButtonSkin? skin) =>
      skin?.plate == null ? _bareSize : _plateSize;

  @override
  Widget build(BuildContext context) {
    final plate = skin?.plate;
    final box = widthFor(skin);
    final markSize = plate == null ? _bareSize : 20.0;
    Widget content = SizedBox.square(
      dimension: markSize,
      child: inProgress
          ? Padding(
              padding: const EdgeInsets.all(2),
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: progressColor),
            )
          : Opacity(
              opacity: enabled ? 1 : 0.5,
              child: GoogleGMark(size: markSize),
            ),
    );
    if (plate != null) {
      content = DecoratedBox(
        decoration: BoxDecoration(
          color: plate,
          borderRadius: BorderRadius.circular(10),
          boxShadow: const [
            BoxShadow(
              color: Color(0x38080E12),
              blurRadius: 3,
              offset: Offset(0, 1),
            ),
          ],
        ),
        child: Center(child: content),
      );
    }
    return SizedBox.square(dimension: box, child: content);
  }
}

/// Google's standard multicolour "G", stored as a small local 48×48 PNG.
///
/// The former `CustomPainter` depended on four overlapping paths and could
/// render blank/clipped on a real surface even though the widget existed.
/// The embedded raster keeps the final mark exact and offline without adding
/// a graphics package. A small deterministic vector fallback occupies the
/// same bounds while the first image frame decodes, so even the very first
/// rendered Login frame can never contain a blank icon slot.
///
/// **Brand colours, not theme colours.** Google's branding rules require the
/// mark in its own four colours on every background, so these four values are
/// the one deliberate exception to "every colour is an `AppColors` token" —
/// they must not follow the palette, dark mode or eye-protect.
class GoogleGMark extends StatelessWidget {
  const GoogleGMark({super.key, this.size = 20});

  final double size;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
        child: Image.memory(
          _googleGBytes,
          width: size,
          height: size,
          fit: BoxFit.contain,
          filterQuality: FilterQuality.high,
          isAntiAlias: true,
          gaplessPlayback: true,
          frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
            if (wasSynchronouslyLoaded || frame != null) return child;
            return _GoogleGVectorFallback(size: size);
          },
          errorBuilder: (context, error, stackTrace) =>
              _GoogleGVectorFallback(size: size),
        ),
      );
}

/// First-frame/error fallback for the local brand raster.
///
/// It deliberately uses only strokes and a same-bounds layer: there are no
/// overlapping scaled paths to clip, and the transparent cutout opens the
/// ring before the blue crossbar creates the recognisable `G`.
class _GoogleGVectorFallback extends StatelessWidget {
  const _GoogleGVectorFallback({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) => SizedBox.square(
        dimension: size,
        child: const CustomPaint(painter: _GoogleGVectorPainter()),
      );
}

class _GoogleGVectorPainter extends CustomPainter {
  const _GoogleGVectorPainter();

  static const _blue = Color(0xFF4285F4);
  static const _red = Color(0xFFEA4335);
  static const _yellow = Color(0xFFFBBC05);
  static const _green = Color(0xFF34A853);

  @override
  void paint(Canvas canvas, Size size) {
    final side = math.min(size.width, size.height);
    if (side <= 0) return;
    final bounds = Offset.zero & size;
    final center = bounds.center;
    final stroke = side * 0.19;
    final radius = (side - stroke) / 2;
    final arc = Rect.fromCircle(center: center, radius: radius);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.butt
      ..isAntiAlias = true;

    canvas.saveLayer(bounds, Paint());
    void segment(Color color, double start, double sweep) {
      canvas.drawArc(arc, start, sweep, false, paint..color = color);
    }

    segment(_blue, -0.82, 1.58);
    segment(_green, 0.76, 1.88);
    segment(_yellow, 2.64, 0.62);
    segment(_red, 3.26, 2.20);

    // Open the right side of the ring, then draw Google's blue crossbar.
    canvas.drawRect(
      Rect.fromLTRB(center.dx + side * 0.08, center.dy - stroke * 0.54,
          size.width, center.dy + stroke * 0.54),
      Paint()..blendMode = BlendMode.clear,
    );
    canvas.drawRect(
      Rect.fromLTRB(center.dx - side * 0.02, center.dy - stroke * 0.48,
          size.width - side * 0.04, center.dy + stroke * 0.48),
      Paint()..color = _blue,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_GoogleGVectorPainter oldDelegate) => false;
}

final _googleGBytes = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAADAAAAAwCAYAAABXAvmHAAAFeUlEQVRo3u1Za0xU'
  'Rxg9c2fvLmwVljc+QW20WEFaqqCmIgYji021MbEPrRJrrEZMja3atRVbQ8VK1PaP'
  'qeKrTbXa1FfcsMZU64rFNVqNVCVYNdgaEcpzAZfdu/dOf1StwN3duy/4Uc6/nXv'
  'm+86Z+XZm7lygD334f4MEKhBbS9UgyEQbm4lWloUWJMDKQtEBDhpICCc26Eg1+qM'
  'MoeQn8DhHNohCrxtgn9BpqGWbUCW97HXnJO4SoskaslH8pccNMAPNxV1pPx4wnb+'
  'DgEGkEcO4eaRINAXdAPuU6lDHTqFSGue38K5I4iyIJ9PJBtEaFAPMQKfCIv4MZ+'
  'D+O92gBkM6nUI2iueU0DnF4lfRRTgvng6qeABwgKBMNLM1NC9gBtgquggWsSSowr'
  'uCx0UlNI+jyQw0C+fFMz0qPpOOJoVipd8GWAHVoUxsDHrZ+CgeAFRun9ayU16LT+'
  'IuIAyboSXnYUMjOEjQQAWGMDgwA81sKW5KEwIhHnAzA2wt1aNMLFUcaTRXikFkPi'
  'kQGzxR2To6CI1sJyqkXH/EuzewVXUDR52jFUUZz80mW6Qj3iZna+gClIv7fBXv0g'
  'Aza0YCqEITA3Y6gFY3ETK4caRYuuxLcgBg6ynI56Kv3V0uo4sBABEE+EgNvErlWRP'
  'oLH/EA/BLPCAzA8ysoQCc3Zi3JWDfM4fHZO4E2S697lf2AEBuBkbIMp/ngI/VwMDH'
  'nsPIot4WD8gvo2ku2f0IsJQHrkjfk5XOOiUJBqyuYIESm6C9b58YdXnv1uUFS5+0'
  'yc3AZLdRCAHS6MZAifIG9x4N1jzsiOmkT85AmpJYvWEAAO7bBiZ6MpCoII6ttww8'
  'sMWFejIQ4ykIybQHrK69Rbuo7bRyyhn421MQZtb03OGuC+I0dZ02DjkD1QrihCrg'
  'BAWR6pZO5Stn4DcFcRJ6y8Dg0IfVngy4fRe9KkShqDW1Z9/OnkGMpv7ss7/lNjLZ'
  'GZAYcKhjBA7YRgLApN2mlNj39BUeN7OazSmK/i/FJfmxW/9YXOuJF8a3GT0ZuNO1'
  'wSrx2NCahiox4j9h4nPfAtAHYFABALfahh9UwlMTodMlWLcSIpl2EcCWp4Gd4Zjbn'
  'N1JPABYhLicb0pTZwVC/LrthjnGmuwsT7ysmPKrhve/crg18Bg7GQNMHUPwoXWiy4'
  'BGe+LRHaWpSnZul/hix8rxu6rfPqSE+0L/O4aubS7rs9A4ocYixMUrCazX/Dl7We4'
  'Vr9/I8netWHH41sJtSrij+t2xni14I7xru8t7oSG0NU+pEJN96OFCY4bpx5NJUUr4'
  'JaaxUUXG9NPXqEqReABIj7y6QK7d7QpRZEy3/CoMSFeaBAAy+IcXIjh7sY5znGuR'
  '1E0DabvUImmoCpKunfHZ9VLIB+VC/NNbCdujWNy8lu82Zma05drB1YtT5Z65vVYZ'
  'rrJOvyLENNmgUnx0sPwrTnE5hWrrkPLKl6isWALBES7LGaJ9kO2qv9urxTdzKltmh'
  'NybqlSMr+D5dox56WvoIm92ezZv6BF9cf5n9a76UnjAsf111avyNH9VOSNmBtMEI'
  'RIioq4DYGizDgMAvDX4+LIty9f/4Laf0gQlpWMXHrcP2x1ME0/QWJ+MZNG5bseSo'
  'kKPxr0JvNeUPOVER+IZB2jQjtNaIrDXNPey5uuvm5XwvRZy4OSLurvO/qcsQnzAv'
  '9BM4msujlBZp8/JqWxR2sfnkdxjSsmtECL33xZ1On+Fj6LNTcl8wzt5+t9PetvX7'
  '1L4zjRm2l0xbNNlIdbrr5QZfO2lBNpqeFd//bSv+QNWy3tMKWoKNrlZUs9qYCFZ9'
  'VLI0AYpRNvOeE5LBCma67DFcrZqHXGYdZz9GE8k89ycGw7/M/ehD37hHwjY1clAM'
  '0t1AAAAAElFTkSuQmCC',
);

/// Development-only chooser. Absent — not merely hidden — from a release
/// artefact's call graph, since [GoogleSignInButton] never calls it there.
Future<GoogleSignInAttempt> _pickMockGoogleIdentity(
    BuildContext context) async {
  final result = await showDialog<GoogleSignInAttempt>(
    context: context,
    builder: (context) => const _MockGoogleChooserDialog(),
  );
  return result ?? const GoogleSignInCancelled();
}

/// Owns its own [TextEditingController] so it disposes on the dialog route's
/// own lifecycle — not the instant `showDialog` resolves, which is *before*
/// the closing transition finishes and was disposing the controller out from
/// under it.
class _MockGoogleChooserDialog extends StatefulWidget {
  const _MockGoogleChooserDialog();

  @override
  State<_MockGoogleChooserDialog> createState() =>
      _MockGoogleChooserDialogState();
}

class _MockGoogleChooserDialogState extends State<_MockGoogleChooserDialog> {
  final _email = TextEditingController();
  bool _verified = true;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('اختيار حساب Google (تطوير فقط)'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Directionality(
            textDirection: TextDirection.ltr,
            child: TextField(
              controller: _email,
              autofocus: true,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(labelText: 'name@example.com'),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _verified,
            onChanged: (v) => setState(() => _verified = v),
            title: const Text('البريد موثّق من Google'),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () =>
              Navigator.of(context).pop(const GoogleSignInCancelled()),
          child: const Text(S.cancel),
        ),
        FilledButton(
          onPressed: () {
            final value = _email.text.trim();
            if (value.isEmpty) return;
            final prefix = _verified
                ? kMockGoogleVerifiedPrefix
                : kMockGoogleUnverifiedPrefix;
            Navigator.of(context).pop(
              GoogleSignInObtained(GoogleIdentityAssertion('$prefix$value')),
            );
          },
          child: const Text(S.confirm),
        ),
      ],
    );
  }
}
