# Source

Everything the release ships is built from these files by `pack.py`:

| File | Role |
|---|---|
| `translate_mod.py` | The translator. Standard library only. Generated into `Dictionary\translate_mod.py` by the setup. |
| `build_dictionary.template.py` | The setup program, with a placeholder where `translate_mod.py` is embedded. |
| `build_dictionary.py` | The setup program with `translate_mod.py` embedded (output of `pack.py`). Runs directly with Python. |
| `pack.py` | Builds `build_dictionary.py`, then writes `Build Dictionary.bat` = a 25-line batch launcher + `build_dictionary.py` appended after a `:::PYTHON:::` marker. |

To verify the release: run `python pack.py` here and compare the produced `Build Dictionary.bat` (written to the repository root) with the one attached to the release. Windows line endings (CRLF) are used for the `.bat`.

MIT licensed; see `../LICENSE`.
