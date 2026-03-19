cmake_minimum_required(VERSION 3.14)

project(example_sdl3_metal LANGUAGES C CXX OBJCXX)

set(CMAKE_CXX_STANDARD 11)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

find_package(PkgConfig REQUIRED)
pkg_check_modules(SDL3 REQUIRED sdl3)

set(IMGUI_DIR "imgui")
set(SQLITE_DIR "sqllite")

set(SOURCES
    main.mm
    ${IMGUI_DIR}/imgui.cpp
    ${IMGUI_DIR}/imgui_demo.cpp
    ${IMGUI_DIR}/imgui_draw.cpp
    ${IMGUI_DIR}/imgui_tables.cpp
    ${IMGUI_DIR}/imgui_widgets.cpp
    ${IMGUI_DIR}/backends/imgui_impl_sdl3.cpp
    ${IMGUI_DIR}/backends/imgui_impl_metal.mm
    ${SQLITE_DIR}/sqlite3.c
)

add_executable(example_sdl3_metal ${SOURCES})
# add_subdirectory(${SQLITE_DIR})

# Add include dirs (only add OPENSSL include if provided)
target_include_directories(example_sdl3_metal PRIVATE
    ${IMGUI_DIR}
    ${IMGUI_DIR}/backends
    ${SDL3_INCLUDE_DIRS}
    ${SQLITE_DIR}
)

target_compile_options(example_sdl3_metal PRIVATE -g3 -O0)

# Link libraries: prefer imported OpenSSL targets
target_link_libraries(example_sdl3_metal PRIVATE
    ${SDL3_LINK_LIBRARIES}
    # ${SQLITE_DIR}
    "-framework Metal -framework MetalKit -framework Cocoa -framework IOKit -framework CoreVideo -framework QuartzCore"
)

# Output dir
file(MAKE_DIRECTORY ${CMAKE_BINARY_DIR})
set_source_files_properties(${SQLITE_DIR}/sqlite3.c PROPERTIES LANGUAGE C)
set_target_properties(example_sdl3_metal PROPERTIES
    RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}"
)
