@echo off
setlocal
cd /d "%~dp0"
rem ---- Heroes' Vow: Three Kingdoms mod translator - one-time setup.
rem ---- Double-click. Works without Python: a private copy is downloaded once.
set "PY="
py -3 -c "import sys" >nul 2>&1 && set "PY=py -3"
if not defined PY python -c "import sys" >nul 2>&1 && set "PY=python"
if not defined PY if exist "Dictionary\python\python.exe" set "PY=Dictionary\python\python.exe"
if not defined PY (
    echo Python is not installed. Downloading a private copy for this tool ^(about 11 MB, one time^)...
    mkdir "Dictionary\python" >nul 2>&1
    curl -L -o "Dictionary\python\python.zip" https://www.python.org/ftp/python/3.12.7/python-3.12.7-embed-amd64.zip
    if errorlevel 1 (
        echo Download failed. Check your internet connection and run this again.
        pause
        exit /b 1
    )
    tar -xf "Dictionary\python\python.zip" -C "Dictionary\python"
    del "Dictionary\python\python.zip"
    set "PY=Dictionary\python\python.exe"
)
rem ---- the Python program is the rest of this file; run it with this file's folder as its home
%PY% -c "import sys,io;p=sys.argv[1];s=io.open(p,encoding='utf-8').read().split(':::'+'PYTHON'+':::',1)[1];sys.argv=[p]+sys.argv[2:];g={'__file__':p,'__name__':'__main__'};exec(compile(s,p,'exec'),g)" "%~f0" %*
if errorlevel 1 pause
exit /b
:::PYTHON:::
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
#                            English. For information only: the translator
#                            still translates them online when a mod shows them.
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

# Han ideographs only. Fullwidth punctuation (【】，：) also appears in the game's own
# ENGLISH, so counting it as Chinese threw away every official line that used it.
CJK = re.compile(r"[\u3400-\u4dbf\u4e00-\u9fff]")
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
    print("vanilla_untranslated.json lists %d lines the game ships without English (for information)." % len(untranslated))
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
README_MD = r'''# Heroes' Vow: Three Kingdoms — Workshop Mod Translator

Translates Chinese Steam Workshop mods for *Heroes' Vow: Three Kingdoms* (Steam app 3020510) into English, using the game's own official translations wherever they exist and an online translator only for text the modder actually wrote.

One file to download, one double-click to set up, one double-click to translate every subscribed mod.

---

## Why this exists

The game's data lives in plain JSON files and is fully translated to English. Most Workshop mods are written in Chinese, and when a mod overrides a game file the affected text shows in Chinese in-game. Almost all of that text, however, is copied unchanged from the game, so its official English already exists in the game folder. This tool reuses it.

## How it works

1. **Build a dictionary from the game.** Every game field that has an English twin (`dialog` / `dialogEn`, `name` / `nameEn`, and so on) becomes a Chinese → English pair. The choices inside conversation `option` fields are harvested too. Result: about 68,000 pairs.
2. **Translate a mod from the dictionary.** Every Chinese display field in the mod that matches a known line gets the game's official English. Engine fields (`condition`, `formula`, IDs, tags) are never touched.
3. **Send only new text online.** Lines the modder wrote or edited go to Google Translate (free) or, if you enable it, to an AI model with your own API key. Game terms from a glossary are pinned so names, places, titles and stats stay consistent with the game. Every online result must pass a sanity check (no leftover Chinese, no lost placeholder, English script, sane length) or it is left for you in `needs_translation.json` instead of being saved wrong.
4. **Remember.** Online results and any corrections you make are kept in `manual.json` and reused for every future mod.

What is deliberately **not** translated:

- rows the game itself never displays (`"func":"1"` logic/comment rows in conversation files)
- fields whose English twin is already filled (the game shows that English already)

## Install (once)

1. Download `Build-Dictionary.bat`.
2. Put it in the game folder, the one containing `ThreeKingdom_Data`. Typically:
   `D:\SteamLibrary\steamapps\common\LegendOfHeros`
3. Double-click it. It finds the game data by itself, then press Enter.

It creates a `Dictionary` folder next to it. If Python is not installed on your PC, it downloads the official *embeddable* Python (about 11 MB, no installer, no admin rights) into `Dictionary\python\` and uses that. Nothing is installed anywhere else on your system.

Run it again whenever the game updates.

## Translate mods

Double-click `Dictionary\Translate-Mods.bat`.

```
Workshop folder found: D:\SteamLibrary\steamapps\workshop\content\3020510
Press Enter to translate every mod in it, or paste one mod folder path:
```

Press Enter and every subscribed mod is translated in turn. A summary is printed at the end. Each mod keeps its untouched originals in `<mod>\backup_original\`.

You can also paste a single mod folder, or drag a folder onto the `.bat`.

Rerunning is safe: mods already translated report `0 translated` and are left alone. A mod that Steam has updated since is recognised (its files are newer than its backup) and translated again with a fresh backup.

**To restore a mod to Chinese**, copy the files from its `backup_original` folder back over the mod files, or simply verify the mod's files in Steam.

## AI translation (optional)

Open `Dictionary\ai_api.ini`:

```ini
[AI]
enabled = no
api_key =
model =
url =
context = yes
```

| Setting | Meaning |
|---|---|
| `enabled` | `no` = Google Translate, free, no key. `yes` = your AI provider. `offline` = never go online; unknown lines are left in `needs_translation.json`. |
| `api_key` | Key from OpenAI, Anthropic, Google Gemini, DeepSeek, OpenRouter, Groq or xAI. The provider is recognised from the key itself. |
| `model` | Optional. Leave empty for the provider's default. |
| `url` | Optional. Only for a custom OpenAI-compatible endpoint, e.g. a local server: `http://localhost:11434/v1/chat/completions` |
| `context` | `yes` = for every line the AI also receives what kind of text it is, the mod's name, the surrounding conversation with the game's official English, and official translations of the closest vanilla lines. It reads that first, then translates so the line fits its scene and the game's style. `no` = bare lines plus glossary; cheapest. |

Typical cost with AI enabled is a few cents per mod. Google Translate is free but weaker on tone and game terms.

## Files in the Dictionary folder

| File | What it is |
|---|---|
| `Translate-Mods.bat` | Double-click to translate. Uses installed Python or the private copy. |
| `translate_mod.py` | The translator itself. Standard library only. |
| `ai_api.ini` | Your AI settings. Never overwritten by a rebuild. |
| `dictionary.json` | Chinese → English from the game files. |
| `glossary.json` | Game terms the game translates consistently, pinned during online translation. |
| `vanilla_untranslated.json` | Chinese lines the game itself ships without English. Information only; when a mod shows one of them it is translated online like any other line. |
| `manual.json` | Online results and your corrections. Edit freely; it always wins. |
| `python\` | Only if Python was not installed: the private embeddable Python. |

Inside a translated mod:

| File | What it is |
|---|---|
| `backup_original\` | The mod's untouched files. |
| `needs_translation.json` | Lines that could not be translated. Fill in the English and run again; they are merged into `manual.json`. |
| `translate_log.txt` | Why each leftover line failed. |

## Fixing a translation

If a line reads badly in-game, find it in `Dictionary\manual.json`, change the English, and run the translator again. Your version replaces the old one in every mod that uses that line.

## Transparency and safety

This tool is a plain text script. You can read every line of it.

- `Build-Dictionary.bat` is a 25-line batch launcher followed by the Python program itself, appended as text. Open it in Notepad to inspect it. The `source\` folder of this release contains the same program as separate `.py` files, and `pack.py`, which shows exactly how the `.bat` is assembled from them.
- Network access, complete list:
  - `python.org` — only if no Python is installed, to download the official embeddable Python once.
  - `translate.googleapis.com` — Google Translate, only for lines not found in the dictionary.
  - your AI provider's API — only when `enabled = yes` in `ai_api.ini`, and only with the key you put there.
  - Nothing else. No telemetry, no update checks, no data sent anywhere about you or your mods.
- Files written: the `Dictionary` folder next to the setup file, and inside each translated mod its own files plus `backup_original\`. Game files are read, never modified.
- No installer, no registry changes, no services, no admin rights.

Windows SmartScreen may warn about an unrecognised `.bat` file, as it does for any script that is not code-signed. That is the generic warning for scripts; the source is above for anyone who wants to verify what it does.

## Troubleshooting

- **"Game data folder found" shows the wrong path** — paste the correct one; the game folder, `ThreeKingdom_Data`, or the `Json` folder are all accepted.
- **"That folder belongs to a different game's Workshop"** — the tool only works inside `workshop\content\3020510`. Other games are refused on purpose.
- **Lines still in Chinese after translating** — they are logic rows the game never shows, or lines listed in `needs_translation.json` because the online translation failed. Fill those in and run again.
- **AI: "rejected the API key"** — check `api_key` in `ai_api.ini`. **404** — wrong `model` name for that provider; leave it empty for the default.
- **A Google line is nonsense** — fix it in `manual.json`, or enable AI translation.

## License

MIT. See `LICENSE`.
'''

