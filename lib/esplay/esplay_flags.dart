/// Settings EsPlay keeps out of sight: the theme store, saved themes and the
/// Appearance > Extras section.
const esplayHideThemeStoreAndExtras = true;

/// Also out of sight: Integrations, the media bar settings (EsPlay has one
/// bar), Home's external sources, the app theme and the focus border color.
const esplayHideIntegrationsAndLooks = true;

/// EsPlay has no book, photo or home video libraries: their Home rows and
/// settings are not offered, and Latest leaves those library types out.
const esplayHideBooksPhotosHomeVideos = true;

/// The server comes from the panel, so EsPlay offers no way to pick or type
/// one, and no Quick Connect.
const esplayHideServerChoiceAndQuickConnect = true;

/// Quality is always the maximum (see UserPreferences.get), so the Quality &
/// Decoding screen and the download quality pickers are not offered.
const esplayHideQualitySettings = true;

/// Everyone gets the same media bar: the EsPlay one with trailer and sound,
/// the 5 latest titles from the Películas and Series libraries, advancing
/// every 10 seconds, with IMDb, TMDB and Rotten Tomatoes ratings.
const esplayForceMediaBar = true;

/// The looks are fixed, so the first-run setup wizard never opens and Settings
/// does not offer to run it again.
const esplayNoSetupWizard = true;

/// The navigation's Seerr entry opens EsPlay's own requests instead. Not
/// const only so the tests of Moonfin's own Seerr entry can switch it off.
bool esplayRequestsInNav = true;

/// The libraries the media bar draws from, by name (lower case).
const esplayMediaBarLibraries = {'películas', 'series'};

/// The panel's version policy, which the in-app updater reads instead of
/// Moonfin's GitHub releases: per app, the lowest version still allowed and
/// where to download a newer one.
const esplayVersionPolicyUrl = 'https://panel.esplay.es/api/app/version-policy';
