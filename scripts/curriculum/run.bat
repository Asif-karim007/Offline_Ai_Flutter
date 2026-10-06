@echo off
rem One command on Windows: set up Python, then download, OCR, build and upload every pack.
rem Safe to re-run: every stage continues where the last run stopped.
rem
rem   run.bat                                    everything, space-saving mode
rem   run.bat --packs general_class-9-10_bn      just one pack (good first test)
rem   run.bat --no-upload                        build only, upload later with: run.bat upload
setlocal EnableDelayedExpansion
cd /d "%~dp0"
chcp 65001 >nul
set PYTHONUTF8=1

set STAGE=all
set FIRST=%~1
if defined FIRST if not "!FIRST:~0,2!"=="--" (
  set STAGE=%~1
  shift
)
set ARGS=
:collect
if "%~1"=="" goto collected
set ARGS=!ARGS! %1
shift
goto collect
:collected

if not exist .venv (
  echo Creating Python environment ^(.venv^) ...
  py -3.12 -m venv .venv 2>nul || py -3.11 -m venv .venv 2>nul || py -3 -m venv .venv 2>nul || python -m venv .venv
  if errorlevel 1 (
    echo Python 3.11 or newer is required: https://www.python.org/downloads/
    echo Tick "Add python.exe to PATH" in the installer.
    exit /b 1
  )
)
call .venv\Scripts\activate.bat

if not exist .venv\.installed (
  python -m pip install --upgrade pip || exit /b 1
  pip install -r requirements.txt || exit /b 1
  type nul > .venv\.installed
)

where tesseract >nul 2>nul
if errorlevel 1 if not exist "C:\Program Files\Tesseract-OCR\tesseract.exe" (
  echo.
  echo Tesseract OCR is not installed. Most NCTB books are images, so it is required.
  echo Install it from https://github.com/UB-Mannheim/tesseract/wiki
  echo and in the installer, under "Additional language data", tick BENGALI.
  exit /b 1
)

set NEEDHF=
if /i "%STAGE%"=="all" set NEEDHF=1
if /i "%STAGE%"=="upload" set NEEDHF=1
echo !ARGS! | findstr /c:"--no-upload" >nul && set NEEDHF=
if defined NEEDHF (
  python -c "from huggingface_hub import HfApi; HfApi().whoami()" >nul 2>nul
  if errorlevel 1 (
    echo Log in to Hugging Face ^(paste your Write token when asked^):
    hf auth login
  )
)

python nctb_pipeline.py %STAGE% --delete-pdfs !ARGS!
