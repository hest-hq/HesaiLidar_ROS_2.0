# JT128 bring-up on ROS 2

End-to-end recipe for bringing a JT128 up over Ethernet. Wiring, host networking, and the colcon build are identical to the XT32M2X — see `../xt32m/README.md` for those shared steps. This document only covers JT128-specific differences.

## What's in this folder

| File                                       | Purpose                                                                          |
|--------------------------------------------|----------------------------------------------------------------------------------|
| `config_jt128.yaml`                        | JT128-tuned driver config. Pass via `-p config_path:=...`.                       |
| `JT128_default_angle.csv`                  | Per-channel elevation/azimuth template (per-MODEL, not per-unit). Fallback if PTC fetch is unavailable. |
| `JT128_Firetime_Correction_File.csv`       | Per-channel laser firing offsets (µs). Required — JT128 does not fetch firetime over PTC. Copy of the SDK's bundled file. |
| `JT128_User_Manual_J01-en-260330.pdf`      | Manufacturer user manual.                                                        |
| `JT128-3D-Model.zip`                       | 3D mechanical model.                                                             |

## How JT128 differs from the XT32M2X

| Knob                         | JT128 behavior                                                             |
|------------------------------|----------------------------------------------------------------------------|
| Parser                       | `Udp1_4Parser` (shared with Pandar128 and OT128).                          |
| Channels                     | 128 (vs 32 on XT32M2X). Frame is up to ~1.6M pts.                          |
| Frame mode                   | Azimuth-based (same as XT — frames split when angle wraps).                |
| `firetimes_path`             | **Required.** Driver does NOT fetch firetime over PTC for JT128. Without an absolute path the driver logs a FATAL and runs with reduced timestamp precision. |
| `correction_file_path`       | Optional. Per-unit angle correction is fetched over PTC at startup; the bundled CSV is per-MODEL and only used as fallback. |
| `distance_correction_flag`   | Supported (parser feature: ✅). Off by default.                            |
| `send_imu_ros`               | JT128 emits IMU via `Udp1_4Parser`. Default is `true`; verify with `ros2 topic hz /lidar_imu` after bring-up. |
| `xt_spot_correction`         | XT-S only — leave `false`.                                                 |

## Bring-up

Wiring, host networking, and the colcon build are identical to the XT32M (the JT128 ships with the same `192.168.1.201` factory default). Once the host is on `192.168.1.0/24` and `ping 192.168.1.201` succeeds:

1. **Set the absolute firetime path** in `config_jt128.yaml`. The bundled file lives in this directory; you'll need its full path on this machine. Example:

   ```yaml
   firetimes_path: /home/<you>/hesai_ws/src/HesaiLidar_ROS_2.0/lidars/jt128/JT128_Firetime_Correction_File.csv
   ```

   This per-machine edit should not be committed (mirrors the convention used in `lidars/xt32m/config_xt32m.yaml`).

2. **Run the driver**:

   ```bash
   source ~/hesai_ws/install/setup.bash
   ros2 run hesai_ros_driver hesai_ros_driver_node \
       --ros-args -p config_path:=$HOME/hesai_ws/src/HesaiLidar_ROS_2.0/lidars/jt128/config_jt128.yaml
   ```

   Successful startup logs include `Read correction file from lidar success` and `Open firetime file success!`.

3. **Sanity-check the topics** in another terminal:

   ```bash
   ros2 topic hz /lidar_points        # expect ~10 Hz
   ros2 topic hz /lidar_imu           # if non-zero, IMU is flowing — keep send_imu_ros: true
   ros2 topic hz /lidar_packets       # raw packets for rosbag recording
   ```

   If `/lidar_imu` is silent after a few seconds, the firmware may not emit IMU on this unit; flip `send_imu_ros: false` in the config to drop the dead publisher.

4. **Open RViz** in another terminal:

   ```bash
   source /opt/ros/jazzy/setup.bash
   source ~/hesai_ws/install/setup.bash
   rviz2
   ```

   Set **Fixed Frame** to `hesai_lidar`, then **Add → By topic → /lidar_points → PointCloud2**.

## Multiple lidars on one host

The JT128 ships at the same factory IP as the XT32M2X and FTX (`192.168.1.201`), so only one lidar can be plugged in at a time unless you reconfigure their IPs over PTC. See the multi-lidar pattern in the root `README.md`.
