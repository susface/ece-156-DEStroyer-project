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

set "VSWHERE="
if exist "C:\Program Files (x86)\Microsoft Visual Studio\Installer\vswhere.exe" (
    set "VSWHERE=C:\Program Files (x86)\Microsoft Visual Studio\Installer\vswhere.exe"
)
if not defined VSWHERE if exist "C:\Program Files\Microsoft Visual Studio\Installer\vswhere.exe" (
    set "VSWHERE=C:\Program Files\Microsoft Visual Studio\Installer\vswhere.exe"
)

set "VS_INSTALL_PATH="
set "VCVARS="

if not defined VSWHERE goto :skip_vswhere
echo Using vswhere.exe to locate Visual Studio...

for /f "usebackq tokens=*" %%I in (`"!VSWHERE!" -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath`) do (
    if not defined VS_INSTALL_PATH set "VS_INSTALL_PATH=%%I"
)
if not defined VS_INSTALL_PATH (
    for /f "usebackq tokens=*" %%I in (`"!VSWHERE!" -latest -products * -property installationPath`) do (
        if not defined VS_INSTALL_PATH set "VS_INSTALL_PATH=%%I"
    )
)
if not defined VS_INSTALL_PATH goto :skip_vswhere

if exist "!VS_INSTALL_PATH!\VC\Auxiliary\Build\vcvarsall.bat" (
    set "VCVARS=!VS_INSTALL_PATH!\VC\Auxiliary\Build\vcvarsall.bat"
)

set "_VSVER="
for /f "usebackq tokens=*" %%V in (`"!VSWHERE!" -latest -products * -property installationVersion`) do (
    set "_VSVER=%%V"
)
echo Found Visual Studio at: !VS_INSTALL_PATH! ^(version !_VSVER!^)
:skip_vswhere

if defined VCVARS goto :vs_done
echo Scanning for Visual Studio manually...
for %%L in (C D E F G H I J K L M N O P Q R S T U V W X Y Z) do (
    if not defined VCVARS if exist "%%L:\" (
        for %%V in (2026 2022 2019) do (
            for %%E in (Enterprise Professional Community BuildTools) do (
                if not defined VCVARS if exist "%%L:\Program Files\Microsoft Visual Studio\%%V\%%E\VC\Auxiliary\Build\vcvarsall.bat" (
                    set "VCVARS=%%L:\Program Files\Microsoft Visual Studio\%%V\%%E\VC\Auxiliary\Build\vcvarsall.bat"
                    set "VS_INSTALL_PATH=%%L:\Program Files\Microsoft Visual Studio\%%V\%%E"
                    echo Found Visual Studio %%V on %%L: drive
                )
            )
        )
    )
)
:vs_done

set "CMAKE_EXE="
where cmake >nul 2>&1
if not errorlevel 1 (
    for /f "delims=" %%P in ('where cmake') do if not defined CMAKE_EXE set "CMAKE_EXE=%%P"
)
if defined CMAKE_EXE goto :cmake_ok

if not defined VS_INSTALL_PATH goto :cmake_no_vs
set "_VSCMAKE=!VS_INSTALL_PATH!\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe"
if exist "!_VSCMAKE!" (
    set "CMAKE_EXE=!_VSCMAKE!"
    echo Found CMake from VS: !CMAKE_EXE!
)
:cmake_no_vs
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
"!CMAKE_EXE!" --help >"%TEMP%\_cmake_gens.txt" 2>&1

for %%G in (
    "Visual Studio 18 2026"
    "Visual Studio 17 2022"
    "Visual Studio 16 2019"
    "Visual Studio 15 2017"
) do (
    if not defined VS_GEN (
        findstr /c:%%G "%TEMP%\_cmake_gens.txt" >nul 2>&1
        if not errorlevel 1 set "VS_GEN=%%~G"
    )
)
del "%TEMP%\_cmake_gens.txt" >nul 2>&1

if defined VS_GEN (
    echo CMake supports generator: !VS_GEN!
) else (
    echo CMake does not support any Visual Studio generators -- will use Ninja/NMake/MinGW.
)

set "NINJA_EXE="
where ninja >nul 2>&1
if not errorlevel 1 set "NINJA_EXE=ninja"
if defined NINJA_EXE goto :ninja_ok
if not defined VS_INSTALL_PATH goto :ninja_no_vs
set "_VSNINJA=!VS_INSTALL_PATH!\Common7\IDE\CommonExtensions\Microsoft\CMake\Ninja\ninja.exe"
if exist "!_VSNINJA!" (
    set "NINJA_EXE=!_VSNINJA!"
    echo Found Ninja from VS: !NINJA_EXE!
)
:ninja_no_vs
:ninja_ok

