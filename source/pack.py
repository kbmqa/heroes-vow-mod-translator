# pack.py - builds the deliverables:
#   build_dictionary.py   = build_dictionary.template.py + translate_mod.py embedded verbatim
#   Build-Dictionary.bat  = a batch launcher with build_dictionary.py appended after a marker.
#                           Runs with an installed Python, or downloads a private embeddable
#                           Python into Dictionary\python\ (shared with Translate-Mods.bat).
import os

HERE = os.path.dirname(os.path.abspath(__file__))
src = open(os.path.join(HERE, "build_dictionary.template.py"), encoding="utf-8").read()
tm = open(os.path.join(HERE, "translate_mod.py"), encoding="utf-8").read()
assert "'''" not in tm, "translate_mod.py must not contain triple single quotes"
assert "__TRANSLATE_MOD_PY__" in src
ROOT = os.path.dirname(HERE)          # repository root: README.md, LICENSE and the .bat live there
readme = open(os.path.join(ROOT, "README.md"), encoding="utf-8").read()
lic = open(os.path.join(ROOT, "LICENSE"), encoding="utf-8").read()
assert "'''" not in readme and "'''" not in lic
py = src.replace("__TRANSLATE_MOD_PY__", tm).replace("__README_MD__", readme).replace("__LICENSE__", lic)
open(os.path.join(HERE, "build_dictionary.py"), "w", encoding="utf-8", newline="\n").write(py)
print("packed build_dictionary.py: %d lines" % py.count("\n"))

MARK = ":::" + "PYTHON" + ":::"
assert py.count(MARK) == 0
HEADER = r"""@echo off
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
""" + MARK + "\n"
bat = HEADER.replace("\n", "\r\n") + py.replace("\n", "\r\n")
open(os.path.join(ROOT, "Build-Dictionary.bat"), "wb").write(bat.encode("utf-8"))
print("packed Build-Dictionary.bat: %d bytes" % len(bat))
