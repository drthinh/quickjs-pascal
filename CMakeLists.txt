cmake_minimum_required(VERSION 3.10)

project(quickjs LANGUAGES C)

include(CheckCCompilerFlag)
include(GNUInstallDirs)

# Set visibility preset - use default for static libraries, hidden for shared
# Static libraries need default visibility so functions can be linked into executables
if(BUILD_SHARED_LIBS)
    set(CMAKE_C_VISIBILITY_PRESET hidden)
else()
    set(CMAKE_C_VISIBILITY_PRESET default)
endif()
set(CMAKE_C_STANDARD_REQUIRED ON)
set(CMAKE_C_EXTENSIONS ON)
set(CMAKE_C_STANDARD 11)

# MINGW doesn't exist in older cmake versions, newer versions don't know
# about CMAKE_COMPILER_IS_MINGW, and there is no unique CMAKE_C_COMPILER_ID
# for mingw-based compilers...
if(MINGW)
    # do nothing
elseif(CMAKE_C_COMPILER MATCHES "mingw")
    set(MINGW TRUE)
else()
    set(MINGW FALSE)
endif()

if(CMAKE_SYSTEM_NAME STREQUAL "tvOS")
    set(TVOS TRUE)
else()
    set(TVOS FALSE)
endif()
if(CMAKE_SYSTEM_NAME STREQUAL "watchOS")
    set(WATCHOS TRUE)
else()
    set(WATCHOS FALSE)
endif()

if(CMAKE_SYSTEM_NAME STREQUAL "SunOS")
    set(SUNOS TRUE)
else()
    set(SUNOS FALSE)
endif()

if(NOT CMAKE_BUILD_TYPE)
    message(STATUS "No build type selected, default to Release")
    set(CMAKE_BUILD_TYPE "Release")
endif()

message(STATUS "Building in ${CMAKE_BUILD_TYPE} mode")
message(STATUS "Building with ${CMAKE_C_COMPILER_ID} ${CMAKE_C_COMPILER_VERSION} on ${CMAKE_SYSTEM}")

macro(xcheck_add_c_compiler_flag FLAG)
    string(REPLACE "-" "" FLAG_NO_HYPHEN ${FLAG})
    check_c_compiler_flag(${FLAG} COMPILER_SUPPORTS_${FLAG_NO_HYPHEN})
    if(COMPILER_SUPPORTS_${FLAG_NO_HYPHEN})
        add_compile_options(${FLAG})
    endif()
endmacro()

xcheck_add_c_compiler_flag(-Wall)
if(NOT MSVC AND NOT IOS AND NOT TVOS AND NOT WATCHOS)
    xcheck_add_c_compiler_flag(-Werror)
    xcheck_add_c_compiler_flag(-Wextra)
endif()
xcheck_add_c_compiler_flag(-Wformat=2)
xcheck_add_c_compiler_flag(-Wno-implicit-fallthrough)
xcheck_add_c_compiler_flag(-Wno-sign-compare)
xcheck_add_c_compiler_flag(-Wno-missing-field-initializers)
xcheck_add_c_compiler_flag(-Wno-unused-parameter)
xcheck_add_c_compiler_flag(-Wno-unused-but-set-variable)
xcheck_add_c_compiler_flag(-Wno-unused-result)
xcheck_add_c_compiler_flag(-Wno-stringop-truncation)
xcheck_add_c_compiler_flag(-Wno-array-bounds)
if(NOT SUNOS)
xcheck_add_c_compiler_flag(-funsigned-char)
endif()

