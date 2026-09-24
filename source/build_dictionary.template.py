# build_dictionary.py  —  one-time setup: builds the Dictionary folder
#
# Put this file in the game folder (LegendOfHeros) and double-click it. It
# finds the game data (ThreeKingdom_Data\StreamingAssets\Json) by itself,
# also looking through the usual Steam library locations on every drive; if it
# cannot, paste the path when asked, or pass it on the command line:
#     python build_dictionary.py "D:\...\LegendOfHeros"
#
# It creates a folder named  Dictionary  next to this script containing:
#
#   Translate-Mods.bat       double-click to translate your Workshop mods. Works
#                            on a PC without Python: it downloads a private
#                            copy once (11 MB, no installer, no admin).
#   translate_mod.py         the translator itself (standard library only).
#                            Generated here, nothing else to download.
#   ai_api.ini               AI settings: turn AI translation on/off and put
#                            your API key. Off = free Google Translate.
#                            Never overwritten once it exists.
#   dictionary.json          Chinese -> English from every game field that has
#                            an English twin, plus Conversation option choices.
#   vanilla_untranslated.json  Chinese lines the game itself ships WITHOUT
#                            English (developer notes). Skipped by the translator.
#   glossary.json            Short game terms (names, places, titles, stats,
#                            UI words) the game translates consistently; pinned
#                            when new mod text is sent online.
#   manual.json              created later by the translator: its online
#                            results and your corrections.
#   README.md, LICENSE       full documentation and the MIT license.
#
# Run again whenever the game updates. Game files are never modified.

import os
import re
import sys
import json

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
OUT_DIR = os.path.join(SCRIPT_DIR, "Dictionary")
DICT_PATH = os.path.join(OUT_DIR, "dictionary.json")
UNTRANSLATED_PATH = os.path.join(OUT_DIR, "vanilla_untranslated.json")
GLOSSARY_PATH = os.path.join(OUT_DIR, "glossary.json")
TRANSLATE_PATH = os.path.join(OUT_DIR, "translate_mod.py")
INI_PATH = os.path.join(OUT_DIR, "ai_api.ini")
BAT_PATH = os.path.join(OUT_DIR, "Translate-Mods.bat")
README_PATH = os.path.join(OUT_DIR, "README.md")
LICENSE_PATH = os.path.join(OUT_DIR, "LICENSE")

# Launcher for people who do not have Python: uses an installed Python if one
# works, otherwise downloads the official "embeddable" Python (about 11 MB, no
# installer, no admin rights) into Dictionary\python\ once and uses that.
# curl and tar are part of Windows 10/11. The translator is standard-library
# only, so nothing else is installed.
LAUNCHER_BAT = r"""@echo off
setlocal
cd /d "%~dp0"
set "PY="
py -3 -c "import sys" >nul 2>&1 && set "PY=py -3"
if not defined PY python -c "import sys" >nul 2>&1 && set "PY=python"
if not defined PY if exist "python\python.exe" set "PY=python\python.exe"
if not defined PY (
    echo Python is not installed. Downloading a private copy for this tool ^(about 11 MB, one time^)...
    mkdir python >nul 2>&1
    curl -L -o "python\python.zip" https://www.python.org/ftp/python/3.12.7/python-3.12.7-embed-amd64.zip
    if errorlevel 1 (
        echo Download failed. Check your internet connection and run this again.
        pause
        exit /b 1
    )
    tar -xf "python\python.zip" -C python
    del "python\python.zip"
    set "PY=python\python.exe"
)
%PY% translate_mod.py %*
if errorlevel 1 pause
"""

AI_INI = """; AI settings for translate_mod.py
;
; enabled = no       -> unknown mod text goes to Google Translate (free, no key)
; enabled = yes      -> unknown mod text goes to your AI provider using api_key
; enabled = offline  -> never go online; unknown text is left in needs_translation.json
;
; The provider is recognised from the key itself: OpenAI, Anthropic, Gemini,
; DeepSeek, OpenRouter, Groq, xAI. model is optional (provider default when
; empty). url is only for a custom OpenAI-compatible endpoint, e.g. a local
; server such as Ollama: http://localhost:11434/v1/chat/completions

; context = yes  -> the AI is given, for every line, what kind of text it is,
;                   the mod's name, the surrounding lines of the conversation
;                   with the game's official English, and official translations
;                   of similar vanilla lines. It reads that first, then
;                   translates so the line fits its scene and the game's style.
;                   Better quality; a few hundred more tokens per line.
; context = no   -> lines are translated on their own, glossary only. Cheapest.

[AI]
enabled = no
api_key = 
model = 
url = 
context = yes
"""

# glossary candidates: 2-4 Chinese characters whose English is a short Title-Case term
TERM_ZH = re.compile(r"^[一-鿿]{2,4}$")
TERM_EN = re.compile(r"^[A-Z][A-Za-z'\-]*( [A-Za-z0-9'\-]+){0,2}$")

