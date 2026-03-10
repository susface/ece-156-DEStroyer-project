cmake_minimum_required(VERSION 4.1.2-msvc8)
set(CMAKE_MODULE_PATH "")

project(CheckCUDA LANGUAGES CUDA)
file(WRITE "${CMAKE_CURRENT_BINARY_DIR}/result.cmake" "set(CMAKE_CUDA_COMPILER \"${CMAKE_CUDA_COMPILER}\")
")