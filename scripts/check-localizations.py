#!/usr/bin/env python3
"""Checks that every localizable literal in the Swift sources exists in all Localizable.strings files.

It looks for string literals passed to `String(localized:)` and to the SwiftUI initializers that take a
`LocalizedStringKey`, converts `\\(...)` interpolations to format specifiers and verifies that the key is
present in every `*.lproj/Localizable.strings`. It also checks that all languages have the same keys.
Only the standard library is used.
"""

import itertools
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
SOURCES = ROOT / "Itinerary"
RESOURCES = SOURCES / "Resources"

LITERAL = r'"((?:[^"\\]|\\.)*)"'
CALLS = [
    r"String\(localized:\s*",
    r"(?<![A-Za-z.])Text\(",
    r"(?<![A-Za-z.])Button\(",
    r"(?<![A-Za-z.])Label\(",
    r"(?<![A-Za-z.])Section\(",
    r"(?<![A-Za-z.])Toggle\(",
    r"(?<![A-Za-z.])NavigationLink\(",
    r"\.navigationTitle\(",
    r"(?<![A-Za-z.])TextField\(",
    r"(?<![A-Za-z.])SecureField\(",
    r"(?<![A-Za-z.])Picker\(",
    r"(?<![A-Za-z.])LabeledContent\(",
    r"(?<![A-Za-z.])DatePicker\(",
]
# `return "..."` inside a property typed `LocalizedStringKey` is checked through this marker.
LOCALIZED_KEY_BLOCK = re.compile(r"LocalizedStringKey\s*\{(.*?)\n    \}", re.S)


def strip_interpolations(literal):
    """Returns the literal split around `\\(...)` interpolations."""
    parts, current, index = [], "", 0
    while index < len(literal):
        if literal.startswith("\\(", index):
            depth, index = 1, index + 2
            while index < len(literal) and depth:
                depth += {"(": 1, ")": -1}.get(literal[index], 0)
                index += 1
            parts.append(current)
            current = ""
        else:
            current += literal[index]
            index += 1
    parts.append(current)
    return parts


def candidates(literal):
    parts = strip_interpolations(literal)
    if len(parts) == 1:
        return [parts[0]]
    keys = []
    for specifiers in itertools.product(["%@", "%lld", "%lf"], repeat=len(parts) - 1):
        key = parts[0]
        for specifier, part in zip(specifiers, parts[1:]):
            key += specifier + part
        keys.append(key)
    return keys


def parse_strings(path):
    text = path.read_text(encoding="utf-8")
    return {key.replace('\\"', '"').replace("\\\\", "\\") for key in re.findall(r'^"((?:[^"\\]|\\.)*)"\s*=', text, re.M)}


def main():
    tables = {path.parent.name: parse_strings(path) for path in sorted(RESOURCES.glob("*.lproj/Localizable.strings"))}
    if not tables:
        print("No Localizable.strings files found.")
        return 1

    used = {}
    for source in sorted(SOURCES.rglob("*.swift")):
        text = source.read_text(encoding="utf-8")
        for call in CALLS:
            for match in re.finditer(call + LITERAL, text):
                used.setdefault(match.group(1), set()).add(source.relative_to(ROOT).as_posix())
        for line in re.findall(r":\s*LocalizedStringKey\s*=(.*)", text):
            for match in re.finditer(LITERAL, line):
                used.setdefault(match.group(1), set()).add(source.relative_to(ROOT).as_posix())
        for block in LOCALIZED_KEY_BLOCK.findall(text):
            for match in re.finditer(r"return\s+" + LITERAL, block):
                used.setdefault(match.group(1), set()).add(source.relative_to(ROOT).as_posix())

    errors = []
    for literal, files in sorted(used.items()):
        if not literal.strip():
            continue
        for language, keys in tables.items():
            if not any(candidate in keys for candidate in candidates(literal)):
                errors.append(f'{language}: missing "{literal}" (used in {", ".join(sorted(files))})')

    reference_language, reference_keys = next(iter(tables.items()))
    for language, keys in tables.items():
        for key in sorted(reference_keys - keys):
            errors.append(f'{language}: missing "{key}" that exists in {reference_language}')
        for key in sorted(keys - reference_keys):
            errors.append(f'{reference_language}: missing "{key}" that exists in {language}')

    if errors:
        print("\n".join(sorted(set(errors))))
        print(f"\n{len(set(errors))} localization problem(s) found.")
        return 1
    print(f"Localizations OK: {len(used)} literals checked against {', '.join(tables)}.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
