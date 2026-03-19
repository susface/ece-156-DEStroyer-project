@echo off
if not "%_BUILD_WRAPPED%"=="1" (
    set "_BUILD_WRAPPED=1"
    cmd /k call "%~f0" %*
    exit /b
)
setlocal enabledelayedexpansion
chcp 65001 >nul 2>&1
cd /d "%~dp0" 2>nul

set EXE_NAME=mitm_2des
set BUILD_TYPE=Release
set "SCRIPT_DIR=%~dp0"

if "%~1"=="clean" (
    echo Cleaning build directories...
    if exist "%SCRIPT_DIR%build" rmdir /s /q "%SCRIPT_DIR%build"
    for /d %%S in ("%SCRIPT_DIR%*") do if exist "%%S\build" rmdir /s /q "%%S\build"
    echo Done.
    exit /b 0
)

set "SRC_DIR="
if exist "%SCRIPT_DIR%CMakeLists.txt" set "SRC_DIR=%SCRIPT_DIR%"
if defined SRC_DIR goto :src_ok
for /d %%S in ("%SCRIPT_DIR%*") do (
    if not defined SRC_DIR if exist "%%S\CMakeLists.txt" (
        set "SRC_DIR=%%S\"
        echo Found project in: %%S
    )
)
:src_ok
if not defined SRC_DIR (
    echo.
    echo ERROR: CMakeLists.txt not found in script directory or any subfolder.
    echo.
    exit /b 1
)

set "BUILD_DIR=!SRC_DIR!build"

set "CMAKE_EXE="
where cmake >nul 2>&1
if not errorlevel 1 (
    for /f "delims=" %%P in ('where cmake 2^^^>nul') do if not defined CMAKE_EXE set "CMAKE_EXE=%%P"
)
if defined CMAKE_EXE goto :cmake_ok

for %%L in (C D E F G H I J K L M N O P Q R S T U V W X Y Z) do (
    if not defined CMAKE_EXE if exist "%%L:\" (
        for %%V in (2026 2022 2019) do (
            for %%E in (Enterprise Professional Community BuildTools) do (
                if not defined CMAKE_EXE if exist "%%L:\Program Files\Microsoft Visual Studio\%%V\%%E\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe" (
                    set "CMAKE_EXE=%%L:\Program Files\Microsoft Visual Studio\%%V\%%E\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe"
                    echo Found CMake: !CMAKE_EXE!
                )
            )
        )
    )
)
if defined CMAKE_EXE goto :cmake_ok

for %%L in (C D E F G H I J K L M N O P Q R S T U V W X Y Z) do (
    if not defined CMAKE_EXE if exist "%%L:\" (
        if exist "%%L:\Program Files\CMake\bin\cmake.exe" set "CMAKE_EXE=%%L:\Program Files\CMake\bin\cmake.exe"
    )
)
if not defined CMAKE_EXE if exist "C:\Program Files (x86)\CMake\bin\cmake.exe" set "CMAKE_EXE=C:\Program Files (x86)\CMake\bin\cmake.exe"
if not defined CMAKE_EXE if exist "C:\msys64\mingw64\bin\cmake.exe" set "CMAKE_EXE=C:\msys64\mingw64\bin\cmake.exe"
if not defined CMAKE_EXE if exist "C:\msys64\ucrt64\bin\cmake.exe" set "CMAKE_EXE=C:\msys64\ucrt64\bin\cmake.exe"
if not defined CMAKE_EXE if exist "C:\msys64\usr\bin\cmake.exe" set "CMAKE_EXE=C:\msys64\usr\bin\cmake.exe"
if defined CMAKE_EXE echo Found CMake: !CMAKE_EXE!
:cmake_ok

if not defined CMAKE_EXE (
    echo.
    echo ERROR: cmake.exe not found anywhere.
    echo   1. Install CMake from https://cmake.org/download/
    echo   2. Or open a Developer Command Prompt for VS 2026/2022/2019
    echo   3. Or install via: winget install Kitware.CMake
    echo.
    exit /b 1
)

set "VS_GEN="
set "VCVARS="
for %%L in (C D E F G H I J K L M N O P Q R S T U V W X Y Z) do (
    if not defined VS_GEN if exist "%%L:\" (
        for %%V in (2026 2022 2019) do (
            for %%E in (Enterprise Professional Community BuildTools) do (
                if not defined VS_GEN if exist "%%L:\Program Files\Microsoft Visual Studio\%%V\%%E\VC\Auxiliary\Build\vcvarsall.bat" (
                    if "%%V"=="2026" set "VS_GEN=Visual Studio 18 2026"
                    if "%%V"=="2022" set "VS_GEN=Visual Studio 17 2022"
                    if "%%V"=="2019" set "VS_GEN=Visual Studio 16 2019"
                    set "VCVARS=%%L:\Program Files\Microsoft Visual Studio\%%V\%%E\VC\Auxiliary\Build\vcvarsall.bat"
                    echo Found Visual Studio %%V on %%L: drive
                )
            )
        )
    )
)

set "NINJA_EXE="
where ninja >nul 2>&1
if not errorlevel 1 set "NINJA_EXE=ninja"

