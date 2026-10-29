# Dokey for Windows - Win32 tray app on top of Dokey Core.
# Copyright (c) 2026 Do Huy Toan. All rights reserved.
#
#   cmake -S apps/windows -B build -A x64      (or Win32, ARM64)
#   cmake --build build --config Release
cmake_minimum_required(VERSION 3.16)

# Static CRT: Dokey.exe runs without the Visual C++ redistributable.
cmake_policy(SET CMP0091 NEW)
set(CMAKE_MSVC_RUNTIME_LIBRARY "MultiThreaded$<$<CONFIG:Debug>:Debug>")

project(DokeyWindows LANGUAGES CXX RC)

if(NOT WIN32)
    message(FATAL_ERROR "apps/windows builds on Windows only")
endif()

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# Version: -DDOKEY_APP_VERSION=1.2.3, else the one in the root CMakeLists.txt.
if(NOT DOKEY_APP_VERSION)
    file(STRINGS "${CMAKE_CURRENT_SOURCE_DIR}/../../CMakeLists.txt" _project REGEX "project\\(DokeyCore VERSION")
    string(REGEX MATCH "[0-9]+\\.[0-9]+\\.[0-9]+" DOKEY_APP_VERSION "${_project}")
endif()
string(REGEX MATCH "^([0-9]+)\\.([0-9]+)\\.([0-9]+)" _ver "${DOKEY_APP_VERSION}")
if(NOT _ver)
    message(FATAL_ERROR "DOKEY_APP_VERSION must look like 1.2.3, got '${DOKEY_APP_VERSION}'")
endif()
set(DOKEY_VER_MAJOR ${CMAKE_MATCH_1})
set(DOKEY_VER_MINOR ${CMAKE_MATCH_2})
set(DOKEY_VER_PATCH ${CMAKE_MATCH_3})
message(STATUS "Dokey for Windows ${DOKEY_APP_VERSION}")
configure_file(src/version.h.in "${CMAKE_CURRENT_BINARY_DIR}/generated/version.h" @ONLY)

# The engine, built with the same compiler settings as the app.
add_subdirectory("${CMAKE_CURRENT_SOURCE_DIR}/../.." dokey_core EXCLUDE_FROM_ALL)

add_executable(Dokey WIN32
    src/main.cpp
    src/keyboard.cpp
    src/panel.cpp
    src/settings.cpp
    res/dokey.rc
    res/dokey.manifest
)
target_include_directories(Dokey PRIVATE "${CMAKE_CURRENT_BINARY_DIR}/generated" "${CMAKE_CURRENT_SOURCE_DIR}/res")
target_link_libraries(Dokey PRIVATE dokey_core imm32 user32 gdi32 gdiplus dwmapi shell32 advapi32 version)
target_compile_definitions(Dokey PRIVATE
    UNICODE _UNICODE WIN32_LEAN_AND_MEAN NOMINMAX _WIN32_WINNT=0x0A00)
if(MSVC)
    target_compile_options(Dokey PRIVATE /utf-8 /W4 /permissive-)
    target_link_options(Dokey PRIVATE /OPT:REF /OPT:ICF)
endif()

# Unit test for the parts that do not need a desktop session.
enable_testing()
add_executable(dokey_windows_tests tests/inject_tests.cpp)
target_link_libraries(dokey_windows_tests PRIVATE dokey_core user32)
target_compile_definitions(dokey_windows_tests PRIVATE UNICODE _UNICODE WIN32_LEAN_AND_MEAN NOMINMAX)
if(MSVC)
    target_compile_options(dokey_windows_tests PRIVATE /utf-8 /W4)
endif()
add_test(NAME dokey_windows_tests COMMAND dokey_windows_tests)
