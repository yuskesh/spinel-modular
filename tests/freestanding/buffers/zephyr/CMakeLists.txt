cmake_minimum_required(VERSION 3.20.0)
find_package(Zephyr REQUIRED HINTS $ENV{ZEPHYR_BASE})
project(buffers_freestanding_data_abi)

# The freestanding object, its generated header and the generated case table all
# come from spinel-fs-emit / mkcases_inc.rb; Zephyr is only asked to link and run:
# the final link belongs to the platform.
if(NOT DEFINED SPINEL_OBJ)
  message(FATAL_ERROR "-DSPINEL_OBJ=<path to kern.o> is required")
endif()
if(NOT DEFINED SPINEL_GEN_DIR)
  message(FATAL_ERROR "-DSPINEL_GEN_DIR=<dir with spinel_freestanding.h and cases.inc> is required")
endif()

target_sources(app PRIVATE src/main.c)
target_include_directories(app PRIVATE ${SPINEL_GEN_DIR})
if(DEFINED BUFFERS_PANIC_TRAP)
  target_compile_definitions(app PRIVATE BUFFERS_PANIC_TRAP=1)
endif()

zephyr_link_libraries(${SPINEL_OBJ})
