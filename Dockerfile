# docker build -t hesai-ros:jazzy .
#
# Build for another distro:
#   docker build --build-arg ROS_DISTRO=humble  -t hesai-ros:humble  .
#   docker build --build-arg ROS_DISTRO=rolling -t hesai-ros:rolling .
#
# Run with RViz (requires host networking for the sensor + X11 for the GUI):
#   xhost +local:docker   # allow the container to talk to your X server
#   docker run --rm --network host \
#       -e DISPLAY=$DISPLAY \
#       -v /tmp/.X11-unix:/tmp/.X11-unix \
#       hesai-ros:jazzy
#
# Run headless (no RViz):
#   docker run --rm --network host hesai-ros:jazzy \
#       ros2 run hesai_ros_driver hesai_ros_driver_node
#
# Override config at runtime:
#   docker run --rm --network host \
#       -v $(pwd)/my_config.yaml:/ros2_ws/src/hesai_ros_driver/config/config.yaml:ro \
#       hesai-ros:jazzy

ARG ROS_DISTRO=jazzy
FROM docker.io/library/ros:${ROS_DISTRO}-ros-base

ARG ROS_DISTRO
ENV ROS_DISTRO=${ROS_DISTRO}
ENV DEBIAN_FRONTEND=noninteractive

# Build + system deps. Mirrors .github/workflows/build.yml.
RUN apt-get update && apt-get install -y --no-install-recommends \
      build-essential \
      cmake \
      git \
      python3-colcon-common-extensions \
      python3-rosdep \
      libboost-all-dev \
      libyaml-cpp-dev \
      ros-${ROS_DISTRO}-rviz2 \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /ros2_ws/src/hesai_ros_driver
COPY . .

RUN git config --global --add safe.directory '*' && \
    if [ -f src/driver/HesaiLidar_SDK_2.0/CMakeLists.txt ]; then \
        echo "SDK already populated in build context"; \
    elif [ -d .git ]; then \
        echo "Initializing submodule from parent repo"; \
        git submodule update --init --recursive; \
    else \
        echo "ERROR: SDK missing and no .git in build context."; \
        echo "       Either run 'git submodule update --init --recursive' on"; \
        echo "       the host before building, or build from a checkout that"; \
        echo "       still has its .git directory."; \
        exit 1; \
    fi && \
    test -f src/driver/HesaiLidar_SDK_2.0/CMakeLists.txt

WORKDIR /ros2_ws
RUN rosdep update --rosdistro=${ROS_DISTRO} \
 && rosdep install --from-paths src --ignore-src -r -y --rosdistro=${ROS_DISTRO}

RUN . /opt/ros/${ROS_DISTRO}/setup.sh \
 && colcon build --symlink-install \
      --cmake-args -DCMAKE_BUILD_TYPE=Release -DCMAKE_CXX_FLAGS=-Werror

# Entrypoint sources ROS and the workspace overlay before exec'ing CMD.
COPY ros_entrypoint.sh /ros_entrypoint.sh
RUN chmod +x /ros_entrypoint.sh

ENTRYPOINT ["/ros_entrypoint.sh"]

# Default: full launch (driver node + rviz2)
CMD ["ros2", "launch", "hesai_ros_driver", "start.py"]