# ClangCL is command line compatible with MSVC, so 'MSVC' is set.
if(MSVC)
    xcheck_add_c_compiler_flag(-Wno-unsafe-buffer-usage)
    xcheck_add_c_compiler_flag(-Wno-sign-conversion)
    xcheck_add_c_compiler_flag(-Wno-nonportable-system-include-path)
    xcheck_add_c_compiler_flag(-Wno-implicit-int-conversion)
    xcheck_add_c_compiler_flag(-Wno-shorten-64-to-32)
    xcheck_add_c_compiler_flag(-Wno-reserved-macro-identifier)
    xcheck_add_c_compiler_flag(-Wno-reserved-identifier)
    xcheck_add_c_compiler_flag(-Wdeprecated-declarations)
    xcheck_add_c_compiler_flag(/experimental:c11atomics)
    xcheck_add_c_compiler_flag(/wd4018) # -Wno-sign-conversion
    xcheck_add_c_compiler_flag(/wd4061) # -Wno-implicit-fallthrough
    xcheck_add_c_compiler_flag(/wd4100) # -Wno-unused-parameter
    xcheck_add_c_compiler_flag(/wd4200) # -Wno-zero-length-array
    xcheck_add_c_compiler_flag(/wd4242) # -Wno-shorten-64-to-32
    xcheck_add_c_compiler_flag(/wd4244) # -Wno-shorten-64-to-32
    xcheck_add_c_compiler_flag(/wd4245) # -Wno-sign-compare
    xcheck_add_c_compiler_flag(/wd4267) # -Wno-shorten-64-to-32
    xcheck_add_c_compiler_flag(/wd4388) # -Wno-sign-compare
    xcheck_add_c_compiler_flag(/wd4389) # -Wno-sign-compare
    xcheck_add_c_compiler_flag(/wd4456) # Hides previous local declaration
    xcheck_add_c_compiler_flag(/wd4457) # Hides function parameter
    xcheck_add_c_compiler_flag(/wd4710) # Function not inlined
    xcheck_add_c_compiler_flag(/wd4711) # Function was inlined
    xcheck_add_c_compiler_flag(/wd4820) # Padding added after construct
    xcheck_add_c_compiler_flag(/wd4996) # -Wdeprecated-declarations
    xcheck_add_c_compiler_flag(/wd5045) # Compiler will insert Spectre mitigation for memory load if /Qspectre switch specified
endif()

# Set a 8MB default stack size on Windows.
# It defaults to 1MB on MSVC, which is the same as our current JS stack size,
# so it will overflow and crash otherwise.
# On MinGW it defaults to 2MB.
if(WIN32)
    if(MSVC)
        set(CMAKE_EXE_LINKER_FLAGS "${CMAKE_EXE_LINKER_FLAGS} /STACK:8388608")
        # Use static runtime to avoid CRT DLL dependencies (api-ms-win-crt-*.dll)
        # This sets the default for all targets - individual targets can override
        set(CMAKE_MSVC_RUNTIME_LIBRARY "MultiThreaded$<$<CONFIG:Debug>:Debug>")
        # Disable Universal CRT dependencies
        add_compile_definitions(_CRT_SECURE_NO_WARNINGS)
        # Explicitly link with static runtime libraries to avoid UCRT DLL dependencies
        # /MT uses libcmt.lib (static) instead of msvcrt.lib (DLL) or ucrt.lib (UCRT DLL)
        # This should prevent dependencies on api-ms-win-crt-*.dll
    else()
        set(CMAKE_EXE_LINKER_FLAGS "${CMAKE_EXE_LINKER_FLAGS} -Wl,--stack,8388608")
        # Static linking for MinGW to avoid CRT DLL dependencies
        # NOTE: On Windows 10/11, MinGW-w64 uses Universal C Runtime (UCRT) by default.
        # This creates dependencies on api-ms-win-crt-*.dll, which are system DLLs
        # that come with Windows 10/11. These dependencies are normal and acceptable.
        # To completely avoid UCRT dependencies, you would need:
        # 1. Use MSVC compiler with static runtime (handled above), OR
        # 2. Use an older MinGW build configured for msvcrt.dll instead of UCRT
        set(CMAKE_EXE_LINKER_FLAGS "${CMAKE_EXE_LINKER_FLAGS} -static -static-libgcc -static-libstdc++")
    endif()
endif()