CJK = re.compile(r"[\u3000-\u303f\u4e00-\u9fff\uff00-\uffef]")
# one {...} record; quoted strings may contain { } without breaking the record
RECORD = re.compile(r'\{(?:"(?:[^"\\]|\\.)*"|[^{}"])*\}', re.DOTALL)
FIELD = re.compile(r'"([A-Za-z0-9_]+)":"([^"]*)"')
DATA_EXT = (".txt", ".json")
OPTION_FIELD = "option"      # inline choice list: &zh&id&id&tc&en&jp&kr& # &zh&...
OPT_ZH, OPT_EN, OPT_LEN = 1, 5, 9


def norm(s):
    return s.replace("\r\n", "\n")


def read_text(path):
    with open(path, "rb") as f:
        raw = f.read()
    for enc in ("utf-8", "utf-8-sig", "gb18030", "utf-16"):
        try:
            return raw.decode(enc)
        except UnicodeDecodeError:
            continue
    return None


def load_json(path, default):
    if not os.path.exists(path):
        return default
    with open(path, "rb") as f:
        try:
            return json.loads(f.read().decode("utf-8-sig"))
        except Exception as e:
            print("  ! could not read existing %s (%s) - starting fresh" % (os.path.basename(path), e))
            return default


def save_json(path, data):
    with open(path, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=1)


def data_files(folder):
    out = []
    for root, dirs, files in os.walk(folder):
        for name in files:
            if name.lower().endswith(DATA_EXT):
                out.append(os.path.join(root, name))
    return sorted(out)


def has_english(s):
    return bool(s) and not CJK.search(s)


def option_segments(val):
    """Yield (zh, en) for every choice inside an option field."""
    for seg in val.split("#"):
        p = seg.split("&")
        if len(p) >= OPT_LEN and CJK.search(p[OPT_ZH]):
            yield p[OPT_ZH], p[OPT_EN]


def build_glossary(dictionary):
    """Pick the short terms the game translates the same way wherever they occur.

    Across the vanilla sentences that contain a candidate term:
      - English present >= 60% of the time with the same capitalisation
        >= 60% of those times  -> kept as is (names, places, titles, stats,
        UI words: "Jing Province", "STR", "Topic").
      - English present >= 80% of the time but usually lower-case in
        sentences -> kept in lower case ("mood", "stamina", "cavalry").
        translate_mod.py pins these only in description-style lines
        (bullets, numbers), not in dialogue, to avoid stiff grammar.
      - anything else (大人, 现在, 结束) is dropped: vanilla itself renders
        it many different ways.
    Terms seen fewer than 3 times are kept only if 3+ characters long.
    """
    cand = {k: v for k, v in dictionary.items() if TERM_ZH.match(k) and TERM_EN.match(v)}
    if not cand:
        return {}
    pat = re.compile("|".join(map(re.escape, sorted(cand, key=len, reverse=True))))
    seen, hit, exact = {}, {}, {}
    for zh, en in dictionary.items():
        if zh in cand:
            continue
        low = en.lower()
        for m in set(pat.findall(zh)):
            seen[m] = seen.get(m, 0) + 1
            if cand[m].lower() in low:
                hit[m] = hit.get(m, 0) + 1
                if cand[m] in en:
                    exact[m] = exact.get(m, 0) + 1
    out = {}
    for k, v in cand.items():
        n = seen.get(k, 0)
        if n >= 3:
            h = hit.get(k, 0)
            if h / n >= 0.6 and exact.get(k, 0) / max(h, 1) >= 0.6:
                out[k] = v
            elif h / n >= 0.8:
                out[k] = v.lower()
        elif len(k) >= 3:
            out[k] = v
    return out


