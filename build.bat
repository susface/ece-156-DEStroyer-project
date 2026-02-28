@echo off
chcp 65001 >nul

set EXE_NAME=mitm_2des
set BUILD_DIR=build
set BUILD_TYPE=Release

if "%1"=="clean" (
    echo Cleaning build directory...
    if exist %BUILD_DIR% rmdir /s /q %BUILD_DIR%
    echo Done.
    pause
    exit /b 0
)

REM ============================================================
REM Find cmake.exe -- check PATH first, then common VS locations
REM ============================================================
set CMAKE_EXE=cmake
where cmake >nul 2>&1
if errorlevel 1 (
    echo cmake not in PATH -- searching Visual Studio install locations...
    set CMAKE_EXE=

    for %%V in (2022 2019) do (
        for %%E in (Enterprise Professional Community BuildTools) do (
            for %%P in (
                "C:\Program Files\Microsoft Visual Studio\%%V\%%E\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe"
                "C:\Program Files (x86)\Microsoft Visual Studio\%%V\%%E\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe"
            ) do (
                if exist %%P (
                    if not defined CMAKE_EXE (
                        set CMAKE_EXE=%%~P
                        echo Found: %%~P
                    )
                )
            )
        )
    )

    if not defined CMAKE_EXE (
        echo.
        echo ERROR: cmake.exe not found. Try one of:
        echo   1. Open this bat from a "Developer Command Prompt for VS 2022"
        echo      Start Menu ^> Visual Studio 2022 ^> Developer Command Prompt
        echo   2. Add CMake to PATH manually:
        echo      VS install dir\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin
        echo.
        pause
        exit /b 1
    )
)

if not exist %BUILD_DIR% mkdir %BUILD_DIR%
cd %BUILD_DIR%

echo.
echo === Generating Visual Studio 2022 solution ===
echo.
"%CMAKE_EXE%" .. -G "Visual Studio 17 2022" -A x64

if errorlevel 1 (
    echo.
    echo ERROR: CMake generation failed.
    cd ..
    pause
    exit /b 1
)

echo.
echo === Building %BUILD_TYPE% ===
echo.
"%CMAKE_EXE%" --build . --config %BUILD_TYPE% --parallel

if errorlevel 1 (
    echo.
    echo ERROR: Build failed. See errors above.
    cd ..
    pause
    exit /b 1
)

echo.
echo ============================================================
echo  Build successful!
echo  Run: %BUILD_DIR%\%BUILD_TYPE%\%EXE_NAME%.exe
echo ============================================================

pause
cd ..
