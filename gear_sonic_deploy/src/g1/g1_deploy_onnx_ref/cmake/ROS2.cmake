# =============================================================================
# ROS2 Configuration
# =============================================================================
# This file contains ROS2 library discovery and test configuration
# Used by both main executable and test executable

if(NOT rclcpp_FOUND OR NOT std_msgs_FOUND)
  message(WARNING "ROS2.cmake included but ROS2 not found")
  return()
endif()

message(STATUS "Configuring ROS2 support...")

# =============================================================================
# ROS2 Library Discovery
# =============================================================================

# Auto-discover ROS2 include directories dynamically
set(ROS2_INCLUDE_DIRS "")
set(ROS2_PREFIX_CANDIDATES
    "/opt/ros/jazzy"
    "/opt/ros/iron"
    "/opt/ros/humble"
    "/opt/ros/galactic"
    "/opt/ros/foxy"
    "/usr/local/ros/jazzy"
    "/usr/local/ros/iron"
    "/usr/local/ros/humble"
)

# Pixi / conda packages are installed directly at the environment prefix.
if(DEFINED ENV{CONDA_PREFIX} AND NOT "$ENV{CONDA_PREFIX}" STREQUAL "")
  message(STATUS "Detected conda environment at $ENV{CONDA_PREFIX}, adding to ROS2 prefix candidates")
  list(PREPEND ROS2_PREFIX_CANDIDATES "$ENV{CONDA_PREFIX}")
endif()

set(ROS2_DISTRO_FOUND "")
foreach(ros2_prefix IN LISTS ROS2_PREFIX_CANDIDATES)
  set(ros2_include_path "${ros2_prefix}/include")
  message(STATUS "Searching for ROS 2 headers in ${ros2_prefix}...")

  if(EXISTS "${ros2_include_path}")
  set(ROS2_INCLUDE_DIRS "${ros2_include_path}")
  set(ROS2_INSTALL_BASE "${ros2_prefix}")

  if(ros2_prefix MATCHES "/(jazzy|iron|humble|galactic|foxy)$")
    set(ROS2_DISTRO_FOUND "${CMAKE_MATCH_1}")
  else()
    set(ROS2_DISTRO_FOUND "pixi/conda")
  endif()

  message(STATUS "📦 Found ROS 2 (${ROS2_DISTRO_FOUND}) at ${ros2_prefix}")
  break()
  endif()
endforeach()

if(NOT ROS2_DISTRO_FOUND)
  message(FATAL_ERROR "ROS 2 headers were not found.")
endif()


list(REMOVE_DUPLICATES ROS2_INCLUDE_DIRS)

# Essential ROS2 libraries for basic pub/sub functionality
set(ESSENTIAL_LIB_PATTERNS
  "librclcpp.so*" "librcl.so*" "librcl_yaml_param_parser.so*"
  "librcpputils.so*" "librcutils.so*" "librmw.so*"
  "librmw_implementation.so*" "librmw_fastrtps_cpp.so*"
  "libstd_msgs__rosidl_typesupport_cpp.so*" "libstd_msgs__rosidl_generator_cpp.so*"
  "librosidl_typesupport_cpp.so*" "librosidl_runtime_cpp.so*" "librosidl_runtime_c.so*"
  "libbuiltin_interfaces__rosidl_typesupport_cpp.so*" "libbuiltin_interfaces__rosidl_generator_cpp.so*"
  "libstatistics_msgs__rosidl_typesupport_cpp.so*" "libstatistics_msgs__rosidl_generator_cpp.so*"
  "libtracetools.so*" "liblibstatistics_collector.so*"
  "libfastrtps.so*" "libfastcdr.so*" "libtinyxml2.so*" "libspdlog.so*" "libfmt.so*"
)

# Use CMAKE_SYSTEM_PROCESSOR for consistency with other CMakeLists
if(CMAKE_SYSTEM_PROCESSOR STREQUAL "x86_64")
  set(SYSTEM_LIB_DIR "/usr/lib/x86_64-linux-gnu")
elseif(CMAKE_SYSTEM_PROCESSOR STREQUAL "aarch64")
  set(SYSTEM_LIB_DIR "/usr/lib/aarch64-linux-gnu")
else()
  set(SYSTEM_LIB_DIR "/usr/lib")
endif()

# Auto-discover ROS2 libraries using dynamic distro path
set(ROS2_LIBS "")
foreach(pattern ${ESSENTIAL_LIB_PATTERNS})
  # Use dynamically detected ROS2 installation
  file(GLOB ros2_libs "${ROS2_INSTALL_BASE}/lib/${pattern}")
  list(APPEND ROS2_LIBS ${ros2_libs})
  # Also check system library paths
  file(GLOB system_libs "/lib/${CMAKE_SYSTEM_PROCESSOR}-linux-gnu/${pattern}")
  list(APPEND ROS2_LIBS ${system_libs})
  file(GLOB usr_system_libs "${SYSTEM_LIB_DIR}/${pattern}")
  list(APPEND ROS2_LIBS ${usr_system_libs})
endforeach()

list(REMOVE_DUPLICATES ROS2_LIBS)
message(STATUS "Discovered ROS2 libraries: ${ROS2_LIBS}")
list(LENGTH ROS2_LIBS ROS2_LIB_COUNT)

message(STATUS "✅ ROS2 configuration: ${ROS2_LIB_COUNT} libraries discovered")

# =============================================================================
# ROS2 Test Executable
# =============================================================================

set(TEST_EXECUTABLE_NAME test_ros2)
add_executable(${TEST_EXECUTABLE_NAME} tests/test_ros2.cpp)

target_include_directories(${TEST_EXECUTABLE_NAME} PUBLIC ${CMAKE_CURRENT_SOURCE_DIR}/include/)
message(STATUS ${ROS2_INCLUDE_DIRS})
find_package(rclcpp REQUIRED)
find_package(std_msgs REQUIRED)
target_include_directories(${TEST_EXECUTABLE_NAME} PRIVATE
  ${rclcpp_INCLUDE_DIRS}
  ${std_msgs_INCLUDE_DIRS})
target_link_libraries(${TEST_EXECUTABLE_NAME} PRIVATE
  rclcpp::rclcpp
  std_msgs::std_msgs__rosidl_typesupport_cpp
  ${ROS2_LIBS}
  pthread)
target_compile_definitions(${TEST_EXECUTABLE_NAME} PRIVATE HAS_ROS2=1)

set_target_properties(${TEST_EXECUTABLE_NAME} PROPERTIES 
  RUNTIME_OUTPUT_DIRECTORY "${PROJECT_SOURCE_DIR}/target/release/"
  OUTPUT_NAME ${TEST_EXECUTABLE_NAME}
)

message(STATUS "✅ ROS2 test executable configured")

# =============================================================================
# Test Configuration Files
# =============================================================================

file(MAKE_DIRECTORY "${PROJECT_SOURCE_DIR}/target/release/config")
configure_file(
  "${CMAKE_CURRENT_SOURCE_DIR}/config/fastrtps_profile.xml"
  "${PROJECT_SOURCE_DIR}/target/release/config/fastrtps_profile.xml"
  COPYONLY
)

message(STATUS "✅ FastRTPS profile copied for test deployment")
