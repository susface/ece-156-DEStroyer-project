cmake_minimum_required(VERSION 3.18)
project(mitm_2des_skeleton CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# Windows MSVC flags
set(CMAKE_CXX_FLAGS_RELEASE "/O2 /Ob2 /DNDEBUG")
add_compile_definitions(_CRT_SECURE_NO_WARNINGS)

if(NOT CMAKE_BUILD_TYPE AND NOT CMAKE_CONFIGURATION_TYPES)
    set(CMAKE_BUILD_TYPE Release CACHE STRING "Build type" FORCE)
endif()

add_executable(mitm_2des
    src/main.cpp
    src/ui.cpp
)

target_include_directories(mitm_2des PRIVATE include)
