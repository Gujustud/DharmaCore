@echo off
setlocal

REM Build Android release APK with CribHub production backend URLs.
REM For live shop (CT 105 / dharmacore), use buildapk_shop.bat instead.

set "REPO_ROOT=%~dp0.."
pushd "%REPO_ROOT%" >nul

echo.
echo === Updating git / build stamp (About page) ===
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0update_git_info.ps1"
if errorlevel 1 (
  echo Failed to update git_info.dart
  popd >nul
  exit /b 1
)

echo.
echo === Building production APK (cribhub.sscadcam.com) ===
flutter build apk --release ^
  --dart-define=POCKETBASE_URL=https://cribhub.sscadcam.com/ ^
  --dart-define=MCP_URL=https://cribhub.sscadcam.com/mcp

if errorlevel 1 (
  echo.
  echo Production APK build failed.
  popd >nul
  exit /b 1
)

echo.
echo Build complete:
echo   build\app\outputs\flutter-apk\app-release.apk
echo.
echo For live shop tablet builds use: .\scripts\buildapk_shop.bat

popd >nul
endlocal
