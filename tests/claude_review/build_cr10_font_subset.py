#!/usr/bin/env python3
"""Build and verify the pinned Noto subsets used by CR-10."""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import shutil
import subprocess
import sys
import tempfile
import unicodedata
from pathlib import Path

from fontTools.ttLib import TTFont


UPSTREAM_REPOSITORY = "notofonts/noto-cjk"
UPSTREAM_TAG = "Sans2.004"
UPSTREAM_COMMIT = "523d033d6cb47f4a80c58a35753646f5c3608a78"
SOURCE_FONT_SHA256 = "2c76254f6fc379fddfce0a7e84fb5385bb135d3e399294f6eeb6680d0365b74b"
SOURCE_FONT_BYTES = 16437364
SOURCE_LICENSE_SHA256 = "6a73f9541c2de74158c0e7cf6b0a58ef774f5a780bf191f2d7ec9cc53efe2bf2"
REGULAR_SOURCE_GIT_BLOB_SHA = "dc15562470b4f842321894787a0d066879ccff8b"
MEDIUM_SOURCE_FONT_SHA256 = "ca094f6b0001fb048ca39ddd797a0cdb0179e1e55c6561e111c49c3e6a61d7b7"
MEDIUM_SOURCE_FONT_BYTES = 16523632
MEDIUM_SOURCE_GIT_BLOB_SHA = "00b01dff38ff8d0a345c53d64a71bfcf9ec55522"
BOLD_SOURCE_FONT_SHA256 = "b5f0d1a190a7f9b43c310a8850630af12553df32c4c050543f9059732d9b4c0a"
BOLD_SOURCE_FONT_BYTES = 17002248
BOLD_SOURCE_GIT_BLOB_SHA = "ff4c0450e8a5bf0290fbb6013a72dc61a10e8e56"
FONTTOOLS_VERSION = "4.66.1"
FONT_FILENAME = "NotoSansCJKsc-Regular-subset.otf"
LICENSE_FILENAME = "LICENSE.txt"
MANIFEST_FILENAME = "source.json"

CJK_FONT_STYLES = (
    {
        "style": "Regular",
        "weight": 400,
        "role": "comparison_reference",
        "source_filename": "NotoSansCJKsc-Regular.otf",
        "source_path": "Sans/OTF/SimplifiedChinese/NotoSansCJKsc-Regular.otf",
        "source_sha256": SOURCE_FONT_SHA256,
        "source_bytes": SOURCE_FONT_BYTES,
        "source_git_blob_sha": REGULAR_SOURCE_GIT_BLOB_SHA,
        "subset_filename": FONT_FILENAME,
    },
    {
        "style": "Medium",
        "weight": 500,
        "role": "weight_candidate",
        "source_filename": "NotoSansCJKsc-Medium.otf",
        "source_path": "Sans/OTF/SimplifiedChinese/NotoSansCJKsc-Medium.otf",
        "source_sha256": MEDIUM_SOURCE_FONT_SHA256,
        "source_bytes": MEDIUM_SOURCE_FONT_BYTES,
        "source_git_blob_sha": MEDIUM_SOURCE_GIT_BLOB_SHA,
        "subset_filename": "NotoSansCJKsc-Medium-subset.otf",
    },
    {
        "style": "Bold",
        "weight": 700,
        "role": "weight_candidate",
        "source_filename": "NotoSansCJKsc-Bold.otf",
        "source_path": "Sans/OTF/SimplifiedChinese/NotoSansCJKsc-Bold.otf",
        "source_sha256": BOLD_SOURCE_FONT_SHA256,
        "source_bytes": BOLD_SOURCE_FONT_BYTES,
        "source_git_blob_sha": BOLD_SOURCE_GIT_BLOB_SHA,
        "subset_filename": "NotoSansCJKsc-Bold-subset.otf",
    },
)

