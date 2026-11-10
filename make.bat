@ECHO OFF
SETLOCAL EnableDelayedExpansion

:: Resolve project root directory
SET "ROOT_DIR=%~dp0"
IF "%ROOT_DIR:~-1%"=="\" SET "ROOT_DIR=%ROOT_DIR:~0,-1%"

:: Target script definition
SET "SCRIPT_NAME=quickmixer"
SET "SCRIPT_FILE=%ROOT_DIR%\%SCRIPT_NAME%.ahk"

IF NOT EXIST "%SCRIPT_FILE%" (
    ECHO [ERROR] Script not found at "%SCRIPT_FILE%"!
    PAUSE
    EXIT /B 1
)

:: Locate AutoHotkey installation
SET "AHK_DIR="
FOR /F "tokens=2*" %%A IN ('REG QUERY "HKEY_LOCAL_MACHINE\SOFTWARE\AutoHotkey\v2" /v InstallDir 2^>NUL') DO SET "AHK_DIR=%%B"
IF "%AHK_DIR%"=="" FOR /F "tokens=2*" %%A IN ('REG QUERY "HKEY_LOCAL_MACHINE\SOFTWARE\AutoHotkey" /v InstallDir 2^>NUL') DO SET "AHK_DIR=%%B"
IF "%AHK_DIR%"=="" IF EXIST "%ProgramFiles%\AutoHotkey" SET "AHK_DIR=%ProgramFiles%\AutoHotkey"

SET "AHK_COMPILER=%AHK_DIR%\Compiler\Ahk2Exe.exe"
IF NOT EXIST "%AHK_COMPILER%" (
    ECHO [ERROR] Ahk2Exe.exe not found at "%AHK_COMPILER%"!
    ECHO Please ensure AutoHotkey v2 and the Ahk2Exe compiler are installed.
    PAUSE
    EXIT /B 1
)

:: Detect AHKv2 Base Binaries (64-bit and 32-bit)
SET "BASE_64="
IF EXIST "%AHK_DIR%\v2\AutoHotkey64.exe" (
    SET "BASE_64=%AHK_DIR%\v2\AutoHotkey64.exe"
)

SET "BASE_32="
IF EXIST "%AHK_DIR%\v2\AutoHotkey32.exe" (
    SET "BASE_32=%AHK_DIR%\v2\AutoHotkey32.exe"
)

:: Fallback if only one base is found
IF "%BASE_64%"=="" SET "BASE_64=%BASE_32%"
IF "%BASE_32%"=="" SET "BASE_32=%BASE_64%"

:: Detect Icon
SET "ICON_PARAM="
IF EXIST "%ROOT_DIR%\%SCRIPT_NAME%.ico" (
    SET "ICON_PARAM=/icon "%ROOT_DIR%\%SCRIPT_NAME%.ico""
) ELSE IF EXIST "%ROOT_DIR%\icon.ico" (
    SET "ICON_PARAM=/icon "%ROOT_DIR%\icon.ico""
) ELSE IF EXIST "%ROOT_DIR%\assets\icon.ico" (
    SET "ICON_PARAM=/icon "%ROOT_DIR%\assets\icon.ico""
)

:: Direct CLI argument handling
SET "IS_CLI=0"
IF NOT "%~1"=="" (
    SET "IS_CLI=1"
    SET "CHOICE=%~1"
    IF /I "%~1"=="x64" SET "CHOICE=1"
    IF /I "%~1"=="64"  SET "CHOICE=1"
    IF /I "%~1"=="x86" SET "CHOICE=2"
    IF /I "%~1"=="32"  SET "CHOICE=2"
    IF /I "%~1"=="all" SET "CHOICE=3"
    IF /I "%~1"=="gui" SET "CHOICE=4"
    IF /I "!CHOICE!"=="1" GOTO DO_BUILD_X64
    IF /I "!CHOICE!"=="2" GOTO DO_BUILD_X86
    IF /I "!CHOICE!"=="3" GOTO DO_BUILD_ALL
    IF /I "!CHOICE!"=="4" GOTO LAUNCH_GUI
    IF /I "!CHOICE!"=="Q" EXIT /B 0
    ECHO Unknown command-line option: %~1
    EXIT /B 1
)

:MENU
CLS
ECHO ===============================================================================
ECHO   QuickMixer (Windows Volume Mixer) - Build / Compiler Tool
ECHO ===============================================================================
ECHO   Root Dir   : %ROOT_DIR%
ECHO   Script     : %SCRIPT_NAME%.ahk
ECHO   Ahk2Exe    : %AHK_COMPILER%
ECHO   x64 Base   : %BASE_64%
ECHO   x86 Base   : %BASE_32%
ECHO.
ECHO   [1] Build x64 Unicode (Recommended)  -^> %SCRIPT_NAME%.exe
ECHO   [2] Build x86 Unicode (32-bit)       -^> %SCRIPT_NAME%.exe
ECHO   [3] Build Both (x64 and x86)         -^> bin\
ECHO   [4] Launch Ahk2Exe GUI
ECHO   [Q] Quit
ECHO.
SET /P "CHOICE=Enter selection (1-4, Q): "

