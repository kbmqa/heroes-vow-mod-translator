# Heroes' Vow: Three Kingdoms — Workshop Mod Translator

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
- developer notes the game ships without English (listed in `vanilla_untranslated.json`)
- fields whose English twin is already filled (the game shows that English already)

## Install (once)

1. Download `Build Dictionary.bat`.
2. Put it in the game folder, the one containing `ThreeKingdom_Data`. Typically:
   `D:\SteamLibrary\steamapps\common\LegendOfHeros`
3. Double-click it. It finds the game data by itself, then press Enter.

It creates a `Dictionary` folder next to it. If Python is not installed on your PC, it downloads the official *embeddable* Python (about 11 MB, no installer, no admin rights) into `Dictionary\python\` and uses that. Nothing is installed anywhere else on your system.

Run it again whenever the game updates.

## Translate mods

Double-click `Dictionary\Translate Mods.bat`.

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
| `Translate Mods.bat` | Double-click to translate. Uses installed Python or the private copy. |
| `translate_mod.py` | The translator itself. Standard library only. |
| `ai_api.ini` | Your AI settings. Never overwritten by a rebuild. |
| `dictionary.json` | Chinese → English from the game files. |
| `glossary.json` | Game terms the game translates consistently, pinned during online translation. |
| `vanilla_untranslated.json` | Chinese lines the game ships without English; skipped. |
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

- `Build Dictionary.bat` is a 25-line batch launcher followed by the Python program itself, appended as text. Open it in Notepad to inspect it. The `source\` folder of this release contains the same program as separate `.py` files, and `pack.py`, which shows exactly how the `.bat` is assembled from them.
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
- **Lines still in Chinese after translating** — they are either logic rows the game never shows, or developer notes the game itself never translated. Check `needs_translation.json` for anything that actually failed.
- **AI: "rejected the API key"** — check `api_key` in `ai_api.ini`. **404** — wrong `model` name for that provider; leave it empty for the default.
- **A Google line is nonsense** — fix it in `manual.json`, or enable AI translation.

## License

MIT. See `LICENSE`.
