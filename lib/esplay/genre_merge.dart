/// EsPlay's servers hold genres in two languages, "Action" next to "Acción",
/// because some items took their metadata in English. The genre screens show
/// each genre once, under its Spanish name, with the titles of both.
library;

const _spanishGenres = <String, String>{
  'action': 'Acción',
  'adventure': 'Aventura',
  'action & adventure': 'Acción y aventura',
  'animation': 'Animación',
  'anime': 'Anime',
  'biography': 'Biografía',
  'children': 'Infantil',
  'comedy': 'Comedia',
  'crime': 'Crimen',
  'documentary': 'Documental',
  'drama': 'Drama',
  'family': 'Familia',
  'fantasy': 'Fantasía',
  'film-noir': 'Cine negro',
  'food': 'Cocina',
  'game show': 'Concursos',
  'history': 'Historia',
  'home and garden': 'Hogar y jardín',
  'horror': 'Terror',
  'kids': 'Infantil',
  'mini-series': 'Miniserie',
  'music': 'Música',
  'musical': 'Musical',
  'mystery': 'Misterio',
  'news': 'Noticias',
  'reality': 'Reality',
  'romance': 'Romance',
  'science fiction': 'Ciencia ficción',
  'sci-fi': 'Ciencia ficción',
  'sci-fi & fantasy': 'Ciencia ficción y fantasía',
  'short': 'Cortometraje',
  'soap': 'Telenovela',
  'sport': 'Deporte',
  'sports': 'Deportes',
  'suspense': 'Suspense',
  'talk': 'Entrevistas',
  'talk show': 'Entrevistas',
  'thriller': 'Suspense',
  'travel': 'Viajes',
  'tv movie': 'Película de TV',
  'war': 'Bélica',
  'war & politics': 'Bélica y política',
  'western': 'Western',
};

/// The Spanish name for a genre the providers wrote in English, else [name].
String esplayGenreName(String name) =>
    _spanishGenres[name.trim().toLowerCase()] ?? name;

String _key(String name) => esplayGenreName(name)
    .toLowerCase()
    .replaceAll(RegExp('[áà]'), 'a')
    .replaceAll(RegExp('[éè]'), 'e')
    .replaceAll(RegExp('[íì]'), 'i')
    .replaceAll(RegExp('[óò]'), 'o')
    .replaceAll(RegExp('[úùü]'), 'u')
    .trim();

/// The ids to filter by for a genre from [mergeGenresBySpanishName]: every
/// merged id with commas, which Emby's `GenreIds` reads as "any of".
String esplayGenreIds(Map<String, dynamic> genre) =>
    genre[_idsField]?.toString() ?? genre['Id']?.toString() ?? '';

const _idsField = 'EsPlayGenreIds';

/// Folds genre items that share a Spanish name into one: its ids are kept
/// for [esplayGenreIds], its counts are added up, and its artwork (and `Id`,
/// which the artwork is fetched by) is the first one that has any. A genre
/// already written in Spanish keeps its own spelling.
List<Map<String, dynamic>> mergeGenresBySpanishName(List<dynamic> genres) {
  final merged = <String, Map<String, dynamic>>{};
  for (final raw in genres.whereType<Map>()) {
    final genre = raw.cast<String, dynamic>();
    final name = genre['Name'] as String? ?? '';
    final key = _key(name);
    final existing = merged[key];
    if (existing == null) {
      merged[key] = {...genre, 'Name': esplayGenreName(name)};
      continue;
    }
    // A Spanish name from the server wins over the translated English one.
    if (esplayGenreName(name) == name) existing['Name'] = name;
    existing[_idsField] = '${esplayGenreIds(existing)},${genre['Id']}';
    for (final entry in genre.entries) {
      final value = entry.value;
      if (entry.key.endsWith('Count') && value is num) {
        existing[entry.key] = ((existing[entry.key] as num?) ?? 0) + value;
      }
    }
    final hasArt = (existing['ImageTags'] as Map?)?.isNotEmpty == true ||
        (existing['BackdropImageTags'] as List?)?.isNotEmpty == true;
    if (!hasArt) {
      for (final field in const [
        'Id',
        'ImageTags',
        'BackdropImageTags',
        'PrimaryImageTag',
        'PrimaryImageAspectRatio',
      ]) {
        if (genre[field] != null) existing[field] = genre[field];
      }
    }
  }
  return merged.values.toList();
}
