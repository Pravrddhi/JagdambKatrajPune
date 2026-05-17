// lib/config/app_config.dart
//
// ╔══════════════════════════════════════════════════════════════════╗
// ║              SINGLE SOURCE OF TRUTH FOR BRANDING                ║
// ║  To release this app under a different name / colour scheme,    ║
// ║  edit ONLY this file.  Everything else references it.           ║
// ╚══════════════════════════════════════════════════════════════════╝

class AppConfig {
  // ── App Identity ───────────────────────────────────────────────────────────

  /// Short internal title used by the Flutter engine (e.g. task-switcher label).
  static const String appTitle = 'jagdambkatrajpune';

  /// Human-readable name shown in the AppBar and anywhere the full name appears.
  static const String appDisplayName = 'Jagdhamb Dhol Tasha Pathak Pune';

  // ── Assets ─────────────────────────────────────────────────────────────────

  /// Path to the splash / login logo image.
  static const String logoAsset = 'assets/logos/splash_logo.png';

  // ── Brand Colors (ARGB hex values) ─────────────────────────────────────────
  // These are plain ints so AppColors can still build them as compile-time
  // `const Color(...)` values.

  /// Primary brand colour (default: maroon).
  ///
  /// Used for:
  /// - Main scaffold/app backgrounds in auth flows and splash.
  /// - AppBar background and major header sections.
  /// - Primary text/icon color on light surfaces.
  /// - Borders/highlights in inputs and cards.
  static const int primaryColorValue = 0xFF702D2C;

  /// Accent / highlight colour (default: yellow).
  ///
  /// Used for:
  /// - CTA emphasis (selected chips, important action highlights).
  /// - Primary action contrast on maroon surfaces.
  /// - Progress/loading accents and interactive focus visuals.
  static const int accentColorValue = 0xFFFFD600;

  /// Disabled / muted variant of the primary colour.
  ///
  /// Used for:
  /// - Disabled buttons, secondary hints, subdued labels.
  /// - Placeholder/less-prominent text and low-emphasis borders.
  static const int disabledColorValue = 0xFFA05252;

  /// App card / scaffold background colour.
  ///
  /// Used for:
  /// - Light page backgrounds for content-heavy modules.
  /// - Card containers/dialog body surfaces over brand headers.
  /// - Neutral base to keep text readability high.
  static const int backgroundColorValue = 0xFFF5F5F5;

  // ── API / Backend ──────────────────────────────────────────────────────────

  /// Default API base URL.
  /// Override at build time with: --dart-define=API_BASE_URL=https://your-api/api
  static const String defaultApiBaseUrl =
      // 'https://api.dholtashapathak.co.in/dholtashapathak/api/';
  'http://dev.dholtashapathak.co.in:8080/dholtashapathak/api/';

  /// Pathak identifier sent with registration and instrument-fetch requests.
  static const String pathakId = '1';
}