# MacOS and GCC 11 or later need -Wno-maybe-uninitialized
# https://github.com/quickjs-ng/quickjs/issues/453
if(APPLE AND CMAKE_C_COMPILER_ID STREQUAL "GNU" AND CMAKE_C_COMPILER_VERSION VERSION_GREATER_EQUAL 11)
    xcheck_add_c_compiler_flag(-Wno-maybe-uninitialized)
endif()

if(CMAKE_SYSTEM_NAME STREQUAL "WASI")
    add_compile_definitions(
        _WASI_EMULATED_PROCESS_CLOCKS
        _WASI_EMULATED_SIGNAL
    )
    add_link_options(
        -lwasi-emulated-process-clocks
        -lwasi-emulated-signal
    )
endif()

if(CMAKE_BUILD_TYPE MATCHES "Debug")
    xcheck_add_c_compiler_flag(/Od)
    xcheck_add_c_compiler_flag(-O0)
    xcheck_add_c_compiler_flag(-ggdb)
    xcheck_add_c_compiler_flag(-fno-omit-frame-pointer)
else()
    # Size optimizations for Release builds
    if(MSVC)
        xcheck_add_c_compiler_flag(/O1)  # Optimize for size
        xcheck_add_c_compiler_flag(/GL) # Whole program optimization
        add_link_options(/LTCG)         # Link-time code generation
    else()
        xcheck_add_c_compiler_flag(-Os) # Optimize for size
        xcheck_add_c_compiler_flag(-ffunction-sections)
        xcheck_add_c_compiler_flag(-fdata-sections)
        add_link_options(-Wl,--gc-sections)
        if(NOT CMAKE_BUILD_TYPE MATCHES "Debug")
            add_link_options(-Wl,--strip-all)
        endif()
    endif()
endif()

macro(xoption OPTION_NAME OPTION_TEXT OPTION_DEFAULT)
    option(${OPTION_NAME} ${OPTION_TEXT} ${OPTION_DEFAULT})
    if(DEFINED ENV{${OPTION_NAME}})
        # Allow setting the option through an environment variable.
        set(${OPTION_NAME} $ENV{${OPTION_NAME}})
    endif()
    if(${OPTION_NAME})
        add_definitions(-D${OPTION_NAME})
    endif()
    message(STATUS "  ${OPTION_NAME}: ${${OPTION_NAME}}")
endmacro()

xoption(BUILD_SHARED_LIBS "Build a shared library" OFF)
if(BUILD_SHARED_LIBS)
    message(STATUS "Building a shared library")
endif()

# note: QJS_ENABLE_TSAN is currently incompatible with the other sanitizers but we
# don't explicitly check for that because who knows what the future will bring?
# QJS_ENABLE_MSAN only works with clang at the time of writing; also not checked
# for the same reason
xoption(QJS_BUILD_EXAMPLES "Build examples" OFF)
xoption(QJS_BUILD_CLI_STATIC "Build a static qjs executable" OFF)
xoption(QJS_BUILD_CLI_WITH_MIMALLOC "Build the qjs executable with mimalloc" OFF)
xoption(QJS_BUILD_CLI_WITH_STATIC_MIMALLOC "Build the qjs executable with mimalloc (statically linked)" OFF)
xoption(QJS_DISABLE_PARSER "Disable JS source code parser" OFF)
xoption(QJS_ENABLE_ASAN "Enable AddressSanitizer (ASan)" OFF)
xoption(QJS_ENABLE_MSAN "Enable MemorySanitizer (MSan)" OFF)
xoption(QJS_ENABLE_TSAN "Enable ThreadSanitizer (TSan)" OFF)
xoption(QJS_ENABLE_UBSAN "Enable UndefinedBehaviorSanitizer (UBSan)" OFF)

if(QJS_ENABLE_ASAN)
message(STATUS "Building with ASan")
add_compile_options(
    -fsanitize=address
    -fno-sanitize-recover=all
    -fno-omit-frame-pointer
)
add_link_options(
    -fsanitize=address
    -fno-sanitize-recover=all
    -fno-omit-frame-pointer
)
endif()

