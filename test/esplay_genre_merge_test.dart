import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/esplay/genre_merge.dart';

void main() {
  test('Action and Acción become one Spanish genre with both ids', () {
    final merged = mergeGenresBySpanishName([
      {'Id': 'a', 'Name': 'Action', 'MovieCount': 3},
      {'Id': 'b', 'Name': 'Acción', 'MovieCount': 5, 'ImageTags': {'Primary': 'x'}},
      {'Id': 'c', 'Name': 'Drama', 'MovieCount': 1},
    ]);
    expect(merged, hasLength(2));
    final action = merged.first;
    expect(action['Name'], 'Acción');
    expect(esplayGenreIds(action), 'a,b');
    expect(action['MovieCount'], 8);
    // The artwork, and the id it's fetched by, come from the one that has it.
    expect(action['Id'], 'b');
    expect(esplayGenreIds(merged.last), 'c');
  });

  test('an English genre alone shows under its Spanish name', () {
    expect(esplayGenreName('Science Fiction'), 'Ciencia ficción');
    expect(esplayGenreName('Rock'), 'Rock');
  });
}
