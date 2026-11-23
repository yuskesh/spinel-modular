# Contract parsing and validation are independent of the MLIR frontend.
add_library(SpinelMLIRContract STATIC
  Model.cpp
  Reader.cpp)
target_include_directories(SpinelMLIRContract PUBLIC
  ${CMAKE_SOURCE_DIR}/include)
target_link_libraries(SpinelMLIRContract PUBLIC LLVMSupport)
