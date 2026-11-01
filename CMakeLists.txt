# Copyright (c) 2026 Do Huy Toan (dhtoan). All rights reserved. See LICENSE.
cmake_minimum_required(VERSION 3.16)
project(DokeyCore VERSION 0.4.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

add_library(dokey_core STATIC
    src/engine.cpp
    src/vietnamese.cpp
    src/c_api.cpp
)
target_include_directories(dokey_core PUBLIC
    $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/include>
    $<INSTALL_INTERFACE:include>)
if(MSVC)
    target_compile_options(dokey_core PRIVATE /utf-8 /W4)
else()
    target_compile_options(dokey_core PRIVATE -Wall -Wextra)
endif()

add_executable(dokey tools/dokey_cli.cpp)
target_link_libraries(dokey PRIVATE dokey_core)
target_compile_definitions(dokey PRIVATE DOKEY_VERSION="${PROJECT_VERSION}")
if(MSVC)
    target_compile_options(dokey PRIVATE /utf-8)
endif()

include(GNUInstallDirs)
install(TARGETS dokey_core dokey
    RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR}
    ARCHIVE DESTINATION ${CMAKE_INSTALL_LIBDIR})
install(DIRECTORY include/dokey DESTINATION ${CMAKE_INSTALL_INCLUDEDIR})
install(FILES README.md SPEC.md LICENSE DESTINATION ${CMAKE_INSTALL_DATADIR}/doc/dokey)

enable_testing()
add_executable(dokey_tests tests/engine_tests.cpp)
target_link_libraries(dokey_tests PRIVATE dokey_core)
if(MSVC)
    target_compile_options(dokey_tests PRIVATE /utf-8)
endif()
target_compile_definitions(dokey_tests PRIVATE DOKEY_TEST_DATA="${CMAKE_CURRENT_SOURCE_DIR}/tests/data")
add_test(NAME dokey_tests COMMAND dokey_tests)