IF /I "%CHOICE%"=="1" GOTO DO_BUILD_X64
IF /I "%CHOICE%"=="2" GOTO DO_BUILD_X86
IF /I "%CHOICE%"=="3" GOTO DO_BUILD_ALL
IF /I "%CHOICE%"=="4" GOTO LAUNCH_GUI
IF /I "%CHOICE%"=="Q" EXIT /B 0
GOTO MENU

:DO_BUILD_X64
ECHO.
ECHO Compiling %SCRIPT_NAME%.ahk [x64 Unicode] -^> %SCRIPT_NAME%.exe ...
IF "%BASE_64%"=="" (
    ECHO [ERROR] 64-bit base binary not found.
    GOTO BUILD_END
)
SET "OUT_FILE=%ROOT_DIR%\%SCRIPT_NAME%.exe"
IF EXIST "%OUT_FILE%" (
    DEL "%OUT_FILE%" 2>NUL
    IF EXIST "%OUT_FILE%" (
        ECHO [ERROR] Could not overwrite "%OUT_FILE%". Is the application currently running?
        GOTO BUILD_END
    )
)
START /WAIT "" "%AHK_COMPILER%" /in "%SCRIPT_FILE%" /out "%OUT_FILE%" %ICON_PARAM% /base "%BASE_64%" /silent
IF EXIST "%OUT_FILE%" (
    ECHO [SUCCESS] Compiled successfully: %OUT_FILE%
) ELSE (
    ECHO [ERROR] Compilation failed.
)
GOTO BUILD_END

:DO_BUILD_X86
ECHO.
ECHO Compiling %SCRIPT_NAME%.ahk [x86 Unicode 32-bit] -^> %SCRIPT_NAME%.exe ...
IF "%BASE_32%"=="" (
    ECHO [ERROR] 32-bit base binary not found.
    GOTO BUILD_END
)
SET "OUT_FILE=%ROOT_DIR%\%SCRIPT_NAME%.exe"
IF EXIST "%OUT_FILE%" (
    DEL "%OUT_FILE%" 2>NUL
    IF EXIST "%OUT_FILE%" (
        ECHO [ERROR] Could not overwrite "%OUT_FILE%". Is the application currently running?
        GOTO BUILD_END
    )
)
START /WAIT "" "%AHK_COMPILER%" /in "%SCRIPT_FILE%" /out "%OUT_FILE%" %ICON_PARAM% /base "%BASE_32%" /silent
IF EXIST "%OUT_FILE%" (
    ECHO [SUCCESS] Compiled successfully: %OUT_FILE%
) ELSE (
    ECHO [ERROR] Compilation failed.
)
GOTO BUILD_END

:DO_BUILD_ALL
ECHO.
ECHO Compiling both architectures to bin\ ...
IF NOT EXIST "%ROOT_DIR%\bin" MKDIR "%ROOT_DIR%\bin"

IF NOT "%BASE_64%"=="" (
    ECHO   -^> Compiling bin\%SCRIPT_NAME%_x64.exe ...
    SET "OUT_64=%ROOT_DIR%\bin\%SCRIPT_NAME%_x64.exe"
    IF EXIST "!OUT_64!" DEL "!OUT_64!" 2>NUL
    START /WAIT "" "%AHK_COMPILER%" /in "%SCRIPT_FILE%" /out "!OUT_64!" %ICON_PARAM% /base "%BASE_64%" /silent
    IF EXIST "!OUT_64!" (
        ECHO       [OK] bin\%SCRIPT_NAME%_x64.exe
        COPY /Y "!OUT_64!" "%ROOT_DIR%\%SCRIPT_NAME%.exe" >NUL 2>&1
    ) ELSE (
        ECHO       [FAILED] bin\%SCRIPT_NAME%_x64.exe
    )
)

IF NOT "%BASE_32%"=="" (
    ECHO   -^> Compiling bin\%SCRIPT_NAME%_x86.exe ...
    SET "OUT_32=%ROOT_DIR%\bin\%SCRIPT_NAME%_x86.exe"
    IF EXIST "!OUT_32!" DEL "!OUT_32!" 2>NUL
    START /WAIT "" "%AHK_COMPILER%" /in "%SCRIPT_FILE%" /out "!OUT_32!" %ICON_PARAM% /base "%BASE_32%" /silent
    IF EXIST "!OUT_32!" (
        ECHO       [OK] bin\%SCRIPT_NAME%_x86.exe
    ) ELSE (
        ECHO       [FAILED] bin\%SCRIPT_NAME%_x86.exe
    )
)

ECHO [DONE] All builds complete!
GOTO BUILD_END

:LAUNCH_GUI
START "" "%AHK_COMPILER%" /in "%SCRIPT_FILE%"
GOTO MENU

:BUILD_END
IF "%IS_CLI%"=="1" EXIT /B 0
PAUSE
GOTO MENU
