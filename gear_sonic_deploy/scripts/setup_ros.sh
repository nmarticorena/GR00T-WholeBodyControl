#!/bin/bash



# ROS2 Environment Setup - dynamically find ROS2 installation
ROS2_FOUND=false

# Conda / pixi ROS2 installation
if [ -n "${CONDA_PREFIX:-}" ]; then
    for ros2_setup_file in \
        "$CONDA_PREFIX/setup.bash" \
        "$CONDA_PREFIX/local_setup.bash"; do

        if [ -f "$ros2_setup_file" ]; then
            source "$ros2_setup_file"
            export RMW_IMPLEMENTATION=rmw_fastrtps_cpp
            export ROS_LOCALHOST_ONLY=1
            export HAS_ROS2=1
            ROS2_FOUND=true
            echo "✅ ROS2 found in conda environment: $CONDA_PREFIX"
            break
        fi
    done
fi
ROS2_FOUND=false # Lets hardcode remove it in the meantime

# Common ROS2 distributions in order of preference (newest first)
ROS2_DISTROS=("jazzy" "iron" "humble" "galactic" "foxy" "eloquent" "dashing" "crystal")
ROS2_INSTALL_PATHS=("/opt/ros" "/usr/local/ros" "$HOME/ros2_ws/install" )

for install_path in "${ROS2_INSTALL_PATHS[@]}"; do
    if [ "$ROS2_FOUND" = true ]; then
        break
    fi
    
    for distro in "${ROS2_DISTROS[@]}"; do
        ros2_setup_file="$install_path/$distro/setup.bash"
        if [ -f "$ros2_setup_file" ]; then
            source "$ros2_setup_file"
            export RMW_IMPLEMENTATION=rmw_fastrtps_cpp
            # Remove problematic system library path that conflicts with system GLIBC
            export LD_LIBRARY_PATH=$(echo $LD_LIBRARY_PATH | tr ':' '\n' | grep -v "$SYSTEM_LIB_DIR" | tr '\n' ':' | sed 's/:$//')
            echo "✅ ROS2 $distro found at $install_path/$distro - system manages all ROS2 dependencies"
            export HAS_ROS2=1
            export ROS_LOCALHOST_ONLY=1
            ROS2_FOUND=true
            break
        fi
    done
done

if [ "$ROS2_FOUND" = false ]; then
    echo "⚠️  ROS2 not found in common locations:"
    printf "   %s/<distro>\n" "${ROS2_INSTALL_PATHS[@]}"
    echo "   Install ROS2 system-wide for ROS2InputHandler support"
    echo "   Building will continue without ROS2InputHandler"
    export HAS_ROS2=0
fi

# Set up production FastRTPS profile
if [ -f "src/g1/g1_deploy_onnx_ref/config/fastrtps_profile.xml" ]; then
    export FASTRTPS_DEFAULT_PROFILES_FILE="$(pwd)/src/g1/g1_deploy_onnx_ref/config/fastrtps_profile.xml"
    echo "✅ FastRTPS production profile configured"
fi


