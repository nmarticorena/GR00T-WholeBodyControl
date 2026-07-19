#!/usr/bin/env python3
"""Publish a valid, neutral command for the G1 ROS2InputHandler.

The deployment constructs ``ROS2InputHandler`` in IK mode.  Consequently the
three ``*_after_ik`` fields below are complete 4x4 transforms, not identity
placeholders.  They are chosen so that, after the C++ handler applies its tool
offsets, the policy receives the documented neutral VR 3-point targets.
"""

from __future__ import annotations

import argparse
import math
from typing import Sequence

import msgpack
import rclpy
from rclpy.node import Node
from std_msgs.msg import ByteMultiArray


NEUTRAL_LEFT_POSITION = (0.0903, 0.1615, -0.2411)
NEUTRAL_RIGHT_POSITION = (0.1280, -0.1522, -0.2461)
NEUTRAL_HEAD_POSITION = (0.0241, -0.0081, 0.4028)

# Quaternions use the same (w, x, y, z) order as the C++ input interface.
NEUTRAL_LEFT_QUATERNION = (0.7295, 0.3145, 0.5533, -0.2506)
NEUTRAL_RIGHT_QUATERNION = (0.7320, -0.2639, 0.5395, 0.3217)
NEUTRAL_HEAD_QUATERNION = (0.9991, 0.0110, 0.0402, -0.0002)

LEFT_TOOL_OFFSET = (0.18, -0.025, 0.0)
RIGHT_TOOL_OFFSET = (0.18, 0.025, 0.0)
HEAD_TOOL_OFFSET = (0.0, 0.0, 0.35)


def make_input_transform(
    target_position: Sequence[float],
    quaternion: Sequence[float],
    tool_offset: Sequence[float],
) -> list[list[float]]:
    """Build the transform expected before ROS2InputHandler's tool offset."""
    w, x, y, z = quaternion
    norm = math.sqrt(w * w + x * x + y * y + z * z)
    w, x, y, z = (value / norm for value in (w, x, y, z))

    rotation = [
        [1.0 - 2.0 * (y * y + z * z), 2.0 * (x * y - z * w), 2.0 * (x * z + y * w)],
        [2.0 * (x * y + z * w), 1.0 - 2.0 * (x * x + z * z), 2.0 * (y * z - x * w)],
        [2.0 * (x * z - y * w), 2.0 * (y * z + x * w), 1.0 - 2.0 * (x * x + y * y)],
    ]
    rotated_offset = [
        sum(rotation[row][column] * tool_offset[column] for column in range(3))
        for row in range(3)
    ]
    translation = [
        target_position[index] - rotated_offset[index] for index in range(3)
    ]

    return [
        [*rotation[0], translation[0]],
        [*rotation[1], translation[1]],
        [*rotation[2], translation[2]],
        [0.0, 0.0, 0.0, 1.0],
    ]


NEUTRAL_LEFT_TRANSFORM = make_input_transform(
    NEUTRAL_LEFT_POSITION, NEUTRAL_LEFT_QUATERNION, LEFT_TOOL_OFFSET
)
NEUTRAL_RIGHT_TRANSFORM = make_input_transform(
    NEUTRAL_RIGHT_POSITION, NEUTRAL_RIGHT_QUATERNION, RIGHT_TOOL_OFFSET
)
NEUTRAL_HEAD_TRANSFORM = make_input_transform(
    NEUTRAL_HEAD_POSITION, NEUTRAL_HEAD_QUATERNION, HEAD_TOOL_OFFSET
)


