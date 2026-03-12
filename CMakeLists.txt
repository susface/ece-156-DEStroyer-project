cmake_minimum_required(VERSION 3.18)

# =============================================================================
# CUDA architecture MUST be set before project() -- CMake 4.0+ requirement.
# sm_75 = Turing (RTX 20xx), sm_86 = Ampere (RTX 30xx), sm_89 = Ada (RTX 40xx)
# sm_100 (Blackwell) omitted: CUDA 13.1 emits warnings and we don't target it.
# =============================================================================
set(CMAKE_CUDA_ARCHITECTURES "75;86;89" CACHE STRING "CUDA architectures" FORCE)

include(CheckLanguage)
check_language(CUDA)

# =============================================================================
# Conditional project declaration: include CUDA language only when nvcc is found.
# If CUDA is missing, GPU sources are excluded and HAVE_CUDA is not defined,
# so all GPU menu options fall back to a "not available" message at runtime.
# =============================================================================
if(CMAKE_CUDA_COMPILER)
    project(mitm_2des CUDA CXX)
    set(HAVE_CUDA TRUE)
else()
    project(mitm_2des CXX)
    set(HAVE_CUDA FALSE)
endif()

# =============================================================================
# C++ / CUDA standards
# DO NOT use add_compile_options(/std:c++17) — it would be passed to nvcc as
# an input filename.  Use the CMake standard variables instead; each toolchain
# translates them correctly (/std:c++17 for MSVC, -std=c++17 for nvcc).
# =============================================================================
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

if(HAVE_CUDA)
    set(CMAKE_CUDA_STANDARD 17)
    set(CMAKE_CUDA_STANDARD_REQUIRED ON)
endif()

# Windows / MSVC flags
set(CMAKE_CXX_FLAGS_RELEASE "/O2 /Ob2 /DNDEBUG")
add_compile_definitions(_CRT_SECURE_NO_WARNINGS NOMINMAX)

if(NOT CMAKE_BUILD_TYPE AND NOT CMAKE_CONFIGURATION_TYPES)
    set(CMAKE_BUILD_TYPE Release CACHE STRING "Build type" FORCE)
endif()

# =============================================================================
# Source files
# =============================================================================
set(SOURCES
    src/main.cpp
    src/ui.cpp
    src/benchmark.cpp
    src/progress.cpp
)

if(HAVE_CUDA)
    list(APPEND SOURCES src/des_gpu.cu)
    add_compile_definitions(HAVE_CUDA)
endif()

add_executable(mitm_2des ${SOURCES})
target_include_directories(mitm_2des PRIVATE include)

if(HAVE_CUDA)
    # Disable separable compilation — not needed for a single TU kernel
    set_target_properties(mitm_2des PROPERTIES CUDA_SEPARABLE_COMPILATION OFF)
endif()