LICENSE_TXT = '''MIT License

Copyright (c) 2026 kbmqa (https://github.com/kbmqa)

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
'''

TRANSLATE_SCRIPT = r'''# translate_mod.py  —  translates a mod folder in one press
#
# This file is generated by build_dictionary.py into the Dictionary folder,
# together with the data files it needs. Double-click it: it finds the Steam
# Workshop folder for this game (steamapps\workshop\content\3020510) and
# offers to translate every mod in it, one after another, each keeping its
# untouched originals in <mod>\backup_original\. Or give it one mod folder:
#     python translate_mod.py "D:\...\workshop\content\3020510\3483808406"
# A mod that Steam has updated since is detected (file newer than its backup)
# and re-translated with a fresh backup.
#
# What it does, in order:
#   1. Translates every Chinese display field using dictionary.json (built from
#      the game's own files) and manual.json.
#   2. Anything still unknown is sent online:
#        - Google Translate (free, no key) by default. Game terms from
#          glossary.json are pinned before sending so names, places, titles
#          and stats match the game's own words.
#        - or your AI provider, when ai_api.ini has  enabled = yes  and an
#          API key (OpenAI, Anthropic, Gemini, DeepSeek, OpenRouter, Groq, xAI
#          or any OpenAI-compatible endpoint). Better with tone, placeholders
#          and terminology; costs cents per mod.
#      Every online result passes a sanity gate (still Chinese, lost
#      placeholder, not English, absurd length -> rejected, never saved).
#   3. Accepted results are saved into manual.json so they are reused for every
#      future mod, and the mod is finished.
#
# Only fields with an "...En" twin (dialog, name, description, showText, ...),
# the choices inside Conversation "option" fields, and ModInfo.json's
# name/remark are touched. Engine keys (condition, variant, formula, tag,
# IDs...) are never modified. Originals go to backup_original\.
#
# Never sent online:
#   - rows whose English twin is already filled (the game shows that already)
#   - Conversation rows with "func":"1" (logic / comment rows, never displayed)
# Lines the game itself ships without English (vanilla_untranslated.json) ARE
# translated: the player sees them, and a machine translation beats Chinese.
#
# If a line reads badly in-game, fix the English in manual.json and run this
# again - manual.json always wins over dictionary.json and the online result.
# Anything that could not be translated is left in needs_translation.json.

import os
import re
import sys
import json
import time
import shutil

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
DICT_PATH = os.path.join(SCRIPT_DIR, "dictionary.json")
MANUAL_PATH = os.path.join(SCRIPT_DIR, "manual.json")
GLOSSARY_PATH = os.path.join(SCRIPT_DIR, "glossary.json")
INI_PATH = os.path.join(SCRIPT_DIR, "ai_api.ini")

FILL_EN_FIELD = False   # True = also copy the English into the empty "...En" column
USE_GLOSSARY = True     # pin game terms from glossary.json when sending to Google

# Any provider with an OpenAI-style /chat/completions endpoint works, which
# covers almost every hosted or local LLM. Anthropic uses its own format.
AI_PROVIDERS = {
    #  name          (api format,   endpoint,                                                          default model)
    "openai":     ("openai",    "https://api.openai.com/v1/chat/completions",                          "gpt-4.1-mini"),
    "anthropic":  ("anthropic", "https://api.anthropic.com/v1/messages",                               "claude-sonnet-5"),
    "gemini":     ("openai",    "https://generativelanguage.googleapis.com/v1beta/openai/chat/completions", "gemini-2.5-flash"),
    "deepseek":   ("openai",    "https://api.deepseek.com/chat/completions",                           "deepseek-chat"),
    "openrouter": ("openai",    "https://openrouter.ai/api/v1/chat/completions",                       "openai/gpt-4.1-mini"),
    "groq":       ("openai",    "https://api.groq.com/openai/v1/chat/completions",                     "llama-3.3-70b-versatile"),
    "xai":        ("openai",    "https://api.x.ai/v1/chat/completions",                                "grok-3-mini"),
    "other":      ("openai",    "",                                                                    ""),
}


def detect_providers(key):
    """Which providers a key could belong to, judged by its prefix, most likely first."""
    if key.startswith("sk-ant-"):
        return ["anthropic"]
    if key.startswith("sk-or-"):
        return ["openrouter"]
    if key.startswith("AIza"):
        return ["gemini"]
    if key.startswith("gsk_"):
        return ["groq"]
    if key.startswith("xai-"):
        return ["xai"]
    return ["openai", "deepseek"]           # both use plain "sk-..." keys: try in turn

FILL_EN_FIELD = False   # True = also copy the English into the empty "...En" column

# Han ideographs only. Fullwidth punctuation (【】，：) also appears in the game's own
# ENGLISH, so counting it as Chinese threw away every official line that used it.
CJK = re.compile(r"[\u3400-\u4dbf\u4e00-\u9fff]")
# one {...} record; quoted strings may contain { } without breaking the record
RECORD = re.compile(r'\{(?:"(?:[^"\\]|\\.)*"|[^{}"])*\}', re.DOTALL)
FIELD = re.compile(r'"([A-Za-z0-9_]+)":"([^"]*)"')
# WO, NI, NTA, AMING, NMING ... (no \b: it does not match between Chinese and Latin letters)
PLACEHOLDER = re.compile(r"(?<![A-Za-z0-9])[A-Z][A-Z0-9]+(?![A-Za-z0-9])")
DATA_EXT = (".txt", ".json")
IGNORE_FILES = {"dictionary.json", "manual.json", "needs_translation.json", "vanilla_untranslated.json",
                "glossary.json", "translate_log.txt"}
COMMENT_FIELDS = {"remark"}
LOGIC_ROW = ("func", "1")    # Conversation rows with func=1 are logic/comment rows, never shown
OPTION_FIELD = "option"      # inline choice list: &zh&id&id&tc&en&jp&kr& # &zh&...
OPT_ZH, OPT_EN, OPT_LEN = 1, 5, 9
GAME_APP_ID = "3020510"      # Steam app id: workshop mods live in steamapps\workshop\content\3020510\<mod id>\


# ------------------------------------------------------------------ helpers
def norm(s):
    return s.replace("\r\n", "\n")


def read_text(path):
    with open(path, "rb") as f:
        raw = f.read()
    for enc in ("utf-8", "utf-8-sig", "gb18030", "utf-16"):
        try:
            return raw.decode(enc), enc
        except UnicodeDecodeError:
            continue
    return None, None


def write_text(path, text, enc):
    with open(path, "wb") as f:
        f.write(text.encode(enc))


def load_json(path):
    if not os.path.exists(path):
        return {}
    with open(path, "rb") as f:
        try:
            return json.loads(f.read().decode("utf-8-sig"))
        except Exception as e:
            print("  ! could not read %s: %s" % (os.path.basename(path), e))
            return {}


def save_json(path, data):
    with open(path, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=1)


def data_files(folder):
    out = []
    for root, dirs, files in os.walk(folder):
        dirs[:] = [d for d in dirs if d != "backup_original"]
        for name in files:
            if name.lower().endswith(DATA_EXT) and name not in IGNORE_FILES:
                out.append(os.path.join(root, name))
    return sorted(out)


# ------------------------------------------------------------------ step 1/3: apply dictionary
CONTEXT = {}     # filled by apply_dictionary; read by the AI engine when context = yes


def field_type(field, is_modinfo=False):
    f = field.lower()
    if is_modinfo:
        return "mod title" if f == "name" else "mod description"
    if f == OPTION_FIELD:
        return "dialogue choice (button text)"
    if f.startswith("dialog"):
        return "dialogue line"
    if "desc" in f or "info" in f or "tip" in f or "text" in f:
        return "description / UI text"
    if "name" in f or "title" in f:
        return "name / title"
    return "game text (field '%s')" % field


def has_english(s):
    return bool(s) and not CJK.search(s)


def apply_dictionary(mod_folder, lookup):
    """Translate what we know. Returns (translated_count, {unknown_chinese: ""}).
    Every display field with Chinese in it is either translated from lookup or
    reported as unknown, including lines the game itself ships without English
    (e.g. the Give Gift / Treat to a Drink tooltips): the player sees them, and
    a machine translation beats Chinese."""
    backup_dir = os.path.join(mod_folder, "backup_original")
    needs = {}
    total = 0
    skipped = 0
    CONTEXT.clear()
    CONTEXT["mod"] = {}
    CONTEXT["items"] = {}         # zh -> {"type": ..., "file": ..., "group": ..., "pos": n}
    CONTEXT["groups"] = {}        # (file, groupID) -> [(zh, en_or_None, speaker), ...]

    for path in data_files(mod_folder):
        text, enc = read_text(path)
        if text is None:
            print("  (skipped, unreadable) " + os.path.basename(path))
            continue
        nl = "\r\n" if "\r\n" in text else "\n"
        fname = os.path.basename(path)
        is_modinfo = fname.lower() == "modinfo.json"
        count = 0

        def note(zh, field, fields):
            """Remember where an unknown string came from, for the AI engine's context."""
            info = {"type": field_type(field, is_modinfo), "file": fname}
            gid = fields.get("groupID")
            if gid and "dialog" in fields:
                info["group"] = (fname, gid)
                info["pos"] = max(0, len(CONTEXT["groups"].get((fname, gid), [])) - 1)   # row was appended already
            CONTEXT["items"].setdefault(zh, info)

        def fix_option(val, fields):
            """Translate the Chinese slot of each choice; choices that already carry English are kept."""
            nonlocal count, skipped
            segs = []
            for seg in val.split("#"):
                p = seg.split("&")
                if len(p) >= OPT_LEN and CJK.search(p[OPT_ZH]) and not has_english(p[OPT_EN]):
                    zh = norm(p[OPT_ZH])
                    en = lookup.get(zh)
                    if en is None:
                        needs[zh] = ""
                        note(zh, OPTION_FIELD, fields)
                    else:
                        p[OPT_ZH] = en.replace("&", "and").replace("#", "").replace("\n", " ")
                        count += 1
                segs.append("&".join(p))
            return "#".join(segs)

        def fix_record(m):
            nonlocal count, skipped
            rec = m.group(0)
            fields = dict(FIELD.findall(rec))
            if fields.get(LOGIC_ROW[0]) == LOGIC_ROW[1] and "dialog" in fields:
                skipped += 1
                return rec                             # logic / comment row -> never displayed
            if is_modinfo:
                for k in ("name", "remark"):
                    if fields.get(k):
                        CONTEXT["mod"][k] = lookup.get(norm(fields[k]), fields[k])
            gid = fields.get("groupID")
            if gid and fields.get("dialog") and CJK.search(fields["dialog"]):
                zh0 = norm(fields["dialog"])
                en0 = fields.get("dialogEn") if has_english(fields.get("dialogEn", "")) else lookup.get(zh0)
                CONTEXT["groups"].setdefault((fname, gid), []).append((zh0, en0, fields.get("speakerIndex", "")))

            def fix_field(fm):
                nonlocal count, skipped
                name, val = fm.group(1), fm.group(2)
                if name.endswith("En") or not val or not CJK.search(val):
                    return fm.group(0)
                if name == OPTION_FIELD:
                    return '"%s":"%s"' % (name, fix_option(val, fields))
                is_display = (name + "En") in fields or (is_modinfo and name in ("name", "remark"))
                if not is_display and name not in COMMENT_FIELDS:
                    return fm.group(0)                 # engine key -> leave alone
                if has_english(fields.get(name + "En", "")):
                    return fm.group(0)                 # English twin already filled -> game shows it
                key = norm(val)
                en = lookup.get(key)
                if en is None:
                    if is_display:
                        needs[key] = ""
                        note(key, name, fields)
                    return fm.group(0)
                count += 1
                return '"%s":"%s"' % (name, en.replace("\n", nl))

            rec = FIELD.sub(fix_field, rec)
            if FILL_EN_FIELD:
                for name, val in fields.items():
                    if (name + "En") in fields and not fields[name + "En"] and val and CJK.search(val):
                        en = lookup.get(norm(val))
                        if en is not None:
                            rec = rec.replace('"%sEn":""' % name,
                                              '"%sEn":"%s"' % (name, en.replace("\n", nl)), 1)
            return rec

        new_text = RECORD.sub(fix_record, text)
        if new_text != text:
            dst = os.path.join(backup_dir, os.path.relpath(path, mod_folder))
            # keep the untouched original; refresh it when the file is newer than the
            # backup (Steam replaced the mod) - our own writes stamp the backup as newer
            if not os.path.exists(dst) or os.path.getmtime(path) > os.path.getmtime(dst):
                os.makedirs(os.path.dirname(dst), exist_ok=True)
                shutil.copy2(path, dst)
            write_text(path, new_text, enc)
            os.utime(dst, (time.time() + 2, time.time() + 2))
        total += count
        print("  %-30s %d translated" % (os.path.relpath(path, mod_folder), count))
    if skipped:
        print("  (%d logic rows left as they are)" % skipped)
    return total, needs


# ------------------------------------------------------------------ step 2: translate the leftovers online
GLOSSARY = {}            # zh term -> en term, loaded from glossary.json
GLOSSARY_PAT = None      # all terms: used for description-style lines (bullets, numbers)
GLOSSARY_PAT_DLG = None  # Title-Case terms only (names, places, titles, stats): used for dialogue
DESCRIPTION_LINE = re.compile(r"^\s*[\u25c6\u25cf\u25cb\u25a0\u25a1\u2605\u2606\u203b\u2022]|[0-9%]")


def load_glossary(enabled):
    global GLOSSARY, GLOSSARY_PAT, GLOSSARY_PAT_DLG
    GLOSSARY = load_json(GLOSSARY_PATH) if enabled else {}
    if isinstance(GLOSSARY, dict) and GLOSSARY:
        GLOSSARY_PAT = re.compile("|".join(map(re.escape, sorted(GLOSSARY, key=len, reverse=True))))
        proper = [k for k, v in GLOSSARY.items() if v[:1].isupper()]
        GLOSSARY_PAT_DLG = re.compile("|".join(map(re.escape, sorted(proper, key=len, reverse=True)))) if proper else None
    else:
        GLOSSARY, GLOSSARY_PAT, GLOSSARY_PAT_DLG = {}, None, None


def protect(text, use_glossary=True):
    """Write known game terms into the Chinese as their official English before
    sending, e.g. 每天5点精力 -> 每天5点stamina. Google keeps Latin words it finds
    inside Chinese text verbatim, so the term comes back exactly as the game
    spells it. (Neutral @@n@@ tokens were tried first; Google silently drops
    them now and then, which lost the whole line.) Placeholders such as WO and
    NI are already Latin capitals and are left as they are for the same reason.
    Returns (text_to_send, [english terms that must appear in the reply])."""
    found = []

    def swap_term(m):
        found.append(GLOSSARY[m.group(0)])
        return GLOSSARY[m.group(0)]

    if use_glossary and GLOSSARY_PAT is not None:
        pat = GLOSSARY_PAT if DESCRIPTION_LINE.search(text) else GLOSSARY_PAT_DLG
        if pat is not None:
            text = pat.sub(swap_term, text)
    return text, found


# Google's replies can carry invisible zero-width spaces and, for long passages,
# the original full-width punctuation. Both would fail the "is it English" gate
# although the text is fine, so they are normalised before the gate looks at it.
ZERO_WIDTH = re.compile("[\\u200b\\u200c\\u200d\\u2060\\ufeff]")
WIDE_PUNCT = {"，": ", ", "。": ". ", "；": "; ", "：": ": ", "（": " (", "）": ") ",
              "！": "! ", "？": "? ", "、": ", ", "「": '"', "」": '"', "『": '"',
              "』": '"', "【": "[", "】": "]", "～": "~", " ": " ", "×": "x"}


def clean_reply(text):
    text = ZERO_WIDTH.sub("", text)
    for k, v in WIDE_PUNCT.items():
        text = text.replace(k, v)
    text = re.sub(r"[ \t]{2,}", " ", text)
    text = re.sub(r"\s+([,.!?;:)\]])", r"\1", text)
    return text.strip()


def restore(text, found, zh=""):
    text = clean_reply(text)
    for ph in set(PLACEHOLDER.findall(zh)):          # "WOWhat I want" -> "WO What I want"
        text = re.sub(r"(?<=[A-Za-z])%s|%s(?=[A-Za-z])" % (ph, ph), lambda m: " " + ph + " ", text)
    return re.sub(r"[ \t]{2,}", " ", text).strip()


def prep_line(line, use_glossary=True):
    """Split a line into (bullet marker, body to send, terms to check, trailing CRs).
    Game text carries \\r\\n inside strings; after splitting on \\n a part may end
    in \\r, which Google drops. It is kept aside and put back on the result."""
    body = line.rstrip("\r")
    tail = line[len(body):]
    lead = re.match(r"^\s*[◆●○■□★☆※•\-]*\s*", body).group(0)
    prot, found = protect(body[len(lead):], use_glossary)
    return lead, prot, found, tail


# anything outside ASCII apart from typographic quotes/dashes/ellipsis means the reply is not English
NON_ENGLISH_LETTER = re.compile("[^\\x00-\\x7f\\u2013-\\u2026\\u00b7\\u00a0]")
LEAD_SYMBOLS = re.compile("[\\u25c6\\u25cf\\u25cb\\u25a0\\u25a1\\u2605\\u2606\\u203b\\u2022]")   # bullets used in descriptions


def gate(zh, en, found=None):
    """Sanity check on an online result. Returns None if fine, else the reason."""
    if not en or not en.strip():
        return "empty reply"
    if CJK.search(en):
        return "still contains Chinese"
    if found:
        low = en.lower()
        for word in found:
            if word.lower() not in low:
                return "dropped '%s'" % word
    for ph in set(PLACEHOLDER.findall(zh)):
        if ph not in en:
            return "dropped placeholder %s" % ph
    if NON_ENGLISH_LETTER.search(LEAD_SYMBOLS.sub("", en)):
        return "reply is not English"
    ratio = len(en) / max(len(zh.strip()), 1)
    if ratio < 0.4 or ratio > 15:
        return "reply length looks wrong (%.1fx)" % ratio
    return None


def classify(e):
    msg = str(e) or type(e).__name__
    low = msg.lower()
    if "getaddrinfo" in low or "name or service" in low or "connection" in low:
        return "no internet connection (" + msg[:80] + ")", False
    if "timed out" in low or "timeout" in low:
        return "request timed out (" + msg[:80] + ")", False
    if "429" in low or "too many" in low or "blocked" in low or "overloaded" in low or "529" in low:
        return "rate-limited / blocked the request (" + msg[:80] + ")", True
    return type(e).__name__ + ": " + msg[:120], False


# ---------------------------------------------------------------- engine: Google
class GoogleWeb(object):
    """Google Translate through its public web endpoint - standard library only, no
    package to install, so it runs on the private Python the launcher downloads.
    If deep-translator happens to be installed it is used as a fallback."""

    URL = "https://translate.googleapis.com/translate_a/single?client=gtx&sl=zh-CN&tl=en&dt=t&q="

    def __init__(self):
        self.fallback = None
        try:
            from deep_translator import GoogleTranslator
            self.fallback = GoogleTranslator(source="zh-CN", target="en")
        except Exception:
            pass

    def translate(self, text):
        import urllib.request
        import urllib.parse
        req = urllib.request.Request(self.URL + urllib.parse.quote(text, safe=""),
                                     headers={"User-Agent": "Mozilla/5.0"})
        try:
            with urllib.request.urlopen(req, timeout=60) as r:
                data = json.loads(r.read().decode("utf-8"))
            return "".join(seg[0] for seg in data[0] if seg and seg[0])
        except Exception:
            if self.fallback is None:
                raise
            return self.fallback.translate(text)


class GoogleEngine(object):
    name = "Google"

    def __init__(self, use_glossary):
        self.use_glossary = use_glossary
        self.tr = GoogleWeb()

    def line(self, line, attempts=3):
        """One line. Returns (english, None) or (None, reason)."""
        if not line.strip() or not CJK.search(line):
            return line, None
        lead, prot, found, tail = prep_line(line, self.use_glossary)
        last = "unknown"
        for attempt in range(attempts):
            try:
                out = self.tr.translate(prot)
                en = restore(out or "", found, line)
                why = gate(line, en, found)
                if why is None:
                    return lead + en + tail, None
                last = why
            except Exception as e:
                last, blocked = classify(e)
                if blocked:
                    time.sleep(15 * (attempt + 1))          # rate-limited: wait it out, then retry
                    continue
            time.sleep(2 * (attempt + 1))
        return None, self.name + ": " + last

    def batch(self, entries):
        """Many entries in ONE request. Returns {zh: en} for the ones that passed the gate."""
        lines = []            # (entry_index, part_index, lead, prot, found, original_line, tail)
        parts_of = []
        for ei, zh in enumerate(entries):
            parts = zh.split("\n")
            parts_of.append(parts)
            for pi, ln in enumerate(parts):
                if CJK.search(ln):
                    lead, prot, found, tail = prep_line(ln, self.use_glossary)
                    lines.append((ei, pi, lead, prot, found, ln, tail))
        if not lines:
            return {}
        try:
            out = self.tr.translate("\n".join(l[3] for l in lines))
        except Exception:
            return {}
        out_lines = out.split("\n") if out else []
        if len(out_lines) != len(lines):
            return {}                                  # answer lost its line structure -> slow path
        result, bad, translated = {}, set(), {}
        for (ei, pi, lead, prot, found, ln, tail), o in zip(lines, out_lines):
            en = restore(o, found, ln)
            if gate(ln, en, found) is None:
                translated[(ei, pi)] = lead + en + tail
            else:
                bad.add(ei)
        for ei, parts in enumerate(parts_of):
            if ei not in bad:
                result[entries[ei]] = "\n".join(translated.get((ei, pi), p) for pi, p in enumerate(parts))
        return result


# ---------------------------------------------------------------- engine: any LLM API
AI_SYSTEM = """You translate text for the video game "Heroes' Vow: Three Kingdoms" (a Romance of the Three Kingdoms life-sim) from Simplified Chinese to natural English for a mod.

Rules:
- Return ONLY a JSON array of strings, same length and order as the input items. No commentary, no code fences.
- Uppercase tokens such as WO, NI, CH, PLACE, NTA, AMING are placeholders the game replaces at runtime (WO = the speaker, NI = the listener). Keep every one exactly as written, in a natural position.
- Keep leading symbols (◆ ● ※ etc.), line breaks, numbers and punctuation structure.
- Use the glossary translations exactly where those terms occur; they are the game's own English.
- Dialogue should read like period drama speech; UI/description text should be concise; names and titles are short and Title Case.
- Never leave Chinese characters in the output."""

AI_SYSTEM_CONTEXT = AI_SYSTEM + """

You receive each item with context: what kind of text it is, the mod it belongs to, the surrounding lines of its conversation (with the game's official English where known), and official translations of similar vanilla lines. Read the context first, then translate so the new line fits its scene and matches the game's established style, terminology and tone. Translate only the "text" of each item."""


class SimilarIndex(object):
    """Finds vanilla dictionary lines that share the most characters with a new line
    (character-bigram overlap). Gives the AI the game's own phrasing to imitate."""

    def __init__(self, dictionary):
        self.pairs = [(zh, en) for zh, en in dictionary.items() if 2 <= len(zh) <= 120]
        self.index = {}
        for i, (zh, en) in enumerate(self.pairs):
            for g in set(zh[j:j + 2] for j in range(len(zh) - 1)):
                self.index.setdefault(g, []).append(i)

    def lookup(self, zh, n=4):
        grams = set(zh[j:j + 2] for j in range(len(zh) - 1))
        if not grams:
            return []
        score = {}
        for g in grams:
            posting = self.index.get(g)
            if posting and len(posting) < 4000:        # skip bigrams too common to be informative
                for i in posting:
                    score[i] = score.get(i, 0) + 1
        best = sorted(score.items(), key=lambda kv: (-kv[1] / (len(grams) + len(self.pairs[kv[0]][0]) ** 0.5), kv[0]))
        out = []
        for i, sc in best[:n * 3]:
            czh, cen = self.pairs[i]
            if sc / len(grams) >= 0.25 and czh != zh:
                out.append({"zh": czh, "en": cen})
            if len(out) >= n:
                break
        return out


class AIEngine(object):
    name = "AI"

    def __init__(self, cfg, dictionary=None):
        self.key = cfg.get("ai_key", "")
        provider = str(cfg.get("ai_provider", "auto")).lower()
        self.candidates = detect_providers(self.key) if provider == "auto" else [provider]
        self.cfg_url, self.cfg_model = cfg.get("ai_url", ""), cfg.get("ai_model", "")
        self.use_context = bool(cfg.get("ai_context", True))
        self.similar = SimilarIndex(dictionary) if (self.use_context and dictionary) else None
        self.dead = False
        self._use(self.candidates.pop(0))
        if not self.url or not self.model:
            raise ValueError("url and model must be set in ai_api.ini for provider '%s'" % self.provider)
        if not self.key and "localhost" not in self.url and "127.0.0.1" not in self.url:
            raise ValueError("api_key is empty in ai_api.ini")

    def _use(self, provider):
        fmt, url, model = AI_PROVIDERS.get(provider, AI_PROVIDERS["other"])
        self.provider, self.fmt = provider, fmt
        self.url = self.cfg_url or url
        self.model = self.cfg_model or model
        self.name = "AI (%s / %s%s)" % (provider, self.model, ", with context" if self.use_context else "")

    def _item(self, i, zh):
        """One item with its context for the model."""
        info = CONTEXT.get("items", {}).get(zh, {})
        item = {"i": i, "type": info.get("type", "game text"), "text": zh}
        grp = info.get("group")
        if grp and grp in CONTEXT.get("groups", {}):
            lines = CONTEXT["groups"][grp]
            pos = info.get("pos", 0)
            scene = []
            for k in range(max(0, pos - 4), min(len(lines), pos + 3)):
                lzh, len_, spk = lines[k]
                entry = {"speaker": spk, "text": len_ if len_ else lzh}
                if k == pos:
                    entry["this"] = True
                scene.append(entry)
            item["scene"] = scene
        if self.similar is not None:
            sim = self.similar.lookup(zh)
            if sim:
                item["similar_official_lines"] = sim
        return item

    def _request(self, entries):
        import urllib.request
        glossary = {}
        if GLOSSARY_PAT is not None:
            for zh in entries:
                for m in set(GLOSSARY_PAT.findall(zh)):
                    glossary[m] = GLOSSARY[m]
        if self.use_context:
            payload = {"mod": CONTEXT.get("mod", {}),
                       "glossary": glossary,
                       "items": [self._item(i, zh) for i, zh in enumerate(entries)]}
            user = ("Translate the \"text\" of every item below. Return a JSON array of %d strings, in order of \"i\".\n%s"
                    % (len(entries), json.dumps(payload, ensure_ascii=False)))
            system = AI_SYSTEM_CONTEXT
        else:
            user = "Glossary (Chinese -> English, use exactly):\n%s\n\nTranslate this JSON array:\n%s" % (
                json.dumps(glossary, ensure_ascii=False), json.dumps(entries, ensure_ascii=False))
            system = AI_SYSTEM
        headers = {"content-type": "application/json"}
        if self.fmt == "anthropic":
            headers.update({"x-api-key": self.key, "anthropic-version": "2023-06-01"})
            body = {"model": self.model, "max_tokens": 8000, "system": system,
                    "messages": [{"role": "user", "content": user}]}
        else:
            if self.key:
                headers["authorization"] = "Bearer " + self.key
            body = {"model": self.model, "temperature": 0.2,
                    "messages": [{"role": "system", "content": system},
                                 {"role": "user", "content": user}]}
        req = urllib.request.Request(self.url, data=json.dumps(body).encode("utf-8"), method="POST", headers=headers)
        with urllib.request.urlopen(req, timeout=180) as r:
            data = json.loads(r.read().decode("utf-8"))
        if self.fmt == "anthropic":
            text = "".join(b.get("text", "") for b in data.get("content", []))
        else:
            text = data["choices"][0]["message"]["content"] or ""
        m = re.search(r"\[.*\]", text, re.DOTALL)
        out = json.loads(m.group(0)) if m else None
        if not isinstance(out, list) or len(out) != len(entries):
            raise ValueError("reply was not a %d-item JSON array" % len(entries))
        return [str(x) for x in out]

    def batch(self, entries, attempts=3):
        if self.dead:
            return {}
        last = "unknown"
        for attempt in range(attempts):
            try:
                out = self._request(entries)
                result = {}
                for zh, en in zip(entries, out):
                    en = clean_reply(en)
                    if gate(zh, en) is None:
                        result[zh] = en
                return result
            except Exception as e:
                last, blocked = classify(e)
                if "HTTP Error 401" in last or "HTTP Error 403" in last:
                    if self.candidates:                     # same key shape, other provider: try it
                        self._use(self.candidates.pop(0))
                        continue
                    print("  The AI service rejected the API key (%s). Check ai_api.ini." % last[:60])
                    self.dead = True
                    return {}
                if "HTTP Error 404" in last:
                    print("  The AI service returned 404: wrong endpoint or model name (%s / %s)." % (self.url, self.model))
                    self.dead = True
                    return {}
                time.sleep((15 if blocked else 3) * (attempt + 1))
        print("  AI request failed: " + last)
        return {}

    def line(self, line):
        if not line.strip() or not CJK.search(line):
            return line, None
        res = self.batch([line])
        if line in res:
            return res[line], None
        return None, "AI: rejected or failed after retries"


def make_engine(cfg, dictionary=None):
    engine = str(cfg.get("engine", "google")).lower()
    if engine == "none":
        return None
    if engine == "ai":
        return AIEngine(cfg, dictionary)
    return GoogleEngine(USE_GLOSSARY)


# ---------------------------------------------------------------- driver
def online_translate(engine, needs, mod_folder):
    """Fill the empty values in needs (in place). Returns number filled.
    Whatever still fails is written to translate_log.txt with the reason."""
    todo = [k for k, v in needs.items() if not v]
    done = 0
    reasons = {}
    for round_no in range(1, 4):                       # up to 3 passes over the failures
        if not todo or getattr(engine, "dead", False):
            break
        if round_no > 1:
            print("  Retry round %d: %d lines still untranslated, waiting a moment ..." % (round_no, len(todo)))
            time.sleep(10 * round_no)

        # --- fast path: batches of up to 20 entries / ~3500 chars in one request
        leftover = []
        batches, batch, size = [], [], 0
        for zh in todo:
            if batch and (len(batch) >= 20 or size + len(zh) > 3500):
                batches.append(batch)
                batch, size = [], 0
            batch.append(zh)
            size += len(zh)
        if batch:
            batches.append(batch)
        for batch in batches:
            res = engine.batch(batch)
            for item in batch:
                if item in res:
                    needs[item] = res[item]
                    done += 1
                    print("  %s  ->  %s" % (short(item, 30), short(res[item], 50)))
                else:
                    leftover.append(item)
            time.sleep(0.3)

        # --- slow path: whatever the batch could not handle, line by line
        failed = []
        for i, zh in enumerate(leftover, 1):
            if getattr(engine, "dead", False):
                reasons[zh] = engine.name + ": service unavailable (see message above)"
                failed.append(zh)
                continue
            out_lines = []
            for ln in zh.split("\n"):
                en, why = engine.line(ln)
                if en is None:
                    out_lines = None
                    reasons[zh] = why
                    break
                out_lines.append(en)
            if out_lines is None:
                failed.append(zh)
                print("  [%d/%d] failed: %s  (%s)" % (i, len(leftover), short(zh, 30), reasons[zh]))
                continue
            needs[zh] = "\n".join(out_lines)
            reasons.pop(zh, None)
            done += 1
            print("  [%d/%d] %s  ->  %s" % (i, len(leftover), short(zh, 30), short(needs[zh], 50)))
            time.sleep(0.3)
        todo = failed
    write_log(mod_folder, reasons)
    return done


def short(s, n):
    """One-line console preview of a string."""
    return s.replace("\r", " ").replace("\n", " ")[:n]


def write_log(mod_folder, reasons):
    """Write translate_log.txt listing every line Google could not translate and why."""
    path = os.path.join(mod_folder, "translate_log.txt")
    if not reasons:
        if os.path.exists(path):
            os.remove(path)
        return
    with open(path, "w", encoding="utf-8") as f:
        f.write("Lines Google Translate could not translate (%s)\n" % time.strftime("%Y-%m-%d %H:%M"))
        f.write("They are also in needs_translation.json. Run the script again later, or fill them in by hand.\n\n")
        for zh, why in reasons.items():
            f.write("TEXT:   " + zh.replace("\n", " / ") + "\n")
            f.write("REASON: " + str(why) + "\n\n")
    print("  Failure details written to translate_log.txt")


# ------------------------------------------------------------------ main
def load_config():
    """Read ai_api.ini (written by build_dictionary.py). Missing file = Google."""
    import configparser
    cfg = {"engine": "google", "ai_key": "", "ai_provider": "auto", "ai_url": "", "ai_model": "", "ai_context": True}
    if not os.path.exists(INI_PATH):
        return cfg
    ini = configparser.ConfigParser()
    try:
        ini.read(INI_PATH, encoding="utf-8-sig")
    except Exception as e:
        print("  ! could not read ai_api.ini (%s) - using Google Translate" % e)
        return cfg
    sec = ini["AI"] if ini.has_section("AI") else {}
    val = str(sec.get("enabled", "no")).strip().lower()
    if val in ("offline", "none"):
        cfg["engine"] = "none"                     # never go online at all
        return cfg
    on = val in ("yes", "y", "true", "1", "on")
    cfg["ai_key"] = str(sec.get("api_key", "")).strip()
    cfg["ai_provider"] = str(sec.get("provider", "")).strip().lower() or "auto"
    cfg["ai_url"] = str(sec.get("url", "")).strip()
    cfg["ai_model"] = str(sec.get("model", "")).strip()
    cfg["ai_context"] = str(sec.get("context", "yes")).strip().lower() in ("yes", "y", "true", "1", "on")
    if on and (cfg["ai_key"] or cfg["ai_url"]):
        cfg["engine"] = "ai"
    elif on:
        print("  ai_api.ini: enabled = yes but api_key is empty - using Google Translate")
    return cfg


def mod_name(mod_folder):
    """The mod's own name from ModInfo.json, if present."""
    for root, dirs, files in os.walk(mod_folder):
        dirs[:] = [d for d in dirs if d != "backup_original"]
        for name in files:
            if name.lower() == "modinfo.json":
                text, enc = read_text(os.path.join(root, name))
                m = re.search(r'"name"\s*:\s*"([^"]*)"', text or "")
                return m.group(1) if m else ""
    return ""


def is_mod_folder(folder):
    """A mod folder holds ModInfo.json or data files directly (Workshop: content\<game id>\<mod id>\)."""
    try:
        names = os.listdir(folder)
    except OSError:
        return False
    return any(n.lower() == "modinfo.json" or n.lower().endswith(DATA_EXT) for n in names)


def find_mods(root):
    """Sub-folders of root that are mods (Steam Workshop: content\<game id>\<mod id>\)."""
    out = []
    for name in sorted(os.listdir(root)):
        p = os.path.join(root, name)
        if os.path.isdir(p) and name != "backup_original" and is_mod_folder(p):
            out.append(p)
    return out


def translate(mod_folder, cfg=None):
    """Translate one mod folder. Returns (translated_count, leftover_count)."""
    if not os.path.isdir(mod_folder):
        print("Folder not found: " + mod_folder)
        return 0, 0
    dictionary = load_json(DICT_PATH)
    if not dictionary:
        print("dictionary.json not found next to this script. Run build_dictionary.py first.")
        return 0, 0
    if cfg is None:
        cfg = load_config()
    manual = load_json(MANUAL_PATH)
    needs_path = os.path.join(mod_folder, "needs_translation.json")

    # absorb a hand-filled needs_translation.json if one is waiting
    filled = {k: v for k, v in load_json(needs_path).items() if v}
    if filled:
        manual.update(filled)
        save_json(MANUAL_PATH, manual)
        print("Merged %d hand translations from needs_translation.json into manual.json" % len(filled))

    lookup = dict(dictionary)
    lookup.update(manual)
    load_glossary(bool(cfg.get("use_glossary", True)))
    if not GLOSSARY:
        print("glossary.json not found - re-run build_dictionary.py so game terms are pinned when translating online.")

    print("Online engine: " + {"ai": "AI (ai_api.ini)", "none": "none (ai_api.ini: offline)"}.get(
        cfg["engine"], "Google Translate (free) - set enabled = yes in ai_api.ini to use your AI key"))
    print("")
    print("[1/3] Translating with game dictionary + manual.json ...")
    total, needs = apply_dictionary(mod_folder, lookup)

    if needs:
        try:
            engine = make_engine(cfg, dictionary)
        except Exception as e:
            print("  Could not start the '%s' engine: %s" % (cfg.get("engine"), e))
            engine = None
    if needs and engine is not None:
        print("")
        print("[2/3] %d unknown strings -> %s ..." % (len(needs), engine.name))
        online_translate(engine, needs, mod_folder)
        new_manual = {k: v for k, v in needs.items() if v}
        if new_manual:
            manual.update(new_manual)
            save_json(MANUAL_PATH, manual)
            lookup.update(new_manual)
            print("")
            print("[3/3] Finishing with %d %s translations ..." % (len(new_manual), engine.name))
            more, needs = apply_dictionary(mod_folder, lookup)
            total += more

    print("")
    print("Done: %d strings translated." % total)
    if needs:
        save_json(needs_path, needs)
        print("%d strings could not be translated -> left in needs_translation.json" % len(needs))
        print("Run again later, or send that file to Claude, save it back filled in, and run again.")
    else:
        if os.path.exists(needs_path):
            os.remove(needs_path)
        print("Everything translated, nothing left over.")
    return total, len(needs)


def translate_all(root, cfg=None):
    """Translate every mod folder inside root (e.g. the Workshop content\<game id> folder)."""
    mods = find_mods(root)
    if not mods:
        print("No mod folders found inside: " + root)
        return
    if cfg is None:
        cfg = load_config()
    print("%d mods found in %s" % (len(mods), root))
    results = []
    for i, mod in enumerate(mods, 1):
        name = mod_name(mod)
        print("")
        print("=" * 70)
        print("[%d/%d] %s   %s" % (i, len(mods), os.path.basename(mod), name))
        print("=" * 70)
        try:
            total, left = translate(mod, cfg)
        except Exception as e:
            print("  ! failed: %s" % e)
            total, left = 0, -1
        results.append((os.path.basename(mod), name, total, left))
    print("")
    print("=" * 70)
    print("Summary")
    print("=" * 70)
    for mid, name, total, left in results:
        status = "error" if left < 0 else ("%d left in needs_translation.json" % left if left else "complete")
        print("  %-12s %-28s %5d translated   %s" % (mid, short(name, 28), total, status))
    print("Translated mods keep their originals in <mod>\\backup_original\\.")


def workshop_folder():
    """The Workshop folder for this game, derived from where the Dictionary folder sits:
    <library>\steamapps\common\LegendOfHeros\Dictionary  ->  <library>\steamapps\workshop\content\3020510"""
    here = SCRIPT_DIR
    for _ in range(6):
        if os.path.basename(here).lower() == "steamapps":
            cand = os.path.join(here, "workshop", "content", GAME_APP_ID)
            if os.path.isdir(cand):
                return cand
        parent = os.path.dirname(here)
        if parent == here:
            break
        here = parent
    if os.name == "nt":
        for drive in "CDEFGHIJKLMNOPQRSTUVWXYZ":
            for lib in ("SteamLibrary", "Steam", os.path.join("Program Files (x86)", "Steam"),
                        os.path.join("Program Files", "Steam"), os.path.join("Games", "Steam")):
                cand = os.path.join(drive + ":\\", lib, "steamapps", "workshop", "content", GAME_APP_ID)
                if os.path.isdir(cand):
                    return cand
    return None


def other_game(path):
    """True if path lies inside steamapps\workshop\content\<some other app id>."""
    parts = [p.lower() for p in os.path.abspath(path).split(os.sep)]
    for i in range(len(parts) - 2):
        if parts[i] == "workshop" and parts[i + 1] == "content":
            return parts[i + 2] != GAME_APP_ID
    return False


def run(path, cfg=None):
    """A mod folder -> translate it. A folder of mods (Workshop content folder) -> translate each."""
    if not os.path.isdir(path):
        print("Folder not found: " + path)
    elif other_game(path):
        print("That folder belongs to a different game's Workshop (this game is content\\%s). Nothing done." % GAME_APP_ID)
    elif os.path.basename(os.path.abspath(path)).lower() == "content" and os.path.basename(os.path.dirname(os.path.abspath(path))).lower() == "workshop":
        sub = os.path.join(path, GAME_APP_ID)
        if os.path.isdir(sub):
            print("That is the Workshop root; using this game's folder inside it: " + sub)
            translate_all(sub, cfg)
        else:
            print("That is the Workshop root and it has no folder for this game (%s). Nothing done." % GAME_APP_ID)
    elif is_mod_folder(path):
        translate(path, cfg)
    else:
        translate_all(path, cfg)


def main():
    if len(sys.argv) >= 2:
        run(sys.argv[1].strip().strip('"'))
        return
    ws = workshop_folder()
    if ws:
        print("Workshop folder found: " + ws)
        p = input("Press Enter to translate every mod in it, or paste one mod folder path: ").strip().strip('"')
        run(p or ws)
    else:
        p = input("Mod folder path (or the Workshop content folder to do all mods): ").strip().strip('"')
        run(p or os.getcwd())
    input("Press Enter to close...")


if __name__ == "__main__":
    try:
        sys.stdout.reconfigure(errors="replace")       # never crash on a console that cannot show Chinese
    except Exception:
        pass
    main()
'''


if __name__ == "__main__":
    main()
