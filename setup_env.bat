@echo off
if not "%_SETUP_WRAPPED%"=="1" (
    set "_SETUP_WRAPPED=1"
    cmd /k call "%~f0" %*
    exit /b
)
setlocal enabledelayedexpansion
chcp 65001 >nul 2>&1
cd /d "%~dp0" 2>nul

echo ============================================================
echo  DEStroyer Environment Scanner
echo ============================================================
echo.

set "FOUND_COUNT=0"
set "MISSING_COUNT=0"

set "VSWHERE="
if exist "C:\Program Files (x86)\Microsoft Visual Studio\Installer\vswhere.exe" (
    set "VSWHERE=C:\Program Files (x86)\Microsoft Visual Studio\Installer\vswhere.exe"
)
if not defined VSWHERE if exist "C:\Program Files\Microsoft Visual Studio\Installer\vswhere.exe" (
    set "VSWHERE=C:\Program Files\Microsoft Visual Studio\Installer\vswhere.exe"
)

echo [1/6] Scanning for Visual Studio installations...
echo.
set "VS_FOUND="
set "VCVARS="
set "VS_INSTALL_PATH="

if not defined VSWHERE goto :vs_no_vswhere
echo   Using vswhere.exe...

for /f "usebackq tokens=*" %%I in (`"!VSWHERE!" -all -products * -property installationPath`) do (
    echo   [FOUND] %%I
    if not defined VS_INSTALL_PATH set "VS_INSTALL_PATH=%%I"
    set "VS_FOUND=yes"
)

if not defined VS_INSTALL_PATH goto :vs_no_vswhere

if exist "!VS_INSTALL_PATH!\VC\Auxiliary\Build\vcvarsall.bat" (
    set "VCVARS=!VS_INSTALL_PATH!\VC\Auxiliary\Build\vcvarsall.bat"
)

for /f "usebackq tokens=*" %%V in (`"!VSWHERE!" -latest -products * -property catalog_productLineVersion`) do (
    set "VS_VER=%%V"
)
if defined VS_VER echo   Latest version: !VS_VER!

:vs_no_vswhere
if defined VS_FOUND goto :vs_scan_done
echo   vswhere not found or returned nothing, scanning manually...
for %%L in (C D E F G H I J K L M N O P Q R S T U V W X Y Z) do (
    if exist "%%L:\" (
        for %%V in (2026 2022 2019) do (
            for %%E in (Enterprise Professional Community BuildTools) do (
                if exist "%%L:\Program Files\Microsoft Visual Studio\%%V\%%E\VC\Auxiliary\Build\vcvarsall.bat" (
                    echo   [FOUND] Visual Studio %%V %%E on %%L: drive
                    if not defined VCVARS (
                        set "VCVARS=%%L:\Program Files\Microsoft Visual Studio\%%V\%%E\VC\Auxiliary\Build\vcvarsall.bat"
                        set "VS_FOUND=%%V %%E"
                    )
                )
            )
        )
    )
)
:vs_scan_done
if defined VS_FOUND set /a FOUND_COUNT+=1
if not defined VS_FOUND (
    echo   [MISSING] No Visual Studio installation found
    set /a MISSING_COUNT+=1
)
echo.

echo [2/6] Scanning for MSVC compiler ^(cl.exe^)...
echo.
set "CL_FOUND="
where cl >nul 2>&1
if not errorlevel 1 (
    for /f "delims=" %%P in ('where cl') do if not defined CL_FOUND set "CL_FOUND=%%P"
)
if defined CL_FOUND (
    echo   [FOUND] cl.exe already on PATH: !CL_FOUND!
    set /a FOUND_COUNT+=1
)
if defined CL_FOUND goto :cl_done
if not defined VCVARS (
    echo   [MISSING] cl.exe not on PATH and no Visual Studio found to load it
    set /a MISSING_COUNT+=1
)
if not defined VCVARS goto :cl_done
echo   cl.exe not on PATH, loading from Visual Studio...
call "!VCVARS!" x64 >nul 2>&1
where cl >nul 2>&1
if not errorlevel 1 (
    for /f "delims=" %%P in ('where cl') do if not defined CL_FOUND set "CL_FOUND=%%P"
)
if defined CL_FOUND (
    echo   [FOUND] cl.exe loaded via vcvarsall: !CL_FOUND!
    set /a FOUND_COUNT+=1
)
if not defined CL_FOUND (
    echo   [FAILED] vcvarsall.bat ran but cl.exe still not on PATH
    set /a MISSING_COUNT+=1
)
:cl_done
echo.

echo [3/6] Scanning for CMake...
echo.
set "CMAKE_EXE="
where cmake >nul 2>&1
if not errorlevel 1 (
    for /f "delims=" %%P in ('where cmake') do if not defined CMAKE_EXE set "CMAKE_EXE=%%P"
)
if defined CMAKE_EXE (
    echo   [FOUND] cmake already on PATH: !CMAKE_EXE!
    set /a FOUND_COUNT+=1
)
if defined CMAKE_EXE goto :cmake_done

