# XT32M2X bring-up on ROS 2

End-to-end recipe for bringing an XT32M2X up over Ethernet, from a sealed unit to a live point cloud in RViz on Ubuntu 24.04 / ROS 2 Jazzy. Other ROS 2 distros (Humble, Foxy, Dashing) work the same way — only the launch invocation differs (see the root `README.md`).

## What's in this folder

| File                                       | Purpose                                                                          |
|--------------------------------------------|----------------------------------------------------------------------------------|
| `config_xt32m.yaml`                        | XT32M2X-tuned driver config. Pass to the node via `-p config_path:=...`.         |
| `XT32M2X_Angle_Correction_File-1.csv`      | Per-channel elevation/azimuth offsets. Fallback if PTC fetch is unavailable.     |
| `XT32M2X_Firetime_Correction_File.csv`     | Per-channel laser firing offsets (µs). Fallback if PTC fetch is unavailable.     |
| `XT32M2X_Model.step`                       | 3D mechanical model.                                                             |
| `XT32M2X_User_Manual_X03-en-260410.pdf`    | Manufacturer user manual, revision X03. Referenced as "manual §x.y" below.       |

The driver normally pulls correction data live from the lidar over PTC (TCP/9347), so the CSVs only matter when PTC is blocked or you want deterministic offline startup.

## 1. Wire up the lidar

The XT32M2X exposes a single 9-pin Lemo socket (Lemo `EEG.0T.309.CLN`) carrying power, Ethernet, and GNSS. The pins required for first power-on (manual §2.3.1):

| Pin | Signal       | Wire (factory cable) | Notes                  |
|-----|--------------|----------------------|------------------------|
| 3   | GND          | Brown                | 0 V                    |
| 4   | VIN          | White                | DC 9–36 V              |
| 5   | Ethernet TX+ | Yellow               | to host RX+            |
| 6   | Ethernet TX- | Green                | to host RX-            |
| 7   | Ethernet RX+ | Pink                 | to host TX+            |
| 8   | Ethernet RX- | Gray                 | to host TX-            |

Pins 1 (GNSS PPS), 2 (GNSS NMEA), and the unused blue wire are only needed if you are time-syncing against an external GNSS source.

If you bought the optional connection box, plug the Lemo cable into the box and use its barrel jack and RJ45 instead — the wiring above is already done internally.

**Power supply.** The lidar pulls ≤10 W typical but peaks under 30 W. Use a supply rated for **at least 30 W** at 12–24 V DC. Cables longer than ~10 m at 12 V will brown-out the lidar; switch to 24 V for long runs (manual Appendix C). The lidar has no power switch — it boots and starts spinning as soon as VIN is applied. Before re-powering, hold VIN below 1 V for at least 50 ms.

> Strip the protective cover off the cover lens before powering up (manual §2 opening note).

## 2. Configure the host network

The lidar ships at `192.168.1.201/24` and broadcasts point clouds to the local subnet. Put the host on the same subnet (manual §2.5):

```bash
# Find the interface that will be cabled to the lidar.
ip -brief link

# Example: assign 192.168.1.100/24 to enp5s0. Replace enp5s0 with your interface.
sudo ip addr add 192.168.1.100/24 dev enp5s0
sudo ip link set enp5s0 up

# Verify the lidar replies to ping (lidar must be powered with Ethernet plugged in).
ping -c 3 192.168.1.201
```

Pick any host address from `192.168.1.2`–`200` or `202`–`254` (avoid `.201` — that is the lidar). To make the assignment survive reboots, use NetworkManager or netplan instead of `ip addr add`.

The XT32M2X uses these ports — open them on the host firewall if one is active:

| Port           | Protocol | Purpose                                  |
|----------------|----------|------------------------------------------|
| 2368           | UDP      | Point cloud data (lidar → host)          |
| 9347           | TCP      | PTC: status, settings, correction fetch  |
| 80             | TCP      | Web Control UI                           |
| 319, 320       | UDP      | PTP 1588v2 time sync (optional)          |

Once `ping` succeeds, point a browser at <http://192.168.1.201> to reach the built-in Web Control page (manual §4) to confirm `Spin Rate`, `Destination IP`, and `Lidar Destination Port`. If the host's IP doesn't match the lidar's `Destination IP` (default `255.255.255.255` = broadcast), no UDP point clouds will arrive — set Web Control's `Destination IP` to your host IP for unicast, or leave it on broadcast.

## 3. Build the package in a ROS 2 workspace