set "MINGW_DIR="
where gcc >nul 2>&1
if not errorlevel 1 goto :gcc_ok
if exist "C:\msys64\ucrt64\bin\gcc.exe" set "MINGW_DIR=C:\msys64\ucrt64\bin"
if not defined MINGW_DIR if exist "C:\msys64\mingw64\bin\gcc.exe" set "MINGW_DIR=C:\msys64\mingw64\bin"
if not defined MINGW_DIR if exist "C:\msys64\clang64\bin\gcc.exe" set "MINGW_DIR=C:\msys64\clang64\bin"
if not defined MINGW_DIR if exist "C:\mingw64\bin\gcc.exe" set "MINGW_DIR=C:\mingw64\bin"
if not defined MINGW_DIR if exist "C:\MinGW\bin\gcc.exe" set "MINGW_DIR=C:\MinGW\bin"
if not defined MINGW_DIR (
    for %%L in (D E F G H I J K L M N O P Q R S T U V W X Y Z) do (
        if not defined MINGW_DIR if exist "%%L:\" (
            if exist "%%L:\msys64\ucrt64\bin\gcc.exe" set "MINGW_DIR=%%L:\msys64\ucrt64\bin"
            if not defined MINGW_DIR if exist "%%L:\msys64\mingw64\bin\gcc.exe" set "MINGW_DIR=%%L:\msys64\mingw64\bin"
            if not defined MINGW_DIR if exist "%%L:\mingw64\bin\gcc.exe" set "MINGW_DIR=%%L:\mingw64\bin"
        )
    )
)
if defined MINGW_DIR (
    echo Found MinGW: !MINGW_DIR!
    set "PATH=!MINGW_DIR!;!PATH!"
)
:gcc_ok

where cl >nul 2>&1
if not errorlevel 1 goto :env_ok
if not defined VCVARS goto :env_ok
echo Setting up MSVC environment...
call "!VCVARS!" x64
:env_ok

if not exist "!BUILD_DIR!" mkdir "!BUILD_DIR!"
pushd "!BUILD_DIR!"

set BUILD_OK=0

if not defined VS_GEN goto :skip_vs
echo.
echo === Trying generator: !VS_GEN! ===
echo.
if exist CMakeCache.txt del CMakeCache.txt >nul 2>&1
if exist CMakeFiles rmdir /s /q CMakeFiles >nul 2>&1
"!CMAKE_EXE!" "!SRC_DIR!." -G "!VS_GEN!" -A x64
if not errorlevel 1 set BUILD_OK=1
:skip_vs

if not "!BUILD_OK!"=="0" goto :gen_ok
if not defined NINJA_EXE goto :skip_ninja
echo.
echo === Trying generator: Ninja ===
echo.
if exist CMakeCache.txt del CMakeCache.txt >nul 2>&1
if exist CMakeFiles rmdir /s /q CMakeFiles >nul 2>&1
"!CMAKE_EXE!" "!SRC_DIR!." -G "Ninja" -DCMAKE_BUILD_TYPE=!BUILD_TYPE!
if not errorlevel 1 set BUILD_OK=1
:skip_ninja

if not "!BUILD_OK!"=="0" goto :gen_ok
where cl >nul 2>&1
if errorlevel 1 goto :skip_nmake
echo.
echo === Trying generator: NMake Makefiles ===
echo.
if exist CMakeCache.txt del CMakeCache.txt >nul 2>&1
if exist CMakeFiles rmdir /s /q CMakeFiles >nul 2>&1
"!CMAKE_EXE!" "!SRC_DIR!." -G "NMake Makefiles" -DCMAKE_BUILD_TYPE=!BUILD_TYPE!
if not errorlevel 1 set BUILD_OK=1
:skip_nmake

if not "!BUILD_OK!"=="0" goto :gen_ok
where gcc >nul 2>&1
if errorlevel 1 goto :skip_mingw
echo.
echo === Trying generator: MinGW Makefiles ===
echo.
if exist CMakeCache.txt del CMakeCache.txt >nul 2>&1
if exist CMakeFiles rmdir /s /q CMakeFiles >nul 2>&1
"!CMAKE_EXE!" "!SRC_DIR!." -G "MinGW Makefiles" -DCMAKE_BUILD_TYPE=!BUILD_TYPE!
if not errorlevel 1 set BUILD_OK=1
:skip_mingw

if not "!BUILD_OK!"=="0" goto :gen_ok
echo.
echo ERROR: CMake generation failed with all generators.
echo.
echo   Option A - Visual Studio / Build Tools:
echo     Install VS 2026/2022/2019 with "Desktop development with C++" workload
echo     Or just Build Tools: https://visualstudio.microsoft.com/downloads/
echo.
echo   Option B - VS Code + MinGW:
echo     1. Install MSYS2: https://www.msys2.org
echo     2. In MSYS2 terminal: pacman -S mingw-w64-ucrt-x86_64-toolchain
echo     3. Add C:\msys64\ucrt64\bin to your system PATH
echo     4. Install CMake: https://cmake.org/download/
echo     5. Re-run this script
echo.
popd
exit /b 1

:gen_ok
echo.
echo === Building !BUILD_TYPE! ===
echo.
"!CMAKE_EXE!" --build . --config !BUILD_TYPE! --parallel

if errorlevel 1 (
    echo.
    echo ERROR: Build failed. See errors above.
    popd
    exit /b 1
)

echo.
echo ============================================================
echo  Build successful!
echo  Run: build\!BUILD_TYPE!\!EXE_NAME!.exe
echo ============================================================

popd
exit /b 0