if not defined VS_INSTALL_PATH goto :cmake_no_vs
set "_VSCMAKE=!VS_INSTALL_PATH!\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe"
if exist "!_VSCMAKE!" (
    set "CMAKE_EXE=!_VSCMAKE!"
    echo   [FOUND] cmake from VS: !CMAKE_EXE!
    for %%F in ("!CMAKE_EXE!") do set "PATH=%%~dpF;!PATH!"
    set /a FOUND_COUNT+=1
)
:cmake_no_vs
if defined CMAKE_EXE goto :cmake_done

for %%L in (C D E F G H I J K L M N O P Q R S T U V W X Y Z) do (
    if not defined CMAKE_EXE if exist "%%L:\" (
        if exist "%%L:\Program Files\CMake\bin\cmake.exe" set "CMAKE_EXE=%%L:\Program Files\CMake\bin\cmake.exe"
    )
)
if not defined CMAKE_EXE if exist "C:\Program Files (x86)\CMake\bin\cmake.exe" set "CMAKE_EXE=C:\Program Files (x86)\CMake\bin\cmake.exe"
if not defined CMAKE_EXE if exist "C:\msys64\mingw64\bin\cmake.exe" set "CMAKE_EXE=C:\msys64\mingw64\bin\cmake.exe"
if not defined CMAKE_EXE if exist "C:\msys64\ucrt64\bin\cmake.exe" set "CMAKE_EXE=C:\msys64\ucrt64\bin\cmake.exe"
if not defined CMAKE_EXE if exist "C:\msys64\usr\bin\cmake.exe" set "CMAKE_EXE=C:\msys64\usr\bin\cmake.exe"
if defined CMAKE_EXE (
    echo   [FOUND] cmake: !CMAKE_EXE!
    for %%F in ("!CMAKE_EXE!") do set "PATH=%%~dpF;!PATH!"
    set /a FOUND_COUNT+=1
)
if not defined CMAKE_EXE (
    echo   [MISSING] cmake not found anywhere
    set /a MISSING_COUNT+=1
)
:cmake_done
echo.

echo [4/6] Scanning for Ninja...
echo.
set "NINJA_EXE="
where ninja >nul 2>&1
if not errorlevel 1 (
    for /f "delims=" %%P in ('where ninja') do if not defined NINJA_EXE set "NINJA_EXE=%%P"
)
if defined NINJA_EXE (
    echo   [FOUND] ninja already on PATH: !NINJA_EXE!
    set /a FOUND_COUNT+=1
)
if defined NINJA_EXE goto :ninja_done

if not defined VS_INSTALL_PATH goto :ninja_no_vs
set "_VSNINJA=!VS_INSTALL_PATH!\Common7\IDE\CommonExtensions\Microsoft\CMake\Ninja\ninja.exe"
if exist "!_VSNINJA!" (
    set "NINJA_EXE=!_VSNINJA!"
    echo   [FOUND] ninja from VS: !NINJA_EXE!
    for %%F in ("!NINJA_EXE!") do set "PATH=%%~dpF;!PATH!"
    set /a FOUND_COUNT+=1
)
:ninja_no_vs
if defined NINJA_EXE goto :ninja_done
echo   [MISSING] ninja not found ^(optional, build will use other generators^)
set /a MISSING_COUNT+=1
:ninja_done
echo.

echo [5/6] Scanning for MinGW / GCC...
echo.
set "GCC_EXE="
where gcc >nul 2>&1
if not errorlevel 1 (
    for /f "delims=" %%P in ('where gcc') do if not defined GCC_EXE set "GCC_EXE=%%P"
)
if defined GCC_EXE (
    echo   [FOUND] gcc already on PATH: !GCC_EXE!
    set /a FOUND_COUNT+=1
)
if defined GCC_EXE goto :gcc_done

