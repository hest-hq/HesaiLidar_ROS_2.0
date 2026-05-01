# FTX (PandarFT2) bring-up on ROS 2

End-to-end recipe for bringing an FTX up over Ethernet. Most steps are identical to the XT32M2X — see `../xt32m/README.md` for shared host-network setup, package build, and RViz instructions. This document only covers the FTX-specific differences.

## What's in this folder

| File              | Purpose                                                            |
|-------------------|--------------------------------------------------------------------|
| `config_ftx.yaml` | FTX-tuned driver config. Pass via `-p config_path:=...`.           |

The FTX angle correction file shipped in the SDK (`src/driver/HesaiLidar_SDK_2.0/correction/angle_correction/FTX_Angle Correction File.dat`) is a 78-byte placeholder, not a real correction — rely on PTC fetch or request the per-unit CSV from Hesai.

## How FTX differs from spinning lidars

The FTX is solid-state, so several config knobs that matter for spinning lidars are inert here:

| Knob                         | FTX behavior                                                               |
|------------------------------|----------------------------------------------------------------------------|
| `speed` (RPM)                | Not applicable — no rotor. Leave at `-1`.                                  |
| `frame_start_azimuth`        | Ignored. FTX frames split on Frame ID change, not azimuth.                 |
| `firetimes_path`             | Not used (parser feature: ❌). Leave empty; no FATAL on missing file.      |
| `distance_correction_flag`   | Not supported (parser feature: ❌). Leave `false`.                         |
| `send_imu_ros`               | FTX has no IMU — `false`.                                                  |
| `xt_spot_correction`         | XT-S only — leave `false`.                                                 |

Frame rate is set on the device itself (Web Control or firmware), not pushed by the driver. Adjust `default_frame_frequency` to match what the device is actually running.

## Bring-up

Wiring, host networking, and the colcon build are identical to the XT32M (the FTX ships with the same `192.168.1.201` factory default). Once the host is on `192.168.1.0/24` and `ping 192.168.1.201` succeeds:

```bash
source ~/hesai_ws/install/setup.bash
ros2 run hesai_ros_driver hesai_ros_driver_node \
    --ros-args -p config_path:=$HOME/hesai_ws/src/HesaiLidar_ROS_2.0/ftx/config_ftx.yaml
```

If you're swapping between an XT32M and an FTX on the same physical cable (both default to 192.168.1.201), only one can be plugged in at a time unless you reconfigure the lidar IPs via Web Control.

Open RViz in another terminal:

```bash
source /opt/ros/jazzy/setup.bash
source ~/hesai_ws/install/setup.bash
rviz2
```

In RViz: **Fixed Frame** → `hesai_lidar`, **Add → By topic → /lidar_points → PointCloud2**.