if(QJS_ENABLE_MSAN)
message(STATUS "Building with MSan")
add_compile_options(
    -fsanitize=memory
    -fno-sanitize-recover=all
    -fno-omit-frame-pointer
)
add_link_options(
    -fsanitize=memory
    -fno-sanitize-recover=all
    -fno-omit-frame-pointer
)
endif()

if(QJS_ENABLE_TSAN)
message(STATUS "Building with TSan")
add_compile_options(
    -fsanitize=thread
    -fno-sanitize-recover=all
    -fno-omit-frame-pointer
)
add_link_options(
    -fsanitize=thread
    -fno-sanitize-recover=all
    -fno-omit-frame-pointer
)
endif()

if(QJS_ENABLE_UBSAN)
message(STATUS "Building with UBSan")
add_compile_options(
    -fsanitize=undefined
    -fno-sanitize-recover=all
    -fno-omit-frame-pointer
)
add_link_options(
    -fsanitize=undefined
    -fno-sanitize-recover=all
    -fno-omit-frame-pointer
)
endif()


# QuickJS library
#

xoption(QJS_BUILD_LIBC "Build standard library modules as part of the library" OFF)
macro(add_qjs_libc_if_needed target)
    if(NOT QJS_BUILD_LIBC)
        target_sources(${target} PRIVATE quickjs-libc.c)
        # When building with DLL and quickjs-libc.c is in the target (not in DLL),
        # functions in quickjs-libc.c need BUILD_QJS_DLL to be exported correctly
        if(BUILD_SHARED_LIBS AND WIN32)
            # Mark that this target has quickjs-libc.c
            set_target_properties(${target} PROPERTIES
                _HAS_QUICKJS_LIBC TRUE
            )
            # Define BUILD_QJS_DLL for the entire target so functions in quickjs-libc.c use dllexport
            # This will also affect other files, but functions from qjs library will still be
            # linked from DLL (they just won't use dllimport, which should work with MinGW)
            target_compile_definitions(${target} PRIVATE BUILD_QJS_DLL)
        endif()
    endif()
endmacro()
macro(add_static_if_needed target)
    if(QJS_BUILD_CLI_STATIC OR MINGW OR WIN32)
        if(MSVC)
            # MSVC static linking - already handled globally above
            # But ensure this target also uses static runtime
            set_target_properties(${target} PROPERTIES
                MSVC_RUNTIME_LIBRARY "MultiThreaded$<$<CONFIG:Debug>:Debug>")
        else()
            # For MinGW, use -static only if explicitly requested, otherwise just static runtime libs
            if(QJS_BUILD_CLI_STATIC AND MINGW)
                target_link_options(${target} PRIVATE -static -static-libgcc -static-libstdc++)
            else()
                # Only static runtime libraries, not full static linking
                target_link_options(${target} PRIVATE -static-libgcc -static-libstdc++)
            endif()
        endif()
        # For GCC/MinGW, ensure static linking and minimal dependencies
        # Note: --gc-sections is disabled for targets that link quickjs-libc.c
        # because it may remove symbols needed by the library
        if(CMAKE_C_COMPILER_ID STREQUAL "GNU" OR MINGW)
            # Minimize binary size, but be careful with gc-sections
            if(NOT CMAKE_BUILD_TYPE MATCHES "Debug")
                target_compile_options(${target} PRIVATE -Os -ffunction-sections -fdata-sections)
                # Only use --gc-sections if not linking quickjs-libc.c (which needs all symbols)
                # Check if target uses quickjs-libc.c by checking if QJS_BUILD_LIBC is OFF
                if(QJS_BUILD_LIBC)
                    target_link_options(${target} PRIVATE -Wl,--gc-sections -Wl,--strip-all)
                else()
                    # Don't use --gc-sections for targets with quickjs-libc.c to avoid removing needed symbols
                    target_link_options(${target} PRIVATE -Wl,--strip-all)
                endif()
            endif()
        endif()
    endif()
endmacro()

