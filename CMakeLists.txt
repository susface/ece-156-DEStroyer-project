cmake_minimum_required(VERSION 3.18...4.3)

# =============================================================================
# CUDA architecture MUST be set before project() -- CMake 4.0+ requirement.
# sm_75  = Turing      (RTX 20xx)
# sm_86  = Ampere      (RTX 30xx)
# sm_89  = Ada         (RTX 40xx)
# sm_120 = Blackwell   (RTX 50xx)  -- requires CUDA 12.8+ toolkit
#
# Including the GPU's native arch is critical: without a matching cubin the
# runtime falls back to PTX JIT, and old drivers may reject newer toolkits'
# PTX with "the provided PTX was compiled with an unsupported toolchain".
# =============================================================================
set(CMAKE_CUDA_ARCHITECTURES "75;86;89;120" CACHE STRING "CUDA architectures" FORCE)

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
    src/des_cpu.cpp      # CPU DES/2DES engine (Jose)
    src/mitm_cpu.cpp     # CPU MITM + Brute-Force attacks (Armanjit)
    src/comparisons.cpp  # CPU/GPU + MITM/BF comparison + complexity sweep
)

if(HAVE_CUDA)
    list(APPEND SOURCES src/des_gpu.cu)
    add_compile_definitions(HAVE_CUDA CCCL_IGNORE_MSVC_TRADITIONAL_PREPROCESSOR_WARNING)
endif()

add_executable(mitm_2des ${SOURCES})
target_include_directories(mitm_2des PRIVATE
    include
    thrust-shim
)

if(HAVE_CUDA)
    # Disable separable compilation — not needed for a single TU kernel
    set_target_properties(mitm_2des PROPERTIES CUDA_SEPARABLE_COMPILATION OFF)

    # Link cudart dynamically so it uses the same /MD CRT as the rest of the
    # project.  Default (-cudart static) pulls in /MT objects and triggers
    # LNK4098 "LIBCMT conflicts with use of other libs".
    set_target_properties(mitm_2des PROPERTIES CUDA_RUNTIME_LIBRARY Shared)

    # CCCL (Thrust/CUB) uses variadic macros that break the traditional MSVC
    # preprocessor when multiple SM architectures are compiled simultaneously.
    # /Zc:preprocessor enables the conforming preprocessor which handles them.
    if(MSVC)
        target_compile_options(mitm_2des PRIVATE
            $<$<COMPILE_LANGUAGE:CUDA>:-Xcompiler=/Zc:preprocessor>)
    endif()
endif()
