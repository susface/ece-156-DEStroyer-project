cmake_minimum_required(VERSION 3.18)
project(mitm_2des_skeleton CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

add_executable(mitm_2des src/main.cpp)
target_compile_options(mitm_2des PRIVATE /W3 /O2)