# Macro to add USE_QJS_DLL definition when linking with shared library
# Note: When QJS_BUILD_LIBC is OFF, targets have quickjs-libc.c directly.
# For those targets, we don't use USE_QJS_DLL because functions in quickjs-libc.c
# are defined in the same target and need BUILD_QJS_DLL (handled in add_qjs_libc_if_needed).
# Functions from qjs library will be linked from DLL without dllimport (works with MinGW).
macro(add_use_qjs_dll_if_needed target)
    if(BUILD_SHARED_LIBS)
        # Check if target has quickjs-libc.c (when QJS_BUILD_LIBC is OFF)
        get_target_property(HAS_QUICKJS_LIBC ${target} _HAS_QUICKJS_LIBC)
        if(NOT HAS_QUICKJS_LIBC)
            # Only use USE_QJS_DLL if target doesn't have quickjs-libc.c
            # (i.e., when QJS_BUILD_LIBC is ON, functions are in DLL)
            target_compile_definitions(${target} PRIVATE USE_QJS_DLL)
        endif()
    endif()
endmacro()

# Macro to add cutils.c when building with DLL for internal functions
# Internal functions like js__pstrcpy are not exported from DLL
macro(add_cutils_if_dll target)
    if(BUILD_SHARED_LIBS)
        target_sources(${target} PRIVATE cutils.c)
    endif()
endmacro()

set(qjs_sources
    cutils.c
    dtoa.c
    libregexp.c
    libunicode.c
    quickjs.c
    qar.c
    miniz/miniz.c
    miniz/miniz_tinfl.c
    miniz/miniz_tdef.c
)

if(QJS_BUILD_LIBC)
    list(APPEND qjs_sources quickjs-libc.c)
endif()
list(APPEND qjs_defines _GNU_SOURCE)
if(WIN32)
    # NB: Windows 7 is EOL and we are only supporting in so far as it doesn't interfere with progress.
    list(APPEND qjs_defines WIN32_LEAN_AND_MEAN _WIN32_WINNT=0x0601)
endif()
if(TVOS)
    list(APPEND qjs_defines _TVOS)
endif()
if(WATCHOS)
    list(APPEND qjs_defines _WATCHOS)
endif()
list(APPEND qjs_libs ${CMAKE_DL_LIBS})
find_package(Threads)
if(NOT CMAKE_SYSTEM_NAME STREQUAL "WASI")
    list(APPEND qjs_libs ${CMAKE_THREAD_LIBS_INIT})
endif()

# try to find libm
find_library(M_LIBRARIES m)
if(M_LIBRARIES OR CMAKE_C_COMPILER_ID STREQUAL "TinyCC")
    list(APPEND qjs_libs m)
endif()

add_library(qjs ${qjs_sources})
target_compile_definitions(qjs PRIVATE ${qjs_defines})
# Define MINIZ_EXPORT for DLL builds to export miniz functions
if(BUILD_SHARED_LIBS)
    if(WIN32)
        # For Windows (both MSVC and MinGW), use __declspec(dllexport)
        target_compile_definitions(qjs PRIVATE "MINIZ_EXPORT=__declspec(dllexport)")
    else()
        # For non-Windows, use visibility attribute
        target_compile_definitions(qjs PRIVATE "MINIZ_EXPORT=__attribute__((visibility(\\\"default\\\")))")
    endif()
endif()
target_include_directories(qjs PUBLIC
    $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}>
    $<INSTALL_INTERFACE:${CMAKE_INSTALL_INCLUDEDIR}>
)
# Suppress warnings for miniz source files
if(NOT MSVC)
    set_source_files_properties(
        miniz/miniz.c
        miniz/miniz_tinfl.c
        miniz/miniz_tdef.c
        PROPERTIES COMPILE_FLAGS "-Wno-unused-function -Wno-type-limits"
    )
endif()
target_link_libraries(qjs PUBLIC ${qjs_libs})

# Ensure functions are visible for static library linking
if(NOT BUILD_SHARED_LIBS)
    set_target_properties(qjs PROPERTIES C_VISIBILITY_PRESET default)
endif()

# Apply static runtime and size optimizations to library
if(WIN32 AND MSVC)
    set_target_properties(qjs PROPERTIES
        MSVC_RUNTIME_LIBRARY "MultiThreaded$<$<CONFIG:Debug>:Debug>")