UPSTREAM_FONT_PATH = CJK_FONT_STYLES[0]["source_path"]
UPSTREAM_FONT_URL = (
    "https://raw.githubusercontent.com/notofonts/noto-cjk/"
    f"{UPSTREAM_COMMIT}/{UPSTREAM_FONT_PATH}"
)

SYMBOLS_REPOSITORY = "notofonts/noto-fonts"
SYMBOLS_COMMIT = "ffebf8c1ee449e544955a7e813c54f9b73848eac"
SYMBOLS_LICENSE_SHA256 = "0dab92d0544f7b233403f14b84a663bdbfa746982eda629e7f4f9ffe1b036feb"
SYMBOL_FONTS = (
    {
        "family": "Noto Sans Symbols2",
        "version": "2.003",
        "source_filename": "NotoSansSymbols2-Regular.ttf",
        "source_path": "hinted/ttf/NotoSansSymbols2/NotoSansSymbols2-Regular.ttf",
        "source_bytes": 656852,
        "source_sha256": "630846d528dbe4c4981370a4d0a9475a1fd1491a129bb411f8e157cdb5de13c6",
        "subset_filename": "NotoSansSymbols2-Regular-subset.ttf",
    },
    {
        "family": "Noto Sans Symbols",
        "version": "2.001",
        "source_filename": "NotoSansSymbols-Regular.ttf",
        "source_path": "hinted/ttf/NotoSansSymbols/NotoSansSymbols-Regular.ttf",
        "source_bytes": 258156,
        "source_sha256": "8f02f31959bbdf6061547a188248e13f84dc5fdd940326ec494675f453f072bb",
        "subset_filename": "NotoSansSymbols-Regular-subset.ttf",
    },
)
EMOJI_REPOSITORY = "google/fonts"
EMOJI_COMMIT = "8b0a1d0f5983c89bc2b93f1b5fb55f9e252744b5"
EMOJI_SOURCE_FILENAME = "NotoEmoji-variable.ttf"
EMOJI_SOURCE_PATH = "ofl/notoemoji/NotoEmoji[wght].ttf"
EMOJI_SOURCE_URL = (
    "https://raw.githubusercontent.com/google/fonts/"
    "8b0a1d0f5983c89bc2b93f1b5fb55f9e252744b5/ofl/notoemoji/NotoEmoji%5Bwght%5D.ttf"
)
EMOJI_SOURCE_BYTES = 1982596
EMOJI_SOURCE_SHA256 = "de6c18832938afc99caf132b39d6a30a19bac7f2e812e28db2535b4608d27551"
EMOJI_LICENSE_SHA256 = "500bb1ccf43df7bbb522112f9133a52b16e1c35e809632f5d8609b179152de5b"
EMOJI_SUBSET_FILENAME = "NotoEmoji-Regular-400-subset.ttf"

GAME_SOURCE_ROOTS = ("data", "scenes", "scripts", "assets")
GAME_TEXT_EXTENSIONS = {
    ".gd",
    ".json",
    ".tscn",
    ".tres",
    ".cfg",
    ".csv",
    ".translation",
    ".po",
}
STRING_LITERAL = re.compile(
    r'"""[\s\S]*?"""'
    r"|'''[\s\S]*?'''"
    r'|"(?:\\.|[^"\\])*"'
    r"|'(?:\\.|[^'\\])*'"
)
ESCAPED_CODEPOINT = re.compile(r"\\(?:u([0-9a-fA-F]{4})|U([0-9a-fA-F]{8}))")


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def gb2312_codepoints() -> set[int]:
    """Decode every valid two-byte position in the standard GB2312 plane."""
    result: set[int] = set()
    for lead in range(0xA1, 0xF8):
        for trail in range(0xA1, 0xFF):
            try:
                decoded = bytes((lead, trail)).decode("gb2312")
            except UnicodeDecodeError:
                continue
            if len(decoded) != 1:
                raise RuntimeError(f"Unexpected GB2312 mapping for {lead:02X}{trail:02X}")
            result.add(ord(decoded))
    if len(result) != 7445:
        raise RuntimeError(f"Expected 7445 GB2312 characters, found {len(result)}")
    return result


