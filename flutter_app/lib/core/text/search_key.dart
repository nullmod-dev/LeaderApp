/// The one comparison form for free-text search anywhere in the app.
///
/// **Extracted, not invented.** This is exactly the normalization the roster
/// search has always used (`features/team/domain/member_search.dart`), moved
/// down into `core/` the first time a second surface needed it — the Super
/// Admin's subscriber list. Copying it would have produced two search
/// behaviours that drift, and typing «احمد» would find a colleague on one
/// screen and nothing on another.
///
/// It is deliberately *not* an identity key. Folding أ into ا is right for a
/// lookup aid and wrong for deciding whether two records are the same person
/// or the same team — see `memberNameKey`, which stays strict for that reason.
library;

/// Arabic letters whose written form varies while the word stays the same.
const Map<String, String> _arabicFolds = {
  'أ': 'ا',
  'إ': 'ا',
  'آ': 'ا',
  'ٱ': 'ا',
  'ى': 'ي',
  'ئ': 'ي',
  'ؤ': 'و',
  'ة': 'ه',
};

/// Harakat, tanwin, shadda, sukun and the tatweel stretch character — all
/// decoration over the same consonants.
final RegExp _arabicMarks = RegExp(r'[ـً-ْٰٓ-ٕ]');

/// Arabic-Indic digits, so a number can be typed either way.
const Map<String, String> _digitFolds = {
  '٠': '0',
  '١': '1',
  '٢': '2',
  '٣': '3',
  '٤': '4',
  '٥': '5',
  '٦': '6',
  '٧': '7',
  '٨': '8',
  '٩': '9',
};

/// [value] with every Arabic-Indic (`٠`–`٩`) and Extended Arabic-Indic /
/// Persian (`۰`–`۹`) digit mapped to its ASCII digit, and nothing else
/// touched.
///
/// For **codes** a person copies off a screen or an email — a verification
/// code, a Team Code — where an Arabic keyboard legitimately produces either
/// digit set and a silent strip would turn a correct code into a wrong one.
/// Unlike [searchKey] it folds no letters and changes no case: a code is
/// compared exactly after this, never loosely.
String foldDigitsToAscii(String value) {
  final buffer = StringBuffer();
  for (final rune in value.runes) {
    if (rune >= 0x0660 && rune <= 0x0669) {
      buffer.writeCharCode(0x30 + rune - 0x0660);
    } else if (rune >= 0x06F0 && rune <= 0x06F9) {
      buffer.writeCharCode(0x30 + rune - 0x06F0);
    } else {
      buffer.writeCharCode(rune);
    }
  }
  return buffer.toString();
}

/// [value] trimmed with every run of whitespace collapsed to one space.
String collapseWhitespace(String value) =>
    value.trim().replaceAll(RegExp(r'\s+'), ' ');

/// The comparison form used on **both sides** of every free-text match.
///
/// Whitespace-collapsed, lower-cased, stripped of Arabic diacritics and
/// tatweel, with alef/ya/waw/ta-marbuta variants folded together and
/// Arabic-Indic digits mapped to ASCII. «احمد» finds «أحمد», and «١٠٧» finds
/// «107».
String searchKey(String value) {
  final buffer = StringBuffer();
  for (final rune in collapseWhitespace(value).toLowerCase().runes) {
    final char = String.fromCharCode(rune);
    if (_arabicMarks.hasMatch(char)) continue;
    buffer.write(_arabicFolds[char] ?? _digitFolds[char] ?? char);
  }
  return buffer.toString();
}