endif()
if(NOT CMAKE_BUILD_TYPE MATCHES "Debug")
    if(MSVC)
        target_compile_options(qjs PRIVATE /O1 /GL)
        if(BUILD_SHARED_LIBS)
            target_link_options(qjs PRIVATE /LTCG)
        endif()
    else()
        target_compile_options(qjs PRIVATE -Os -ffunction-sections -fdata-sections)
        if(BUILD_SHARED_LIBS)
            target_link_options(qjs PRIVATE -Wl,--gc-sections)
        endif()
    endif()
endif()

# Export functions for QAR compilation, packaging, and loading
if(BUILD_SHARED_LIBS)
    # Define BUILD_QJS_DLL so that export macros work
    # JS_EXTERN and QAR_EXPORT will use __declspec(dllexport) on Windows with MSVC
    # This automatically exports all functions marked with JS_EXTERN/QAR_EXPORT
    target_compile_definitions(qjs PRIVATE BUILD_QJS_DLL)
    
    # For all platforms, ensure visibility is set correctly
    # On Windows with MSVC, __declspec(dllexport) in JS_EXTERN/QAR_EXPORT handles exports
    # On MinGW/GCC and non-Windows, use visibility attributes
    if(NOT WIN32 OR NOT MSVC)
        # For MinGW/GCC and non-Windows, use visibility attributes
        # QAR_EXPORT and JS_EXTERN macros handle the exports
        set_target_properties(qjs PROPERTIES C_VISIBILITY_PRESET default)
    endif()
endif()

if(EMSCRIPTEN)
    add_executable(qjs_wasm ${qjs_sources})
    target_link_options(qjs_wasm PRIVATE
        # in emscripten 3.x, this will be set to 16k which is too small for quickjs. #write sth. to force github rebuild
        -sSTACK_SIZE=2097152 # let it be 2m = 2 * 1024 * 1024 = 2097152, otherwise, stack overflow may be occured at bootstrap
        -sNO_INVOKE_RUN
        -sNO_EXIT_RUNTIME
        -sMODULARIZE # do not mess the global
        -sEXPORT_ES6 # export js file to morden es module
        -sEXPORT_NAME=getQuickJs # give a name
        -sTEXTDECODER=1 # it will be 2 if we use -Oz, and that will cause js -> c string convertion fail
        -sNO_DEFAULT_TO_CXX # this project is pure c project, no need for c plus plus handle
        -sEXPORTED_RUNTIME_METHODS=ccall,cwrap
    )
    target_compile_definitions(qjs_wasm PRIVATE ${qjs_defines})
    target_link_libraries(qjs_wasm m)
endif()


# QuickJS bytecode compiler
#

add_executable(qjsc
    qjsc.c
)
add_cutils_if_dll(qjsc)
add_qjs_libc_if_needed(qjsc)
add_static_if_needed(qjsc)
# Explicitly set static runtime for qjsc to avoid UCRT DLL dependencies
if(MSVC)
    set_target_properties(qjsc PROPERTIES
        MSVC_RUNTIME_LIBRARY "MultiThreaded$<$<CONFIG:Debug>:Debug>"
    )
endif()
target_compile_definitions(qjsc PRIVATE ${qjs_defines})
add_use_qjs_dll_if_needed(qjsc)
# For MinGW, ensure qjs library symbols are fully included
# Use PUBLIC linking to ensure transitive dependencies are handled correctly
if(MINGW AND NOT BUILD_SHARED_LIBS)
    # Wrap qjs library with --whole-archive to include all symbols
    # This is necessary because static libraries may have symbols that appear unused
    target_link_options(qjsc PRIVATE -Wl,--whole-archive)
    target_link_libraries(qjsc PUBLIC qjs)
    target_link_options(qjsc PRIVATE -Wl,--no-whole-archive)
else()
    target_link_libraries(qjsc PRIVATE qjs)
endif()
add_dependencies(qjsc qjs)