def literal_characters(source: str) -> set[int]:
    result: set[int] = set()
    for match in STRING_LITERAL.finditer(source):
        literal = match.group(0)
        body = literal[3:-3] if literal.startswith(('"""', "'''")) else literal[1:-1]
        result.update(ord(char) for char in body if ord(char) > 0x7F)
        for escaped in ESCAPED_CODEPOINT.finditer(body):
            result.add(int(escaped.group(1) or escaped.group(2), 16))
    return result


def game_string_codepoints(repo_root: Path) -> tuple[set[int], list[str]]:
    result: set[int] = set()
    inputs = [repo_root / "project.godot"]
    for relative_root in GAME_SOURCE_ROOTS:
        source_root = repo_root / relative_root
        if not source_root.is_dir():
            raise RuntimeError(f"Required game source directory is missing: {relative_root}")
        inputs.extend(
            path
            for path in source_root.rglob("*")
            if path.is_file()
            and path.suffix.lower() in GAME_TEXT_EXTENSIONS
            and not path.relative_to(repo_root).as_posix().startswith("assets/fonts/")
        )

    source_paths: list[str] = []
    for path in sorted(inputs, key=lambda item: item.relative_to(repo_root).as_posix()):
        text = path.read_text(encoding="utf-8-sig")
        if path.suffix.lower() in {".csv", ".translation", ".po"}:
            result.update(ord(char) for char in text if ord(char) > 0x7F)
        else:
            result.update(literal_characters(text))
        source_paths.append(path.relative_to(repo_root).as_posix())
    return result, source_paths


def font_codepoints(path: Path) -> set[int]:
    font = TTFont(path, lazy=True)
    try:
        return set(font.getBestCmap() or ())
    finally:
        font.close()


def run_subset(source_font: Path, output_font: Path, unicodes_file: Path, repo_root: Path) -> None:
    command = [
        sys.executable,
        "-m",
        "fontTools.subset",
        str(source_font),
        f"--output-file={output_font}",
        f"--unicodes-file={unicodes_file}",
        "--name-IDs=*",
        "--name-legacy",
        "--name-languages=*",
        "--canonical-order",
        "--no-recalc-timestamp",
        "--drop-tables+=DSIG",
    ]
    subprocess.run(command, cwd=repo_root, check=True)


def build_deterministic_subset(
    source_font: Path,
    output_font: Path,
    codepoints: set[int],
    temporary_root: Path,
    repo_root: Path,
    build_name: str,
) -> str:
    if not codepoints:
        raise RuntimeError(f"No required glyphs were assigned to {build_name}.")
    build_root = temporary_root / build_name
    build_root.mkdir()
    unicodes_file = build_root / "required-unicodes.txt"
    unicodes_file.write_text(
        "\n".join(f"U+{codepoint:04X}" for codepoint in sorted(codepoints)) + "\n",
        encoding="ascii",
        newline="\n",
    )
    first_build = build_root / "first.otf"
    second_build = build_root / "repeat.otf"
    run_subset(source_font, first_build, unicodes_file, repo_root)
    run_subset(source_font, second_build, unicodes_file, repo_root)
    first_hash = sha256(first_build)
    if first_hash != sha256(second_build):
        raise RuntimeError(f"Repeated subset generation was not deterministic for {build_name}.")
    subset_missing = codepoints - font_codepoints(first_build)
    if subset_missing:
        raise RuntimeError(
            f"Generated {build_name} is missing required glyphs: " + codepoint_names(subset_missing)
        )
    shutil.copyfile(first_build, output_font)
    return first_hash


