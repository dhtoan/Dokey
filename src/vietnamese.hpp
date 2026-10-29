// Dokey Core - Vietnamese letters, tones and syllable rules.
// Copyright (c) 2026 Do Huy Toan. All rights reserved.
#pragma once

#include <string>
#include <vector>

namespace dokey {

enum class Mark : unsigned char { None, Circumflex, Breve, Horn, Stroke };
enum class Tone : unsigned char { None = 0, Acute, Grave, Hook, Tilde, Dot };

inline bool isVowelBase(char c) {
    return c == 'a' || c == 'e' || c == 'i' || c == 'o' || c == 'u' || c == 'y';
}

// Lower-case letter with its diacritic, without tone (e.g. 'a'+Circumflex -> u'â').
char16_t markedLetter(char base, Mark mark);

// Letter with diacritic, tone and case, as one precomposed UTF-16 unit.
char16_t composeLetter(char base, Mark mark, Tone tone, bool upper);

// Reverse of composeLetter. Returns false for characters that are not
// Latin letters used in Vietnamese.
bool decomposeLetter(char16_t ch, char& base, Mark& mark, Tone& tone, bool& upper);

// Combining mark (U+0301...) for a tone, or 0 for Tone::None.
char16_t combiningTone(Tone tone);

// Removes diacritics (not tones; strings checked here never carry tones).
std::u16string stripMarks(const std::u16string& lowerMarked);

// Syllable dictionary built from initials x rhymes (see vietnamese.cpp).
bool isSyllablePrefix(const std::u16string& lowerMarked);
bool isStrippedSyllablePrefix(const std::u16string& lowerUnmarked);
// Can this become a syllable prefix by adding diacritics to its plain letters?
// Letters that already carry a mark must match ("đuo" -> đuô/đươ: yes).
bool isCompatibleSyllablePrefix(const std::u16string& lowerMarked);

// Is this exactly a complete syllable (lower case, with diacritics, no tone)?
bool isSyllable(const std::u16string& lowerMarked);

// Every complete syllable (without tone) in the dictionary.
const std::vector<std::u16string>& allSyllables();

} // namespace dokey