set "MINGW_DIR="
if exist "C:\msys64\ucrt64\bin\gcc.exe" set "MINGW_DIR=C:\msys64\ucrt64\bin"
if not defined MINGW_DIR if exist "C:\msys64\mingw64\bin\gcc.exe" set "MINGW_DIR=C:\msys64\mingw64\bin"
if not defined MINGW_DIR if exist "C:\msys64\clang64\bin\gcc.exe" set "MINGW_DIR=C:\msys64\clang64\bin"
if not defined MINGW_DIR if exist "C:\mingw64\bin\gcc.exe" set "MINGW_DIR=C:\mingw64\bin"
if not defined MINGW_DIR if exist "C:\MinGW\bin\gcc.exe" set "MINGW_DIR=C:\MinGW\bin"
if not defined MINGW_DIR if exist "C:\tools\mingw64\bin\gcc.exe" set "MINGW_DIR=C:\tools\mingw64\bin"
if defined MINGW_DIR goto :mingw_found
for %%L in (D E F G H I J K L M N O P Q R S T U V W X Y Z) do (
    if not defined MINGW_DIR if exist "%%L:\" (
        if exist "%%L:\msys64\ucrt64\bin\gcc.exe" set "MINGW_DIR=%%L:\msys64\ucrt64\bin"
        if not defined MINGW_DIR if exist "%%L:\msys64\mingw64\bin\gcc.exe" set "MINGW_DIR=%%L:\msys64\mingw64\bin"
        if not defined MINGW_DIR if exist "%%L:\mingw64\bin\gcc.exe" set "MINGW_DIR=%%L:\mingw64\bin"
        if not defined MINGW_DIR if exist "%%L:\MinGW\bin\gcc.exe" set "MINGW_DIR=%%L:\MinGW\bin"
    )
)
:mingw_found
if defined MINGW_DIR (
    echo   [FOUND] gcc: !MINGW_DIR!\gcc.exe
    set "PATH=!MINGW_DIR!;!PATH!"
    set "GCC_EXE=!MINGW_DIR!\gcc.exe"
    set /a FOUND_COUNT+=1
)
if not defined MINGW_DIR if not defined GCC_EXE (
    echo   [MISSING] gcc not found ^(optional if using MSVC^)
    set /a MISSING_COUNT+=1
)
:gcc_done
echo.

echo [6/6] Scanning for CUDA toolkit ^(nvcc^)...
echo.
set "NVCC_EXE="
where nvcc >nul 2>&1
if not errorlevel 1 (
    for /f "delims=" %%P in ('where nvcc') do if not defined NVCC_EXE set "NVCC_EXE=%%P"
)
if defined NVCC_EXE (
    echo   [FOUND] nvcc already on PATH: !NVCC_EXE!
    set /a FOUND_COUNT+=1
)
if defined NVCC_EXE goto :nvcc_done

set "CUDA_DIR="
if defined CUDA_PATH if exist "!CUDA_PATH!\bin\nvcc.exe" set "CUDA_DIR=!CUDA_PATH!\bin"
if defined CUDA_DIR goto :cuda_found

for %%L in (C D E F G H I J K L M N O P Q R S T U V W X Y Z) do (
    if not defined CUDA_DIR if exist "%%L:\" (
        for %%X in (13.1 13.0 12.9 12.8 12.7 12.6 12.5 12.4 12.3 12.2 12.1 12.0 11.8 11.7) do (
            if not defined CUDA_DIR if exist "%%L:\Program Files\NVIDIA GPU Computing Toolkit\CUDA\v%%X\bin\nvcc.exe" (
                set "CUDA_DIR=%%L:\Program Files\NVIDIA GPU Computing Toolkit\CUDA\v%%X\bin"
            )
        )
    )
)

:cuda_found
if defined CUDA_DIR (
    echo   [FOUND] nvcc: !CUDA_DIR!\nvcc.exe
    set "PATH=!CUDA_DIR!;!PATH!"
    set "NVCC_EXE=!CUDA_DIR!\nvcc.exe"
    set /a FOUND_COUNT+=1
)
if not defined CUDA_DIR if not defined NVCC_EXE (
    echo   [MISSING] nvcc not found ^(GPU features will be disabled^)
    set /a MISSING_COUNT+=1
)
:nvcc_done
echo.

echo ============================================================
echo  Scan Complete: !FOUND_COUNT! found, !MISSING_COUNT! missing
echo ============================================================
echo.

set "CAN_BUILD="
if defined CL_FOUND set "CAN_BUILD=MSVC"
if not defined CAN_BUILD if defined GCC_EXE set "CAN_BUILD=MinGW"

if not defined CAN_BUILD (
    echo  [X] Cannot build: no C++ compiler available.
    echo.
    echo  To fix, install one of:
    echo    - Visual Studio 2026/2022/2019 with "Desktop development with C++" workload
    echo    - Build Tools: https://visualstudio.microsoft.com/downloads/
    echo    - MSYS2 + MinGW: https://www.msys2.org
    echo      then run: pacman -S mingw-w64-ucrt-x86_64-toolchain
    echo.
    exit /b 1
)

if not defined CMAKE_EXE (
    echo  [X] Cannot build: CMake is missing.
    echo.
    echo  Install from: https://cmake.org/download/
    echo  Or run: winget install Kitware.CMake
    echo.
    exit /b 1
)

echo  [OK] Ready to build with !CAN_BUILD!
if defined CMAKE_EXE echo       CMake:  !CMAKE_EXE!
if defined CL_FOUND   echo       MSVC:   !CL_FOUND!
if defined GCC_EXE    echo       GCC:    !GCC_EXE!
if defined NINJA_EXE  echo       Ninja:  !NINJA_EXE!
if defined NVCC_EXE   echo       CUDA:   !NVCC_EXE!
echo.
echo  PATH has been updated for this session.
echo  You can now run build.bat or use cmake directly.
echo.

endlocal ^
 & set "PATH=%PATH%"

exit /b 0