def build(game_folder):
    if not os.path.isdir(game_folder):
        print("Folder not found: " + game_folder)
        return
    os.makedirs(OUT_DIR, exist_ok=True)
    dictionary = load_json(DICT_PATH, {})
    untranslated = set(load_json(UNTRANSLATED_PATH, []))
    before = len(dictionary)
    conflicts = 0
    files = data_files(game_folder)
    print("Scanning %d files in %s ..." % (len(files), game_folder))

    def learn(zh, en):
        nonlocal conflicts
        key, val = norm(zh), norm(en)
        if key in dictionary:
            if dictionary[key] != val:
                conflicts += 1                # same Chinese, different English: keep the first
            return 0
        dictionary[key] = val
        return 1

    for path in files:
        text = read_text(path)
        if text is None:
            continue
        found = 0
        gaps = 0
        for rec in RECORD.finditer(text):
            fields = dict(FIELD.findall(rec.group(0)))
            for name, zh in fields.items():
                if name.endswith("En") or not zh or not CJK.search(zh):
                    continue
                if name == OPTION_FIELD:
                    for ozh, oen in option_segments(zh):
                        if has_english(oen):
                            found += learn(ozh, oen)
                        else:
                            untranslated.add(norm(ozh)); gaps += 1
                    continue
                if (name + "En") not in fields:
                    continue                  # no English twin for this field at all
                en = fields[name + "En"]
                if has_english(en):
                    found += learn(zh, en)
                else:
                    untranslated.add(norm(zh)); gaps += 1
        if found or gaps:
            print("  %-45s +%d   (%d without English)" % (os.path.relpath(path, game_folder), found, gaps))

    # a line counts as untranslated only if no other row gives it an English version
    untranslated = sorted(k for k in untranslated if k not in dictionary)
    save_json(DICT_PATH, dictionary)
    save_json(UNTRANSLATED_PATH, untranslated)
    print("Building glossary ...")
    glossary = build_glossary(dictionary)
    save_json(GLOSSARY_PATH, glossary)
    with open(TRANSLATE_PATH, "w", encoding="utf-8", newline="\n") as f:
        f.write(TRANSLATE_SCRIPT)
    if not os.path.exists(INI_PATH):
        with open(INI_PATH, "w", encoding="utf-8") as f:
            f.write(AI_INI)
    with open(BAT_PATH, "w", encoding="ascii", newline="\r\n") as f:
        f.write(LAUNCHER_BAT)
    old_bat = os.path.join(OUT_DIR, "Translate Mods.bat")     # name used by the first release
    if os.path.exists(old_bat):
        os.remove(old_bat)
    with open(README_PATH, "w", encoding="utf-8") as f:
        f.write(README_MD)
    with open(LICENSE_PATH, "w", encoding="utf-8") as f:
        f.write(LICENSE_TXT)

    print("")
    print("dictionary.json now has %d entries (%d new, %d conflicting duplicates skipped)."
          % (len(dictionary), len(dictionary) - before, conflicts))
    print("vanilla_untranslated.json lists %d lines the game ships without English." % len(untranslated))
    print("glossary.json has %d game terms." % len(glossary))
    print("")
    print("Everything is in: " + OUT_DIR)
    print("  Translate-Mods.bat - double-click to translate (works without Python installed)")
    print("  translate_mod.py   - the translator itself; run directly if you have Python")
    print("  ai_api.ini         - optional: turn on AI translation and put your API key")
    print("  README.md, LICENSE - documentation and MIT license")
    print("")
    print("To share the tool: copy the whole Dictionary folder. Nothing else is needed.")


JSON_SUB = os.path.join("ThreeKingdom_Data", "StreamingAssets", "Json")


def resolve_json(folder):
    """Accept the game root, ThreeKingdom_Data, StreamingAssets or the Json folder itself."""
    folder = os.path.abspath(folder)
    for rel in ("", JSON_SUB, os.path.join("StreamingAssets", "Json"), "Json"):
        cand = os.path.join(folder, rel) if rel else folder
        if os.path.basename(cand) == "Json" and os.path.isfile(os.path.join(cand, "Conversation.json")):
            return cand
    return None


def find_game_json():
    """Look next to / above this script, then in the usual Steam library spots on every drive."""
    here = SCRIPT_DIR
    for _ in range(4):
        found = resolve_json(here)
        if found:
            return found
        parent = os.path.dirname(here)
        if parent == here:
            break
        here = parent
    found = resolve_json(os.getcwd())
    if found:
        return found
    if os.name == "nt":
        for drive in "CDEFGHIJKLMNOPQRSTUVWXYZ":
            for lib in ("SteamLibrary", "Steam", os.path.join("Program Files (x86)", "Steam"),
                        os.path.join("Program Files", "Steam"), os.path.join("Games", "Steam")):
                found = resolve_json(os.path.join(drive + ":\\", lib, "steamapps", "common", "LegendOfHeros"))
                if found:
                    return found
    return None


def main():
    if len(sys.argv) >= 2:
        arg = sys.argv[1].strip().strip('"')
        build(resolve_json(arg) or arg)
        return
    auto = find_game_json()
    if auto:
        print("Game data folder found: " + auto)
        typed = input("Press Enter to use it, or paste another path: ").strip().strip('"')
    else:
        typed = input("Game data folder path (the game's LegendOfHeros folder): ").strip().strip('"')
    folder = typed or auto or ""
    build(resolve_json(folder) or folder)
    input("Press Enter to close...")


# ---------------------------------------------------------------- generated files (verbatim)
README_MD = r'''__README_MD__'''

LICENSE_TXT = '''__LICENSE__'''

TRANSLATE_SCRIPT = r'''__TRANSLATE_MOD_PY__'''


if __name__ == "__main__":
    main()