# QuickJS Archive (QAR) packager
#

add_executable(qjar
    qjar.c
)
add_cutils_if_dll(qjar)
add_qjs_libc_if_needed(qjar)
add_static_if_needed(qjar)
# Explicitly set static runtime for qjar to avoid UCRT DLL dependencies
if(MSVC)
    set_target_properties(qjar PROPERTIES
        MSVC_RUNTIME_LIBRARY "MultiThreaded$<$<CONFIG:Debug>:Debug>"
    )
endif()
target_compile_definitions(qjar PRIVATE ${qjs_defines})
add_use_qjs_dll_if_needed(qjar)
target_link_libraries(qjar qjs)


# QuickJS CLI
#

add_executable(qjs_exe
    gen/repl.c
    gen/standalone.c
    qjs.c
)
add_cutils_if_dll(qjs_exe)
add_qjs_libc_if_needed(qjs_exe)
add_static_if_needed(qjs_exe)
set_target_properties(qjs_exe PROPERTIES
    OUTPUT_NAME "qjs"
)
# Explicitly set static runtime for qjs_exe to avoid UCRT DLL dependencies
if(MSVC)
    set_target_properties(qjs_exe PROPERTIES
        MSVC_RUNTIME_LIBRARY "MultiThreaded$<$<CONFIG:Debug>:Debug>"
    )
endif()
target_compile_definitions(qjs_exe PRIVATE ${qjs_defines})
add_use_qjs_dll_if_needed(qjs_exe)
target_link_libraries(qjs_exe qjs)
if(NOT WIN32)
    set_target_properties(qjs_exe PROPERTIES ENABLE_EXPORTS TRUE)
endif()
if(QJS_BUILD_CLI_WITH_MIMALLOC OR QJS_BUILD_CLI_WITH_STATIC_MIMALLOC)
    find_package(mimalloc REQUIRED)
    # Upstream mimalloc doesn't provide a way to know if both libraries are supported.
    if(QJS_BUILD_CLI_WITH_STATIC_MIMALLOC)
        target_link_libraries(qjs_exe mimalloc-static)
    else()
        target_link_libraries(qjs_exe mimalloc)
    endif()
endif()

# Test262 runner
#

if(NOT EMSCRIPTEN)
    add_executable(run-test262
        run-test262.c
    )
    add_cutils_if_dll(run-test262)
    add_qjs_libc_if_needed(run-test262)
    target_compile_definitions(run-test262 PRIVATE ${qjs_defines})
    add_use_qjs_dll_if_needed(run-test262)
    target_link_libraries(run-test262 qjs)
endif()

# Interrupt test
#

add_executable(api-test
    api-test.c
)
target_compile_definitions(api-test PRIVATE ${qjs_defines})
add_use_qjs_dll_if_needed(api-test)
target_link_libraries(api-test qjs)

# QAR test loader
add_executable(test_qar_load
    tests/test_qar_load.c
)
add_qjs_libc_if_needed(test_qar_load)
target_compile_definitions(test_qar_load PRIVATE ${qjs_defines})
add_use_qjs_dll_if_needed(test_qar_load)
target_link_libraries(test_qar_load qjs)

# Unicode generator
#

add_executable(unicode_gen EXCLUDE_FROM_ALL
    cutils.c
    libunicode.c
    unicode_gen.c
)
target_compile_definitions(unicode_gen PRIVATE ${qjs_defines})

add_executable(function_source
    gen/function_source.c
)
add_qjs_libc_if_needed(function_source)
target_include_directories(function_source PRIVATE ${CMAKE_CURRENT_SOURCE_DIR})
target_compile_definitions(function_source PRIVATE ${qjs_defines})
add_use_qjs_dll_if_needed(function_source)
target_link_libraries(function_source qjs)

# Examples
#