set "MINGW_DIR="
where gcc >nul 2>&1
if not errorlevel 1 goto :gcc_ok
if exist "C:\msys64\ucrt64\bin\gcc.exe" set "MINGW_DIR=C:\msys64\ucrt64\bin"
if not defined MINGW_DIR if exist "C:\msys64\mingw64\bin\gcc.exe" set "MINGW_DIR=C:\msys64\mingw64\bin"
if not defined MINGW_DIR if exist "C:\msys64\clang64\bin\gcc.exe" set "MINGW_DIR=C:\msys64\clang64\bin"
if not defined MINGW_DIR if exist "C:\mingw64\bin\gcc.exe" set "MINGW_DIR=C:\mingw64\bin"
if not defined MINGW_DIR if exist "C:\MinGW\bin\gcc.exe" set "MINGW_DIR=C:\MinGW\bin"
if not defined MINGW_DIR if exist "C:\tools\mingw64\bin\gcc.exe" set "MINGW_DIR=C:\tools\mingw64\bin"
if defined MINGW_DIR goto :mingw_add
for %%L in (D E F G H I J K L M N O P Q R S T U V W X Y Z) do (
    if not defined MINGW_DIR if exist "%%L:\" (
        if exist "%%L:\msys64\ucrt64\bin\gcc.exe" set "MINGW_DIR=%%L:\msys64\ucrt64\bin"
        if not defined MINGW_DIR if exist "%%L:\msys64\mingw64\bin\gcc.exe" set "MINGW_DIR=%%L:\msys64\mingw64\bin"
        if not defined MINGW_DIR if exist "%%L:\mingw64\bin\gcc.exe" set "MINGW_DIR=%%L:\mingw64\bin"
        if not defined MINGW_DIR if exist "%%L:\MinGW\bin\gcc.exe" set "MINGW_DIR=%%L:\MinGW\bin"
    )
)
:mingw_add
if defined MINGW_DIR (
    echo Found MinGW: !MINGW_DIR!
    set "PATH=!MINGW_DIR!;!PATH!"
)
:gcc_ok

set "NVCC_PATH="
where nvcc >nul 2>&1
if not errorlevel 1 (
    for /f "delims=" %%P in ('where nvcc') do if not defined NVCC_PATH set "NVCC_PATH=%%P"
)
if defined NVCC_PATH goto :nvcc_ok

set "CUDA_DIR="
if defined CUDA_PATH if exist "!CUDA_PATH!\bin\nvcc.exe" set "CUDA_DIR=!CUDA_PATH!\bin"
if defined CUDA_DIR goto :cuda_add

for %%L in (C D E F G H I J K L M N O P Q R S T U V W X Y Z) do (
    if not defined CUDA_DIR if exist "%%L:\" (
        for %%X in (13.1 13.0 12.9 12.8 12.7 12.6 12.5 12.4 12.3 12.2 12.1 12.0 11.8 11.7) do (
            if not defined CUDA_DIR if exist "%%L:\Program Files\NVIDIA GPU Computing Toolkit\CUDA\v%%X\bin\nvcc.exe" (
                set "CUDA_DIR=%%L:\Program Files\NVIDIA GPU Computing Toolkit\CUDA\v%%X\bin"
            )
        )
    )
)

:cuda_add
if defined CUDA_DIR (
    set "NVCC_PATH=!CUDA_DIR!\nvcc.exe"
    set "PATH=!CUDA_DIR!;!PATH!"
    echo Found CUDA: !NVCC_PATH!
)
:nvcc_ok

where cl >nul 2>&1
if not errorlevel 1 goto :env_ok
if not defined VCVARS goto :env_ok
echo Setting up MSVC environment...
call "!VCVARS!" x64
:env_ok

where cl >nul 2>&1
if not errorlevel 1 goto :compiler_ok
where gcc >nul 2>&1
if not errorlevel 1 goto :compiler_ok
echo.
echo WARNING: No C++ compiler found on PATH.
echo   MSVC: Install Visual Studio or Build Tools with C++ workload
echo   MinGW: Install MSYS2 from https://www.msys2.org
echo          then run: pacman -S mingw-w64-ucrt-x86_64-toolchain
echo.
:compiler_ok

if not exist "!BUILD_DIR!" mkdir "!BUILD_DIR!"
pushd "!BUILD_DIR!"

