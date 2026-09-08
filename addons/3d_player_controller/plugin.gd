# Copyright (c) 2026 Antigravity Contributors
# SPDX-License-Identifier: MIT

@tool
extends EditorPlugin

## 3D Player Controller plugin editor integration.


func _enter_tree() -> void:
	add_custom_type(
		"Player",
		"CharacterBody3D",
		preload("res://addons/3d_player_controller/scripts/player.gd"),
		null
	)


func _exit_tree() -> void:
	remove_custom_type("Player")
