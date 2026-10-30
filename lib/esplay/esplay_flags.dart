/// Settings EsPlay keeps out of sight: the theme store, saved themes and the
/// Appearance > Extras section.
const esplayHideThemeStoreAndExtras = true;

/// Quality is always the maximum (see UserPreferences.get), so the Quality &
/// Decoding screen and the download quality pickers are not offered.
const esplayHideQualitySettings = true;

/// The panel's version policy, which the in-app updater reads instead of
/// Moonfin's GitHub releases: per app, the lowest version still allowed and
/// where to download a newer one.
const esplayVersionPolicyUrl = 'https://panel.esplay.es/api/app/version-policy';