set BUILD_OK=0
set "GCC_C_FLAGS=-DCMAKE_C_FLAGS_RELEASE=-O2 -DNDEBUG"
set "GCC_CXX_FLAGS=-DCMAKE_CXX_FLAGS_RELEASE=-O2 -DNDEBUG"

set "CUDA_FLAG="
if defined NVCC_PATH set "CUDA_FLAG=-DCMAKE_CUDA_COMPILER=!NVCC_PATH!"

if not defined VS_GEN goto :skip_vs
echo.
echo === Trying generator: !VS_GEN! ===
echo.
if exist CMakeCache.txt del CMakeCache.txt >nul 2>&1
if exist CMakeFiles rmdir /s /q CMakeFiles >nul 2>&1
if defined CUDA_FLAG (
    "!CMAKE_EXE!" "!SRC_DIR!." -G "!VS_GEN!" -A x64 "!CUDA_FLAG!"
) else (
    "!CMAKE_EXE!" "!SRC_DIR!." -G "!VS_GEN!" -A x64
)
if not errorlevel 1 set BUILD_OK=1
:skip_vs

if not "!BUILD_OK!"=="0" goto :gen_ok
if not defined NINJA_EXE goto :skip_ninja
where cl >nul 2>&1
if errorlevel 1 goto :skip_ninja
echo.
echo === Trying generator: Ninja + MSVC ===
echo.
if exist CMakeCache.txt del CMakeCache.txt >nul 2>&1
if exist CMakeFiles rmdir /s /q CMakeFiles >nul 2>&1
if defined CUDA_FLAG (
    "!CMAKE_EXE!" "!SRC_DIR!." -G "Ninja" -DCMAKE_BUILD_TYPE=!BUILD_TYPE! "!CUDA_FLAG!"
) else (
    "!CMAKE_EXE!" "!SRC_DIR!." -G "Ninja" -DCMAKE_BUILD_TYPE=!BUILD_TYPE!
)
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
if defined CUDA_FLAG (
    "!CMAKE_EXE!" "!SRC_DIR!." -G "NMake Makefiles" -DCMAKE_BUILD_TYPE=!BUILD_TYPE! "!CUDA_FLAG!"
) else (
    "!CMAKE_EXE!" "!SRC_DIR!." -G "NMake Makefiles" -DCMAKE_BUILD_TYPE=!BUILD_TYPE!
)
if not errorlevel 1 set BUILD_OK=1
:skip_nmake

if not "!BUILD_OK!"=="0" goto :gen_ok
if not defined NINJA_EXE goto :skip_ninja_gcc
where gcc >nul 2>&1
if errorlevel 1 goto :skip_ninja_gcc
echo.
echo === Trying generator: Ninja + GCC ===
echo.
if exist CMakeCache.txt del CMakeCache.txt >nul 2>&1
if exist CMakeFiles rmdir /s /q CMakeFiles >nul 2>&1
if defined CUDA_FLAG (
    "!CMAKE_EXE!" "!SRC_DIR!." -G "Ninja" -DCMAKE_BUILD_TYPE=!BUILD_TYPE! "!GCC_C_FLAGS!" "!GCC_CXX_FLAGS!" "!CUDA_FLAG!"
) else (
    "!CMAKE_EXE!" "!SRC_DIR!." -G "Ninja" -DCMAKE_BUILD_TYPE=!BUILD_TYPE! "!GCC_C_FLAGS!" "!GCC_CXX_FLAGS!"
)
if not errorlevel 1 set BUILD_OK=1
:skip_ninja_gcc

if not "!BUILD_OK!"=="0" goto :gen_ok
where gcc >nul 2>&1
if errorlevel 1 goto :skip_mingw
echo.
echo === Trying generator: MinGW Makefiles ===
echo.
if exist CMakeCache.txt del CMakeCache.txt >nul 2>&1
if exist CMakeFiles rmdir /s /q CMakeFiles >nul 2>&1
if defined CUDA_FLAG (
    "!CMAKE_EXE!" "!SRC_DIR!." -G "MinGW Makefiles" -DCMAKE_BUILD_TYPE=!BUILD_TYPE! "!GCC_C_FLAGS!" "!GCC_CXX_FLAGS!" "!CUDA_FLAG!"
) else (
    "!CMAKE_EXE!" "!SRC_DIR!." -G "MinGW Makefiles" -DCMAKE_BUILD_TYPE=!BUILD_TYPE! "!GCC_C_FLAGS!" "!GCC_CXX_FLAGS!"
)
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
