/// Settings EsPlay keeps out of sight: the theme store, saved themes and the
/// Appearance > Extras section.
const esplayHideThemeStoreAndExtras = true;

/// Quality is always the maximum (see UserPreferences.get), so the Quality &
/// Decoding screen and the download quality pickers are not offered.
const esplayHideQualitySettings = true;

/// GitHub `owner/repo` whose releases the in-app updater checks. Empty until
/// the EsPlay fork is published, which turns the updater off so it never
/// offers Moonfin's own releases.
const esplayUpdateRepo = '';