def unicode_fingerprint(codepoints: set[int]) -> str:
    encoded = "\n".join(f"{codepoint:06X}" for codepoint in sorted(codepoints)) + "\n"
    return hashlib.sha256(encoded.encode("ascii")).hexdigest()


def codepoint_names(codepoints: set[int], limit: int = 24) -> str:
    entries = []
    for codepoint in sorted(codepoints)[:limit]:
        try:
            name = unicodedata.name(chr(codepoint))
        except ValueError:
            name = "UNNAMED"
        entries.append(f"U+{codepoint:04X} {name}")
    suffix = " ..." if len(codepoints) > limit else ""
    return ", ".join(entries) + suffix


def verify_fonttools_version() -> str:
    import fontTools

    version = fontTools.__version__
    if version != FONTTOOLS_VERSION:
        raise RuntimeError(
            f"Expected fontTools {FONTTOOLS_VERSION}; found {version}. "
            "Use the pinned fontTools release to keep subset output reproducible."
        )
    return version


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source-font", type=Path, required=True)
    parser.add_argument("--medium-source-font", type=Path, required=True)
    parser.add_argument("--bold-source-font", type=Path, required=True)
    parser.add_argument("--symbols2-source-font", type=Path, required=True)
    parser.add_argument("--symbols-source-font", type=Path, required=True)
    parser.add_argument("--emoji-source-font", type=Path, required=True)
    parser.add_argument("--repo-root", type=Path, default=Path(__file__).resolve().parents[2])
    args = parser.parse_args()

    repo_root = args.repo_root.resolve()
    source_font = args.source_font.resolve()
    cjk_sources = {
        "Regular": source_font,
        "Medium": args.medium_source_font.resolve(),
        "Bold": args.bold_source_font.resolve(),
    }
    symbol_sources = {
        "Noto Sans Symbols2": args.symbols2_source_font.resolve(),
        "Noto Sans Symbols": args.symbols_source_font.resolve(),
    }
    emoji_source = args.emoji_source_font.resolve()
    output_dir = repo_root / "assets/fonts/noto_sans_cjk_sc"
    output_font = output_dir / FONT_FILENAME
    license_path = output_dir / LICENSE_FILENAME
    symbol_output_dir = repo_root / "assets/fonts/noto_sans_symbols"
    symbol_license_path = symbol_output_dir / LICENSE_FILENAME
    emoji_output_dir = repo_root / "assets/fonts/noto_emoji"
    emoji_license_path = emoji_output_dir / LICENSE_FILENAME

    for entry in CJK_FONT_STYLES:
        path = cjk_sources[entry["style"]]
        if path.stat().st_size != entry["source_bytes"] or sha256(path) != entry["source_sha256"]:
            raise RuntimeError(
                f"Upstream CJK {entry['style']} source font size or SHA256 does not match the pinned original."
            )
    if not license_path.is_file() or sha256(license_path) != SOURCE_LICENSE_SHA256:
        raise RuntimeError("Packaged CJK SIL OFL license is missing or has the wrong SHA256.")
    if not symbol_license_path.is_file() or sha256(symbol_license_path) != SYMBOLS_LICENSE_SHA256:
        raise RuntimeError("Packaged Noto Symbols SIL OFL license is missing or has the wrong SHA256.")
    if emoji_source.stat().st_size != EMOJI_SOURCE_BYTES or sha256(emoji_source) != EMOJI_SOURCE_SHA256:
        raise RuntimeError("Pinned Noto Emoji source font size or SHA256 does not match the original.")
    if not emoji_license_path.is_file() or sha256(emoji_license_path) != EMOJI_LICENSE_SHA256:
        raise RuntimeError("Packaged Noto Emoji SIL OFL license is missing or has the wrong SHA256.")
    for entry in SYMBOL_FONTS:
        path = symbol_sources[entry["family"]]
        if path.stat().st_size != entry["source_bytes"] or sha256(path) != entry["source_sha256"]:
            raise RuntimeError(f"Pinned source font size or SHA256 does not match {entry['family']}.")
    fonttools_version = verify_fonttools_version()

    gb2312 = gb2312_codepoints()
    game_strings, source_paths = game_string_codepoints(repo_root)
    required = gb2312 | game_strings
    output_dir.mkdir(parents=True, exist_ok=True)
    symbol_output_dir.mkdir(parents=True, exist_ok=True)
    emoji_output_dir.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="sot-cr10-font-") as temporary:
        temporary_root = Path(temporary)
        emoji_static = temporary_root / "NotoEmoji-Regular-400.ttf"
        from fontTools.ttLib import TTFont
        from fontTools.varLib.instancer import instantiateVariableFont

        variable_emoji = TTFont(emoji_source)
        try:
            axes = {
                axis.axisTag: axis.defaultValue
                for axis in variable_emoji["fvar"].axes
            }
            if axes != {"wght": 400.0}:
                raise RuntimeError(f"Unexpected Noto Emoji axes/default instance: {axes}")
            static_emoji = instantiateVariableFont(variable_emoji, {"wght": 400.0})
            try:
                if "fvar" in static_emoji or "gvar" in static_emoji:
                    raise RuntimeError("Default Noto Emoji instance retained variable font tables.")
                static_emoji.recalcTimestamp = False
                static_emoji["head"].created = variable_emoji["head"].created
                static_emoji["head"].modified = variable_emoji["head"].modified
                static_emoji.save(emoji_static, reorderTables=True)
            finally:
                static_emoji.close()
        finally:
            variable_emoji.close()

        # Allocate each codepoint to the first pinned bundled font that covers it.
        candidates = [("Noto Sans CJK SC", source_font)]
        candidates.extend((entry["family"], symbol_sources[entry["family"]]) for entry in SYMBOL_FONTS)
        candidates.append(("Noto Emoji Regular 400", emoji_static))
        remaining = required.copy()
        assigned: dict[str, set[int]] = {}
        for family, path in candidates:
            coverage = remaining & font_codepoints(path)
            assigned[family] = coverage
            remaining -= coverage
        if remaining:
            raise RuntimeError("Pinned package fonts are missing required glyphs: " + codepoint_names(remaining))

        cjk_codepoints = assigned["Noto Sans CJK SC"]
        symbol_codepoints = {entry["family"]: assigned[entry["family"]] for entry in SYMBOL_FONTS}
        emoji_codepoints = assigned["Noto Emoji Regular 400"]

        cjk_font_builds = {}
        for entry in CJK_FONT_STYLES:
            style = entry["style"]
            subset_path = output_dir / entry["subset_filename"]
            subset_hash = build_deterministic_subset(
                cjk_sources[style],
                subset_path,
                cjk_codepoints,
                temporary_root,
                repo_root,
                f"cjk_{style.lower()}",
            )
            cjk_font_builds[style] = {
                "path": subset_path,
                "sha256": subset_hash,
                "coverage": font_codepoints(subset_path),
            }

        regular_coverage = cjk_font_builds["Regular"]["coverage"]
        for entry in CJK_FONT_STYLES[1:]:
            style = entry["style"]
            style_coverage = cjk_font_builds[style]["coverage"]
            if style_coverage != regular_coverage:
                missing = regular_coverage - style_coverage
                extra = style_coverage - regular_coverage
                raise RuntimeError(
                    f"Generated CJK {style} Unicode coverage differs from Regular; "
                    f"missing: {codepoint_names(missing)}; extra: {codepoint_names(extra)}"
                )

        cjk_hash = cjk_font_builds["Regular"]["sha256"]
        symbol_manifests = []
        symbol_hashes = {}
        for entry in SYMBOL_FONTS:
            family = entry["family"]
            subset_filename = entry["subset_filename"]
            output_path = symbol_output_dir / subset_filename
            subset_hash = build_deterministic_subset(
                symbol_sources[family],
                output_path,
                symbol_codepoints[family],
                temporary_root,
                repo_root,
                family.replace(" ", "_").lower(),
            )
            symbol_hashes[family] = subset_hash
            symbol_manifests.append(
                {
                    "family": family,
                    "version": entry["version"],
                    "font_file": subset_filename,
                    "font_sha256": subset_hash,
                    "font_bytes": output_path.stat().st_size,
                    "source_filename": entry["source_filename"],
                    "source_path": entry["source_path"],
                    "source_url": (
                        f"https://raw.githubusercontent.com/{SYMBOLS_REPOSITORY}/"
                        f"{SYMBOLS_COMMIT}/{entry['source_path']}"
                    ),
                    "source_sha256": entry["source_sha256"],
                    "source_bytes": entry["source_bytes"],
                    "required_codepoints": sorted(symbol_codepoints[family]),
                }
            )
        emoji_output = emoji_output_dir / EMOJI_SUBSET_FILENAME
        emoji_hash = build_deterministic_subset(
            emoji_static,
            emoji_output,
            emoji_codepoints,
            temporary_root,
            repo_root,
            "noto_emoji_regular_400",
        )

    combined = cjk_codepoints.copy()
    for glyphs in symbol_codepoints.values():
        combined.update(glyphs)
    combined.update(emoji_codepoints)
    if combined != required:
        raise RuntimeError("Generated package fallback chain does not cover the complete required set.")

    cjk_coverage = cjk_font_builds["Regular"]["coverage"]
    cjk_font_manifests = []
    for entry in CJK_FONT_STYLES:
        style = entry["style"]
        build = cjk_font_builds[style]
        cjk_font_manifests.append(
            {
                "style": style,
                "weight": entry["weight"],
                "role": entry["role"],
                "approval_status": "not_approved",
                "source": {
                    "repository": UPSTREAM_REPOSITORY,
                    "tag": UPSTREAM_TAG,
                    "commit": UPSTREAM_COMMIT,
                    "font_path": entry["source_path"],
                    "font_url": (
                        f"https://raw.githubusercontent.com/{UPSTREAM_REPOSITORY}/"
                        f"{UPSTREAM_COMMIT}/{entry['source_path']}"
                    ),
                    "source_filename": entry["source_filename"],
                    "source_font_sha256": entry["source_sha256"],
                    "source_font_bytes": entry["source_bytes"],
                    "source_git_blob_sha": entry["source_git_blob_sha"],
                    "license_file": LICENSE_FILENAME,
                    "license_sha256": SOURCE_LICENSE_SHA256,
                },
                "subset": {
                    "font_file": entry["subset_filename"],
                    "font_sha256": build["sha256"],
                    "font_bytes": build["path"].stat().st_size,
                    "fonttools_version": fonttools_version,
                    "method": "fontTools.subset with canonical table order and fixed Unicode input",
                    "unicode_list_sha256": unicode_fingerprint(cjk_codepoints),
                    "unicode_coverage_sha256": unicode_fingerprint(build["coverage"]),
                    "unicode_coverage_count": len(build["coverage"]),
                },
            }
        )

    cjk_manifest = {
        "family": "Noto Sans CJK SC",
        "style": "Regular",
        "license": "SIL Open Font License 1.1",
        "upstream": {
            "repository": UPSTREAM_REPOSITORY,
            "tag": UPSTREAM_TAG,
            "commit": UPSTREAM_COMMIT,
            "font_path": UPSTREAM_FONT_PATH,
            "font_url": UPSTREAM_FONT_URL,
            "source_filename": "NotoSansCJKsc-Regular.otf",
            "source_font_sha256": SOURCE_FONT_SHA256,
            "source_font_bytes": SOURCE_FONT_BYTES,
            "license_file": LICENSE_FILENAME,
            "license_sha256": SOURCE_LICENSE_SHA256,
            "reserved_font_name_declared": False,
        },
        "subset": {
            "font_file": FONT_FILENAME,
            "font_sha256": cjk_hash,
            "font_bytes": output_font.stat().st_size,
            "fonttools_version": fonttools_version,
            "method": "fontTools.subset with canonical table order and fixed Unicode input",
            "gb2312_character_count": len(gb2312),
            "game_string_character_count": len(game_strings),
            "unique_character_count": len(required),
            "unicode_list_sha256": unicode_fingerprint(required),
            "required_codepoints": sorted(required),
            "primary_font_codepoints": sorted(cjk_codepoints),
            "unicode_coverage_count": len(cjk_coverage),
            "unicode_coverage_sha256": unicode_fingerprint(cjk_coverage),
            "supplementary_fallbacks": [
                {
                    "family": row["family"],
                    "font_file": row["font_file"],
                    "required_codepoints": row["required_codepoints"],
                }
                for row in symbol_manifests
            ],
            "game_string_sources": source_paths,
        },
        "fonts": cjk_font_manifests,
    }
    symbol_manifest = {
        "upstream": {
            "repository": SYMBOLS_REPOSITORY,
            "commit": SYMBOLS_COMMIT,
            "license": "SIL Open Font License 1.1",
            "license_file": LICENSE_FILENAME,
            "license_sha256": SYMBOLS_LICENSE_SHA256,
            "reserved_font_name_declared": False,
        },
        "fonttools_version": fonttools_version,
        "method": "fontTools.subset with canonical table order and fixed Unicode input",
        "fonts": symbol_manifests,
    }
    emoji_manifest = {
        "upstream": {
            "repository": EMOJI_REPOSITORY,
            "commit": EMOJI_COMMIT,
            "source_filename": EMOJI_SOURCE_FILENAME,
            "source_path": EMOJI_SOURCE_PATH,
            "source_url": EMOJI_SOURCE_URL,
            "source_sha256": EMOJI_SOURCE_SHA256,
            "source_bytes": EMOJI_SOURCE_BYTES,
            "license": "SIL Open Font License 1.1",
            "license_file": LICENSE_FILENAME,
            "license_sha256": EMOJI_LICENSE_SHA256,
            "reserved_font_name_declared": False,
            "variable_axes": {"wght": {"min": 300, "default": 400, "max": 700}},
        },
        "subset": {
            "family": "Noto Emoji",
            "style": "Regular",
            "weight": 400,
            "font_file": EMOJI_SUBSET_FILENAME,
            "font_sha256": emoji_hash,
            "font_bytes": emoji_output.stat().st_size,
            "fonttools_version": fonttools_version,
            "method": "instantiate default wght=400 vector outline, then deterministic fontTools subset",
            "required_codepoints": sorted(emoji_codepoints),
        },
    }
    (output_dir / MANIFEST_FILENAME).write_text(
        json.dumps(cjk_manifest, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
        newline="\n",
    )
    (symbol_output_dir / MANIFEST_FILENAME).write_text(
        json.dumps(symbol_manifest, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
        newline="\n",
    )
    (emoji_output_dir / MANIFEST_FILENAME).write_text(
        json.dumps(emoji_manifest, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
        newline="\n",
    )

    print(
        "CR10_FONT_SUBSET_RESULT "
        f"gb2312={len(gb2312)} game_strings={len(game_strings)} "
        f"unique={len(required)} cjk_fonts={len(cjk_font_manifests)} "
        f"cjk_coverage={len(cjk_coverage)} cjk_sha256={cjk_hash} "
        f"symbol_fonts={len(symbol_manifests)} "
        f"emoji_glyphs={len(emoji_codepoints)} emoji_sha256={emoji_hash} deterministic=true"
    )
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, RuntimeError, subprocess.CalledProcessError) as error:
        print(f"CR10_FONT_SUBSET_ERROR {error}", file=sys.stderr)
        raise SystemExit(1)
