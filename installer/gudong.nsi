; gudong installer. Built by .github/workflows/release.yml with:
;   makensis -INPUTCHARSET UTF8 -DVERSION=<version> -DSOURCE_DIR=<release dir> -DOUTDIR=<dist dir> gudong.nsi

Unicode true
!include "MUI2.nsh"
!include "FileFunc.nsh"

!ifndef VERSION
  !define VERSION "0.2.0"
!endif
!ifndef SOURCE_DIR
  !define SOURCE_DIR "..\island_app\build\windows\x64\runner\Release"
!endif
!ifndef OUTDIR
  !define OUTDIR "..\dist"
!endif

!define APP_NAME "gudong"
!define APP_EXE "island_app.exe"
!define APP_ID "Gudong"
!define APP_PUBLISHER "gudong"
!define APP_URL "https://github.com/ldm0715/gudong"
!define UNINST_KEY "Software\Microsoft\Windows\CurrentVersion\Uninstall\${APP_ID}"

Name "${APP_NAME} ${VERSION}"
OutFile "${OUTDIR}\gudong-${VERSION}-setup.exe"
InstallDir "$LOCALAPPDATA\Programs\Gudong"
InstallDirRegKey HKCU "Software\Gudong" "InstallDir"
RequestExecutionLevel user
BrandingText "${APP_NAME}"

SetCompressor /SOLID lzma
SetCompressorDictSize 32

!define MUI_ICON "..\island_app\windows\runner\resources\app_icon.ico"
!define MUI_UNICON "..\island_app\windows\runner\resources\app_icon.ico"
!define MUI_ABORTWARNING
!define MUI_FINISHPAGE_RUN "$INSTDIR\${APP_EXE}"
!define MUI_FINISHPAGE_RUN_TEXT "运行 ${APP_NAME}"

!insertmacro MUI_PAGE_WELCOME
!insertmacro MUI_PAGE_DIRECTORY
!insertmacro MUI_PAGE_INSTFILES
!insertmacro MUI_PAGE_FINISH

!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES

!insertmacro MUI_LANGUAGE "SimpChinese"

Section "Install"
  SetShellVarContext current
  SetOutPath "$INSTDIR"

  ; Stop a running instance so files can be replaced.
  nsExec::Exec 'taskkill /IM "${APP_EXE}" /F'
  nsExec::Exec 'taskkill /IM "island_service.exe" /F'
  Sleep 500

  File /r "${SOURCE_DIR}\*.*"
  WriteUninstaller "$INSTDIR\Uninstall.exe"

  CreateDirectory "$SMPROGRAMS\${APP_NAME}"
  CreateShortcut "$SMPROGRAMS\${APP_NAME}\${APP_NAME}.lnk" "$INSTDIR\${APP_EXE}" "" "$INSTDIR\${APP_EXE}" 0
  CreateShortcut "$SMPROGRAMS\${APP_NAME}\卸载 ${APP_NAME}.lnk" "$INSTDIR\Uninstall.exe"

  WriteRegStr HKCU "Software\Gudong" "InstallDir" "$INSTDIR"
  WriteRegStr HKCU "${UNINST_KEY}" "DisplayName" "${APP_NAME}"
  WriteRegStr HKCU "${UNINST_KEY}" "DisplayVersion" "${VERSION}"
  WriteRegStr HKCU "${UNINST_KEY}" "DisplayIcon" "$INSTDIR\${APP_EXE}"
  WriteRegStr HKCU "${UNINST_KEY}" "Publisher" "${APP_PUBLISHER}"
  WriteRegStr HKCU "${UNINST_KEY}" "URLInfoAbout" "${APP_URL}"
  WriteRegStr HKCU "${UNINST_KEY}" "InstallLocation" "$INSTDIR"
  WriteRegStr HKCU "${UNINST_KEY}" "UninstallString" "$\"$INSTDIR\Uninstall.exe$\""
  WriteRegStr HKCU "${UNINST_KEY}" "QuietUninstallString" "$\"$INSTDIR\Uninstall.exe$\" /S"
  WriteRegDWORD HKCU "${UNINST_KEY}" "NoModify" 1
  WriteRegDWORD HKCU "${UNINST_KEY}" "NoRepair" 1

  ${GetSize} "$INSTDIR" "/S=0K" $0 $1 $2
  WriteRegDWORD HKCU "${UNINST_KEY}" "EstimatedSize" "$0"
SectionEnd

Section "Uninstall"
  SetShellVarContext current

  nsExec::Exec 'taskkill /IM "${APP_EXE}" /F'
  nsExec::Exec 'taskkill /IM "island_service.exe" /F'
  Sleep 500

  Delete "$SMPROGRAMS\${APP_NAME}\${APP_NAME}.lnk"
  Delete "$SMPROGRAMS\${APP_NAME}\卸载 ${APP_NAME}.lnk"
  RMDir "$SMPROGRAMS\${APP_NAME}"

  RMDir /r "$INSTDIR"

  DeleteRegKey HKCU "${UNINST_KEY}"
  DeleteRegKey HKCU "Software\Gudong"
SectionEnd