class TestCommandPublisher(Node):
    def __init__(self, args: argparse.Namespace) -> None:
        super().__init__("g1_test_command_sender")
        self.publisher = self.create_publisher(ByteMultiArray, args.topic, 1)
        self.timer = self.create_timer(1.0 / args.rate, self.publish_command)
        self.message_count = 0
        self.args = args
        self.start_pending = args.start
        self.connected_cycles = 0

        self.get_logger().info(
            f"Publishing valid commands to {args.topic} at {args.rate:g} Hz"
        )
        self.get_logger().info(
            "Command: "
            f"velocity=[{args.forward:g}, {args.lateral:g}, {args.yaw:g}], "
            f"height={args.height:g}, mode={'fast' if args.fast else 'slow'}"
        )
        if args.start:
            self.get_logger().info(
                "Will send one START toggle after the deployment subscriber connects"
            )
        else:
            self.get_logger().info(
                "Policy activation is disabled; pass --start to send a START toggle"
            )
        self.get_logger().info("Press Ctrl+C to stop")

    def publish_command(self) -> None:
        # Give DDS several heartbeat cycles after discovery before the one-shot
        # toggle. This prevents the start pulse being lost during matching.
        if self.publisher.get_subscription_count() > 0:
            self.connected_cycles += 1
        else:
            self.connected_cycles = 0
        toggle_policy_action = self.start_pending and self.connected_cycles >= 5

        command = {
            "navigate_cmd": [
                self.args.forward,
                self.args.lateral,
                self.args.yaw,
            ],
            "wrist_pose": [
                0.0,
                0.0,
                0.0,
                1.0,
                0.0,
                0.0,
                0.0,
                0.0,
                0.0,
                0.0,
                1.0,
                0.0,
                0.0,
                0.0,
            ],
            "left_wrist_after_ik": NEUTRAL_LEFT_TRANSFORM,
            "right_wrist_after_ik": NEUTRAL_RIGHT_TRANSFORM,
            "head_after_ik": NEUTRAL_HEAD_TRANSFORM,
            "base_height_command": self.args.height,
            "toggle_policy_action": toggle_policy_action,
            "locomotion_mode": int(self.args.fast),
            "left_hand_joint": [0.0] * 7,
            "right_hand_joint": [0.0] * 7,
            "ros_timestamp": self.get_clock().now().nanoseconds / 1e9,
        }

        message = ByteMultiArray()
        # Assign bytes directly.  This preserves the octets across rclpy/RMW
        # implementations whose deprecated ``byte[]`` Python mapping differs.
        message.data = msgpack.packb(command, use_bin_type=True)
        self.publisher.publish(message)
        self.message_count += 1

        if toggle_policy_action:
            self.start_pending = False
            self.get_logger().info("Sent one START toggle")

        if self.message_count % 20 == 0:
            self.get_logger().info(
                f"Published {self.message_count} valid command heartbeats"
            )


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Publish valid msgpack commands to the G1 ROS2 input handler. "
            "The default is a neutral, stationary command without activation."
        )
    )
    parser.add_argument(
        "--topic",
        default="/ControlPolicy/upper_body_pose",
        help="ROS2 ByteMultiArray topic",
    )
    parser.add_argument(
        "--rate",
        type=float,
        default=20.0,
        help="publishing rate in Hz (default: 20)",
    )
    parser.add_argument("--forward", type=float, default=0.0, help="forward velocity in m/s")
    parser.add_argument("--lateral", type=float, default=0.0, help="lateral velocity in m/s")
    parser.add_argument("--yaw", type=float, default=0.0, help="yaw rate in rad/s")
    parser.add_argument(
        "--height",
        type=float,
        default=0.78,
        help="base height command in metres, from 0.1 to 0.88 (default: 0.78)",
    )
    parser.add_argument("--fast", action="store_true", help="select fast walking mode")
    parser.add_argument(
        "--start",
        action="store_true",
        help="send one policy START toggle after a subscriber connects",
    )
    args = parser.parse_args()
    if args.rate <= 0:
        parser.error("--rate must be greater than zero")
    if not 0.1 <= args.height <= 0.88:
        parser.error("--height must be between 0.1 and 0.88")
    numeric_values = (args.rate, args.forward, args.lateral, args.yaw, args.height)
    if not all(math.isfinite(value) for value in numeric_values):
        parser.error("all numeric arguments must be finite")
    return args


def main() -> None:
    args = parse_args()
    rclpy.init()
    node = TestCommandPublisher(args)

    try:
        rclpy.spin(node)
    except KeyboardInterrupt:
        pass
    finally:
        node.destroy_node()
        if rclpy.ok():
            rclpy.shutdown()


if __name__ == "__main__":
    main()
