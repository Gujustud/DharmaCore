@echo off
setlocal

REM Build Android release APK for live shop (CT 105 / dharmacore).
REM Regenerates About-page git/build stamp, then builds with shop URLs.

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
echo === Building shop APK (dharmacore.sscadcam.com) ===
flutter build apk --release ^
  --dart-define=POCKETBASE_URL=https://dharmacore.sscadcam.com/ ^
  --dart-define=MCP_URL=https://dharmacore.sscadcam.com/mcp

if errorlevel 1 (
  echo.
  echo Shop APK build failed.
  popd >nul
  exit /b 1
)

echo.
echo Build complete:
echo   build\app\outputs\flutter-apk\app-release.apk
echo.
echo Check About in the app for Version / Built / Commit before installing on the tablet.

popd >nul
endlocal