if(QJS_BUILD_EXAMPLES)
    add_executable(hello
        gen/hello.c
    )
    add_qjs_libc_if_needed(hello)
    target_include_directories(hello PRIVATE ${CMAKE_CURRENT_SOURCE_DIR})
    target_compile_definitions(hello PRIVATE ${qjs_defines})
    add_use_qjs_dll_if_needed(hello)
    target_link_libraries(hello qjs)

    add_executable(hello_module
        gen/hello_module.c
    )
    add_qjs_libc_if_needed(hello_module)
    target_include_directories(hello_module PRIVATE ${CMAKE_CURRENT_SOURCE_DIR})
    target_compile_definitions(hello_module PRIVATE ${qjs_defines})
    add_use_qjs_dll_if_needed(hello_module)
    target_link_libraries(hello_module qjs)

    add_library(fib MODULE examples/fib.c)
    set_target_properties(fib PROPERTIES
        PREFIX ""
        C_VISIBILITY_PRESET default
    )
    target_compile_definitions(fib PRIVATE JS_SHARED_LIBRARY)
    add_use_qjs_dll_if_needed(fib)
    if(WIN32)
        target_link_libraries(fib qjs)
    elseif(APPLE)
        target_link_options(fib PRIVATE -undefined dynamic_lookup)
    endif()

    add_library(point MODULE examples/point.c)
    set_target_properties(point PROPERTIES
        PREFIX ""
        C_VISIBILITY_PRESET default
    )
    target_compile_definitions(point PRIVATE JS_SHARED_LIBRARY)
    add_use_qjs_dll_if_needed(point)
    if(WIN32)
        target_link_libraries(point qjs)
    elseif(APPLE)
        target_link_options(point PRIVATE -undefined dynamic_lookup)
    endif()

    add_executable(test_fib
        examples/fib.c
        gen/test_fib.c
    )
    add_qjs_libc_if_needed(test_fib)
    target_include_directories(test_fib PRIVATE ${CMAKE_CURRENT_SOURCE_DIR})
    target_compile_definitions(test_fib PRIVATE ${qjs_defines})
    add_use_qjs_dll_if_needed(test_fib)
    target_link_libraries(test_fib qjs)
endif()

# Install target
#

file(STRINGS quickjs.h quickjs_h REGEX QJS_VERSION)
string(REGEX MATCH "QJS_VERSION_MAJOR ([0-9]*)" _ "${quickjs_h}")
set(QJS_VERSION_MAJOR ${CMAKE_MATCH_1})
string(REGEX MATCH "QJS_VERSION_MINOR ([0-9]*)" _ "${quickjs_h}")
set(QJS_VERSION_MINOR ${CMAKE_MATCH_1})
string(REGEX MATCH "QJS_VERSION_PATCH ([0-9]*)" _ "${quickjs_h}")
set(QJS_VERSION_PATCH ${CMAKE_MATCH_1})
set_target_properties(qjs PROPERTIES
    VERSION ${QJS_VERSION_MAJOR}.${QJS_VERSION_MINOR}.${QJS_VERSION_PATCH}
    SOVERSION ${QJS_VERSION_MAJOR}
)
install(FILES quickjs.h DESTINATION ${CMAKE_INSTALL_INCLUDEDIR})
install(FILES qar.h DESTINATION ${CMAKE_INSTALL_INCLUDEDIR})
if(QJS_BUILD_LIBC)
    install(FILES quickjs-libc.h DESTINATION ${CMAKE_INSTALL_INCLUDEDIR})
endif()
if(NOT IOS AND NOT TVOS AND NOT WATCHOS)
    install(TARGETS qjs_exe RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR})
    install(TARGETS qjsc RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR})
    install(TARGETS qjar RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR})
endif()
install(TARGETS qjs EXPORT qjsConfig
        RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR}
        LIBRARY DESTINATION ${CMAKE_INSTALL_LIBDIR}
        ARCHIVE DESTINATION ${CMAKE_INSTALL_LIBDIR})
install(EXPORT qjsConfig DESTINATION ${CMAKE_INSTALL_LIBDIR}/cmake/quickjs)
install(FILES LICENSE DESTINATION ${CMAKE_INSTALL_DOCDIR})
install(DIRECTORY examples DESTINATION ${CMAKE_INSTALL_DOCDIR})