Install the prerequisites once:

```bash
sudo apt update
sudo apt install -y libboost-all-dev libyaml-cpp-dev
```

Then create the workspace and build:

```bash
mkdir -p ~/ros2_ws/src
cd ~/ros2_ws/src
git clone --recurse-submodules https://github.com/HesaiTechnology/HesaiLidar_ROS_2.0.git

cd ~/ros2_ws
source /opt/ros/jazzy/setup.bash      # or humble / foxy / dashing
colcon build --symlink-install
source install/setup.bash
```

If you cloned without `--recurse-submodules`, run `git submodule update --init --recursive` inside `src/HesaiLidar_ROS_2.0` before building — the SDK lives in `src/driver/HesaiLidar_SDK_2.0` as a git submodule.

## 4. Bring up the driver

With the lidar powered, the host on `192.168.1.0/24`, and `ping 192.168.1.201` working, run the node directly and point it at `config_xt32m.yaml`:

```bash
source ~/ros2_ws/install/setup.bash
ros2 run hesai_ros_driver hesai_ros_driver_node \
    --ros-args -p config_path:=$HOME/ros2_ws/src/HesaiLidar_ROS_2.0/xt32m/config_xt32m.yaml
```

The `config_path` parameter is read at startup (see `node/hesai_ros_driver_node.cc`); when set, it overrides the package's default `config/config.yaml`. The path must be absolute.

To also open RViz, run it in a second terminal pre-loaded with the package's RViz config:

```bash
rviz2 -d $(ros2 pkg prefix hesai_ros_driver)/share/hesai_ros_driver/rviz/rviz2.rviz
```

The default fixed frame is `hesai_lidar` and the points topic is `/hesai_ros_driver/lidar_points`.

Sanity-check the data in another terminal:

```bash
source ~/ros2_ws/install/setup.bash
ros2 topic list
ros2 topic hz /hesai_ros_driver/lidar_points    # expect ~10 Hz at 600 RPM
ros2 topic echo /hesai_ros_driver/lidar_points --once | head
```

## 5. Tweak the config

`xt32m/config_xt32m.yaml` is the only file you should need to edit. Common changes:

- **Spin rate / frame rate.** Set `speed: 300`, `600`, or `1200` (RPM → 5/10/20 Hz) under `lidar_udp_type` to push it to the lidar at startup, or change it in Web Control. Keep `default_frame_frequency` in step (10.0 = 600 RPM).
- **Static unicast destination.** If you've changed the lidar's `Destination IP` from broadcast to your host IP via Web Control, no driver change is needed.
- **Multiple lidars on one host.** Give each one a different `udp_port` (and `device_udp_src_port` if they share a destination IP). See the multi-lidar section in the root `README.md`.
- **Offline correction file.** If the host's PTC port is blocked or you want deterministic startup, set `correction_file_path` to the absolute path of `xt32m/XT32M2X_Angle_Correction_File-1.csv` and `firetimes_path` to the firetime CSV.
- **TF transform.** Set `transform_flag: true` and fill in `x/y/z/roll/pitch/yaw` to publish points in your robot frame instead of `hesai_lidar`.

## Troubleshooting

| Symptom                                | First things to check                                                                                                                                       |
|----------------------------------------|-------------------------------------------------------------------------------------------------------------------------------------------------------------|
| `ping 192.168.1.201` fails             | Power LED on the connection box / cable; host IP really on `192.168.1.0/24`; Ethernet link up (`ip -brief link`); cable seated; lidar not in standby.       |
| `ping` works, no `/lidar_points`       | Web Control → `Destination IP` matches host or is `255.255.255.255`; firewall allows UDP/2368; `udp_port` in YAML matches lidar's `Lidar Destination Port`. |
| Driver logs "PTC connect timeout"      | TCP/9347 reachable from host (`nc -zv 192.168.1.201 9347`); `use_ptc_connected: false` to skip PTC if you have set `correction_file_path` instead.          |
| Point cloud looks misaligned / layered | Confirm Web Control shows the right model; ensure `xt_spot_correction: false` (this flag is for XT-S only); apply the bundled correction CSV.               |
| Motor spins but no UDP at all          | `sudo tcpdump -i <iface> udp port 2368` to confirm packets reach the host; check Web Control `Azimuth FOV` is full (1–360); confirm lidar isn't standby.    |

For deeper bring-up issues see manual §6 (*Troubleshooting*) and the `device_log` JSON downloadable from Web Control.
