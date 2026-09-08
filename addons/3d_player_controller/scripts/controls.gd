class_name Controls
extends CanvasLayer

## On-screen input hints: registers the addon's InputMap actions at runtime (drop-in, no project.godot edits),
## swaps button textures per input device, and shows contextual action labels.

signal input_type_changed(input_type: InputType)

enum InputType {
	KEYBOARD_MOUSE,
	MICROSOFT,
	NINTENDO,
	SONY,
	TOUCH,
}

## InputMap actions registered in _ready when the project lacks them.
## keys = physical keycodes, keycodes = logical keycodes, buttons = joypad buttons, axes = [axis, value] pairs,
## mouse = mouse buttons; deadzone defaults to 0.2.
const ACTIONS: Dictionary = {
	"move_up": {"keys": [KEY_W], "axes": [[JOY_AXIS_LEFT_Y, -1.0]]}, ## Controller: (left-stick) forward, Keyboard: [W]
	"move_down": {"keys": [KEY_S], "axes": [[JOY_AXIS_LEFT_Y, 1.0]]}, ## Controller: (left-stick) backward, Keyboard: [S]
	"move_left": {"keys": [KEY_A], "axes": [[JOY_AXIS_LEFT_X, -1.0]]}, ## Controller: (left-stick) left, Keyboard: [A]
	"move_right": {"keys": [KEY_D], "axes": [[JOY_AXIS_LEFT_X, 1.0]]}, ## Controller: (left-stick) right, Keyboard: [D]
	"look_up": {"keys": [KEY_UP], "axes": [[JOY_AXIS_RIGHT_Y, -1.0]]}, ## Controller: (right-stick) up, Keyboard: [Up]
	"look_down": {"keys": [KEY_DOWN], "axes": [[JOY_AXIS_RIGHT_Y, 1.0]]}, ## Controller: (right-stick) down, Keyboard: [Down]
	"look_left": {"keys": [KEY_LEFT], "axes": [[JOY_AXIS_RIGHT_X, -1.0]]}, ## Controller: (right-stick) left, Keyboard: [Left]
	"look_right": {"keys": [KEY_RIGHT], "axes": [[JOY_AXIS_RIGHT_X, 1.0]]}, ## Controller: (right-stick) right, Keyboard: [Right]
	"action": {"keys": [KEY_E], "buttons": [JOY_BUTTON_A]}, ## Microsoft: Ⓐ, Nintendo: Ⓑ, Sony: Ⓧ, Keyboard: [E]
	"sprint": {"keys": [KEY_SHIFT], "buttons": [JOY_BUTTON_B]}, ## Microsoft: Ⓑ, Nintendo: Ⓐ, Sony: Ⓞ, Keyboard: [Shift]
	"attack": {"keys": [KEY_ALT], "buttons": [JOY_BUTTON_X]}, ## Microsoft: Ⓧ, Nintendo: Ⓨ, Sony: 🟗, Keyboard: [Alt]
	"jump": {"keys": [KEY_SPACE], "buttons": [JOY_BUTTON_Y]}, ## Microsoft: Ⓨ, Nintendo: Ⓧ, Sony: 🟕, Keyboard: [Space]
	"crouch": {"keys": [KEY_CTRL], "buttons": [JOY_BUTTON_LEFT_STICK]}, ## Controller: Ⓛ (left-stick click), Keyboard: [Ctrl]
	"scope": {"mouse": [MOUSE_BUTTON_MIDDLE], "buttons": [JOY_BUTTON_RIGHT_STICK]}, ## Controller: 🄬 (right-stick click), Mouse: [Middle-Mouse]
	"focus": {"mouse": [MOUSE_BUTTON_RIGHT], "axes": [[JOY_AXIS_TRIGGER_LEFT, 1.0]]}, ## Microsoft: 🄻T, Nintendo: Z🄻, Sony: 🄻2, Mouse: [Right-Click]
	"shoot": {"mouse": [MOUSE_BUTTON_LEFT], "axes": [[JOY_AXIS_TRIGGER_RIGHT, 1.0]]}, ## Microsoft: 🅁T, Nintendo: Z🅁, Sony: 🅁2, Mouse: [Left-Click]
	"ability": {"keys": [KEY_Q], "buttons": [JOY_BUTTON_LEFT_SHOULDER]}, ## Microsoft: 🄻B, Nintendo: L, Sony: L1, Keyboard: [Q]
	"throw": {"keys": [KEY_T], "buttons": [JOY_BUTTON_RIGHT_SHOULDER]},
	"reload": {"keys": [KEY_R]}, ## Refill the equipped firearm; an empty magazine also reloads on the next trigger pull. Keyboard: [R] ## Microsoft: 🅁B, Nintendo: R, Sony: R1, Keyboard: [T]
	"perspective": {"keys": [KEY_F5], "buttons": [JOY_BUTTON_BACK]}, ## Microsoft: ⧉, Nintendo: ⊝, Sony: ⦀, Keyboard: [F5]
	"share": {"keys": [KEY_PRINT], "buttons": [JOY_BUTTON_MISC1]}, ## Microsoft: ⧉, Nintendo: ⧇, Sony: Create, Keyboard: [PrtScn]
	"start": {"keys": [KEY_ESCAPE], "buttons": [JOY_BUTTON_START]}, ## Pause menu. Microsoft: ☰, Nintendo: ⊕, Sony: ☰, Keyboard: [Esc]
	"seeker": {"keys": [KEY_I], "buttons": [JOY_BUTTON_DPAD_UP]}, ## Controller: DPad Up, Keyboard: [I]
	"whistle": {"keys": [KEY_K], "buttons": [JOY_BUTTON_DPAD_DOWN]}, ## Controller: DPad Down, Keyboard: [K]
	"last_weapon": {"keys": [KEY_J], "buttons": [JOY_BUTTON_DPAD_LEFT]}, ## Controller: DPad Left, Keyboard: [J]
	"next_weapon": {"keys": [KEY_L], "buttons": [JOY_BUTTON_DPAD_RIGHT]}, ## Controller: DPad Right, Keyboard: [L]
	"broadcast": {"keys": [KEY_V]}, ## Push-to-talk. Keyboard: [V]
	"chat": {"keycodes": [KEY_ENTER, KEY_KP_ENTER]}, ## Opens the chat window; handled in _unhandled_input so menus keep Enter. Keyboard: [Enter]
	"ui_accept": {"deadzone": 0.5, "keycodes": [KEY_ENTER, KEY_KP_ENTER], "keys": [KEY_SPACE], "buttons": [JOY_BUTTON_A]},
	"ui_left": {"deadzone": 0.5, "buttons": [JOY_BUTTON_DPAD_LEFT]},
	"ui_right": {"deadzone": 0.5, "buttons": [JOY_BUTTON_DPAD_RIGHT]},
	"ui_up": {"deadzone": 0.5, "buttons": [JOY_BUTTON_DPAD_UP]},
	"ui_down": {"deadzone": 0.5, "buttons": [JOY_BUTTON_DPAD_DOWN]},
	"debug": {"keycodes": [KEY_F3]}, ## Debug HUD. Keyboard: [F3]
	"toggle_toon": {"keycodes": [KEY_F6]}, ## Toon shading filter on or off. Keyboard: [F6]
}

@export var player: Player
@export var input_deadzone: float = 0.05 ## Address joystick drift by setting a deadzone threshold for joystick motion inputs
@export_category("Keyboard and Mouse Textures")
@export var keyboard_mouse_button_0_normal: Texture2D ## Keyboard [E] key (Normal)
@export var keyboard_mouse_button_0_pressed: Texture2D ## Keyboard [E] key (Pressed)
@export var keyboard_mouse_button_1_normal: Texture2D ## Keyboard [Shift] key (Normal)
@export var keyboard_mouse_button_1_pressed: Texture2D ## Keyboard [Shift] key (Pressed)
@export var keyboard_mouse_button_2_normal: Texture2D ## Keyboard [Alt] key (Normal)
@export var keyboard_mouse_button_2_pressed: Texture2D ## Keyboard [Alt] key (Pressed)
@export var keyboard_mouse_button_3_normal: Texture2D ## Keyboard [Space] key (Normal)
@export var keyboard_mouse_button_3_pressed: Texture2D ## Keyboard [Space] key (Pressed)
@export var keyboard_mouse_button_4_normal: Texture2D ## Keyboard [F5] key (Normal)
@export var keyboard_mouse_button_4_pressed: Texture2D ## Keyboard [F5] key (Pressed)
@export var keyboard_mouse_button_15_normal: Texture2D ## Keyboard [Print] key (Normal)
@export var keyboard_mouse_button_15_pressed: Texture2D ## Keyboard [Print] key (Pressed)
@export var keyboard_mouse_button_6_normal: Texture2D ## Keyboard [Esc] key (Normal)
@export var keyboard_mouse_button_6_pressed: Texture2D ## Keyboard [Esc] key (Pressed)
@export var keyboard_mouse_button_7_normal: Texture2D ## Keyboard [Ctrl] key (Normal)
@export var keyboard_mouse_button_7_pressed: Texture2D ## Keyboard [Ctrl] key (Pressed)
@export var keyboard_mouse_button_8_normal: Texture2D ## Keyboard [Mouse-Scroll] key (Normal)
@export var keyboard_mouse_button_8_pressed: Texture2D ## Keyboard [Mouse-Scroll] key (Pressed)
@export var keyboard_mouse_button_9_normal: Texture2D ## Keyboard [Q] key (Normal)
@export var keyboard_mouse_button_9_pressed: Texture2D ## Keyboard [Q] key (Pressed)
@export var keyboard_mouse_button_10_normal: Texture2D ## Keyboard [T] key (Normal)
@export var keyboard_mouse_button_10_pressed: Texture2D ## Keyboard [T] key (Pressed)
@export var keyboard_mouse_axis_4_plus_normal: Texture2D ## Keyboard [Mouse-Left] key (Normal)
@export var keyboard_mouse_axis_4_plus_pressed: Texture2D ## Keyboard [Mouse-Left] key (Pressed)
@export var keyboard_mouse_axis_5_plus_normal: Texture2D ## Keyboard [Mouse-Right] key (Normal)
@export var keyboard_mouse_axis_5_plus_pressed: Texture2D ## Keyboard [Mouse-Right] key (Pressed)
@export_category("Microsoft Textures")
@export var microsoft_button_0_normal: Texture2D ## XBox A (Normal)
@export var microsoft_button_0_pressed: Texture2D ## XBox A (Pressed)
@export var microsoft_button_1_normal: Texture2D ## XBox B (Normal)
@export var microsoft_button_1_pressed: Texture2D ## XBox B (Pressed)
@export var microsoft_button_2_normal: Texture2D ## XBox X (Normal)
@export var microsoft_button_2_pressed: Texture2D ## XBox X (Pressed)
@export var microsoft_button_3_normal: Texture2D ## XBox Y (Normal)
@export var microsoft_button_3_pressed: Texture2D ## XBox Y (Pressed)
@export var microsoft_button_4_normal: Texture2D ## XBox Back(Normal)
@export var microsoft_button_4_pressed: Texture2D ## XBox Back (Pressed)
@export var microsoft_button_15_normal: Texture2D ## XBox Share (Normal)
@export var microsoft_button_15_pressed: Texture2D ## XBox Share (Pressed)
@export var microsoft_button_6_normal: Texture2D ## XBox Forward (Normal)
@export var microsoft_button_6_pressed: Texture2D ## XBox Forward (Pressed)
@export var microsoft_button_7_normal: Texture2D ## XBox LS (Normal)
@export var microsoft_button_7_pressed: Texture2D ## XBox LS (Pressed)
@export var microsoft_button_8_normal: Texture2D ## XBox RS (Normal)
@export var microsoft_button_8_pressed: Texture2D ## XBox RS (Pressed)
@export var microsoft_button_9_normal: Texture2D ## XBox LB (Normal)
@export var microsoft_button_9_pressed: Texture2D ## XBox LB (Pressed)
@export var microsoft_button_10_normal: Texture2D ## XBox RB (Normal)
@export var microsoft_button_10_pressed: Texture2D ## XBox RB (Pressed)
@export var microsoft_axis_4_plus_normal: Texture2D ## XBox LT (Normal)
@export var microsoft_axis_4_plus_pressed: Texture2D ## XBox LT (Pressed)
@export var microsoft_axis_5_plus_normal: Texture2D ## XBox RT (Normal)
@export var microsoft_axis_5_plus_pressed: Texture2D ## XBox RT (Pressed)
@export_category("Nintendo Textures")
@export var nintendo_button_0_normal: Texture2D ## Nintendo B (Normal)
@export var nintendo_button_0_pressed: Texture2D ## Nintendo B (Pressed)
@export var nintendo_button_1_normal: Texture2D ## Nintendo A (Normal)
@export var nintendo_button_1_pressed: Texture2D ## Nintendo A (Pressed)
@export var nintendo_button_2_normal: Texture2D ## Nintendo Y (Normal)
@export var nintendo_button_2_pressed: Texture2D ## Nintendo Y (Pressed)
@export var nintendo_button_3_normal: Texture2D ## Nintendo X (Normal)
@export var nintendo_button_3_pressed: Texture2D ## Nintendo X (Pressed)
@export var nintendo_button_4_normal: Texture2D ## Nintendo - (Normal)
@export var nintendo_button_4_pressed: Texture2D ## Nintendo - (Pressed)
@export var nintendo_button_15_normal: Texture2D ## Nintendo Share (Normal)
@export var nintendo_button_15_pressed: Texture2D ## Nintendo Share (Pressed)
@export var nintendo_button_6_normal: Texture2D ## Nintendo + (Normal)
@export var nintendo_button_6_pressed: Texture2D ## Nintendo + (Pressed)
@export var nintendo_button_7_normal: Texture2D ## Nintendo LS (Normal)
@export var nintendo_button_7_pressed: Texture2D ## Nintendo LS (Pressed)
@export var nintendo_button_8_normal: Texture2D ## Nintendo RS (Normal)
@export var nintendo_button_8_pressed: Texture2D ## Nintendo RS (Pressed)
@export var nintendo_button_9_normal: Texture2D ## Nintendo L (Normal)
@export var nintendo_button_9_pressed: Texture2D ## Nintendo L (Pressed)
@export var nintendo_button_10_normal: Texture2D ## Nintendo R (Normal)
@export var nintendo_button_10_pressed: Texture2D ## Nintendo R (Pressed)
@export var nintendo_axis_4_plus_normal: Texture2D ## Nintendo ZL (Normal)
@export var nintendo_axis_4_plus_pressed: Texture2D ## Nintendo ZL (Pressed)
@export var nintendo_axis_5_plus_normal: Texture2D ## Nintendo ZR (Normal)
@export var nintendo_axis_5_plus_pressed: Texture2D ## Nintendo ZR (Pressed)
@export_category("Sony Textures")
@export var sony_button_0_normal: Texture2D ## Sony Cross (Normal)
@export var sony_button_0_pressed: Texture2D ## Sony Cross (Pressed)
@export var sony_button_1_normal: Texture2D ## Sony Circle (Normal)
@export var sony_button_1_pressed: Texture2D ## Sony Circle (Pressed)
@export var sony_button_2_normal: Texture2D ## Sony Square (Normal)
@export var sony_button_2_pressed: Texture2D ## Sony Square (Pressed)
@export var sony_button_3_normal: Texture2D ## Sony Triangle (Normal)
@export var sony_button_3_pressed: Texture2D ## Sony Triangle (Pressed)
@export var sony_button_4_normal: Texture2D ## Sony Select (Normal)
@export var sony_button_4_pressed: Texture2D ## Sony Select (Pressed)
@export var sony_button_15_normal: Texture2D ## Sony Share (Normal)
@export var sony_button_15_pressed: Texture2D ## Sony Share (Pressed)
@export var sony_button_6_normal: Texture2D ## Sony Options (Normal)
@export var sony_button_6_pressed: Texture2D ## Sony Options (Pressed)
@export var sony_button_7_normal: Texture2D ## Sony L3 (Normal)
@export var sony_button_7_pressed: Texture2D ## Sony L3 (Pressed)
@export var sony_button_8_normal: Texture2D ## Sony R3 (Normal)
@export var sony_button_8_pressed: Texture2D ## Sony R3 (Pressed)
@export var sony_button_9_normal: Texture2D ## Sony L1 (Normal)
@export var sony_button_9_pressed: Texture2D ## Sony L1 (Pressed)
@export var sony_button_10_normal: Texture2D ## Sony R1 (Normal)
@export var sony_button_10_pressed: Texture2D ## Sony R1 (Pressed)
@export var sony_axis_4_plus_normal: Texture2D ## Sony L2 (Normal)
@export var sony_axis_4_plus_pressed: Texture2D ## Sony L2 (Pressed)
@export var sony_axis_5_plus_normal: Texture2D ## Sony R2 (Normal)
@export var sony_axis_5_plus_pressed: Texture2D ## Sony R2 (Pressed)

@onready var joypad_button_0: TouchScreenButton = $BottomRight/JoypadButton0 ## Joypad Button 0 (Bottom Action, Sony Cross, XBox A, Nintendo B)
@onready var joypad_button_0_label: Label = $BottomRight/JoypadButton0/Label
@onready var joypad_button_1: TouchScreenButton = $BottomRight/JoypadButton1 ## Joypad Button 1 (Right Action, Sony Circle, XBox B, Nintendo A)
@onready var joypad_button_1_label: Label = $BottomRight/JoypadButton1/Label
@onready var joypad_button_2: TouchScreenButton = $BottomRight/JoypadButton2 ## Joypad Button 2 (Left Action, Sony Square, XBox X, Nintendo Y)
@onready var joypad_button_2_label: Label = $BottomRight/JoypadButton2/Label
@onready var joypad_button_3: TouchScreenButton = $BottomRight/JoypadButton3 ## Joypad Button 3 (Top Action, Sony Triangle, XBox Y, Nintendo X)
@onready var joypad_button_3_label: Label = $BottomRight/JoypadButton3/Label
@onready var joypad_button_4: TouchScreenButton = $TopCenter/JoypadButton4 ## Joypad Button 4 (Back, Sony Select, XBox Back, Nintendo -)
@onready var joypad_button_4_label: Label = $TopCenter/JoypadButton4/Label
@onready var joypad_button_15: TouchScreenButton = $TopCenter/JoypadButton15 ## Joypad Button 15 (Share Action, Sony Share, XBox Share, Nintendo Share)
@onready var joypad_button_15_label: Label = $TopCenter/JoypadButton15/Label
@onready var joypad_button_6: TouchScreenButton = $TopCenter/JoypadButton6 ## Joypad Button 6 (Start, Sony Options, XBox Menu, Nintendo Plus)
@onready var joypad_button_6_label: Label = $TopCenter/JoypadButton6/Label
@onready var joypad_button_7: TouchScreenButton = $BottomLeft/JoypadButton7 ## Joypad Button 7 (Left Stick, Sony L3, XBox Left Stick, Nintendo Left Stick)
@onready var joypad_button_7_label: Label = $BottomLeft/JoypadButton7/Label
@onready var joypad_button_8: TouchScreenButton = $BottomRight/JoypadButton8 ## Joypad Button 8 (Right Stick, Sony R3, XBox Right Stick, Nintendo Right Stick)
@onready var joypad_button_8_label: Label = $BottomRight/JoypadButton8/Label
@onready var joypad_button_9: TouchScreenButton = $TopLeft/JoypadButton9 ## Joypad Button 9 (Left Shoulder, Sony L1, XBox L, Nintendo L)
@onready var joypad_button_9_label: Label = $TopLeft/JoypadButton9/Label
@onready var cast_bar: ProgressBar = %CastBar ## Fills while an ability with a cast time is cast.
@onready var cast_label: Label = %CastLabel ## Names the ability being cast on the cast bar.
@onready var boss_bar: VBoxContainer = %BossBar ## Name and health of the boss this player is fighting.
@onready var boss_name_label: Label = %BossName
@onready var boss_health_bar: ProgressBar = %BossHealth
@onready var ammo_label: Label = %AmmoLabel ## Magazine / reserve of the equipped firearm; [Firearm] drives it.
@onready var joypad_button_10: TouchScreenButton = $TopRight/JoypadButton10 ## Joypad Button 10 (Right Shoulder, Sony R1, XBox RB, Nintendo R)
@onready var joypad_button_10_label: Label = $TopRight/JoypadButton10/Label
@onready var joypad_axis_4_plus: TouchScreenButton = $TopLeft/JoypadAxis4Plus ## Joypad Axis 4 + (Left Trigger, Sony L2, XBox LT, Nintendo ZL)
@onready var joypad_axis_4_plus_label: Label = $TopLeft/JoypadAxis4Plus/Label
@onready var joypad_axis_5_plus: TouchScreenButton = $TopRight/JoypadAxis5Plus ## Joypad Axis 5 + (Right Trigger, Sony R2, XBox RT, Nintendo ZR)
@onready var joypad_axis_5_plus_label: Label = $TopRight/JoypadAxis5Plus/Label
@onready var joypad_button_11: TouchScreenButton = $BottomLeft/JoypadButton11 ## Joypad Button 11 (DPad Up)
@onready var joypad_button_11_label: Label = $BottomLeft/JoypadButton11/Label
@onready var joypad_button_12: TouchScreenButton = $BottomLeft/JoypadButton12 ## Joypad Button 12 (DPad Down)
@onready var joypad_button_12_label: Label = $BottomLeft/JoypadButton12/Label
@onready var joypad_button_13: TouchScreenButton = $BottomLeft/JoypadButton13 ## Joypad Button 13 (DPad Left)
@onready var joypad_button_13_label: Label = $BottomLeft/JoypadButton13/Label
@onready var joypad_button_14: TouchScreenButton = $BottomLeft/JoypadButton14 ## Joypad Button 14 (DPad Right)
@onready var joypad_button_14_label: Label = $BottomLeft/JoypadButton14/Label
@onready var key_w: TouchScreenButton = $BottomLeft/KeyW ## Keyboard [W] key
@onready var key_w_label: Label = $BottomLeft/KeyW/Label
@onready var key_a: TouchScreenButton = $BottomLeft/KeyA ## Keyboard [A] key
@onready var key_a_label: Label = $BottomLeft/KeyA/Label
@onready var key_s: TouchScreenButton = $BottomLeft/KeyS ## Keyboard [S] key
@onready var key_s_label: Label = $BottomLeft/KeyS/Label
@onready var key_d: TouchScreenButton = $BottomLeft/KeyD ## Keyboard [D] key
@onready var key_d_label: Label = $BottomLeft/KeyD/Label
@onready var key_i: TouchScreenButton = $BottomLeft/KeyI ## Keyboard [I] key
@onready var key_i_label: Label = $BottomLeft/KeyI/Label
@onready var key_j: TouchScreenButton = $BottomLeft/KeyJ ## Keyboard [J] key
@onready var key_j_label: Label = $BottomLeft/KeyJ/Label
@onready var key_k: TouchScreenButton = $BottomLeft/KeyK ## Keyboard [K] key
@onready var key_k_label: Label = $BottomLeft/KeyK/Label
@onready var key_l: TouchScreenButton = $BottomLeft/KeyL ## Keyboard [L] key
@onready var key_l_label: Label = $BottomLeft/KeyL/Label
@onready var left_joystick: VirtualJoystick = $BottomLeft/LeftJoystick ## Virtual Joystick (introduced in Godot 4.7) for player movement
@onready var left_joystick_label: Label = $BottomLeft/LeftJoystick/Label
@onready var right_joystick: VirtualJoystick = $BottomRight/RightJoystick ## Virtual Joystick (introduced in Godot 4.7) for camera movement
@onready var right_joystick_label: Label = $BottomRight/RightJoystick/Label
@onready var key_up: TouchScreenButton = $BottomRight/KeyUp ## Keyboard [Up] key
@onready var key_up_label: Label = $BottomRight/KeyUp/Label
@onready var key_left: TouchScreenButton = $BottomRight/KeyLeft ## Keyboard [Left] key
@onready var key_left_label: Label = $BottomRight/KeyLeft/Label
@onready var key_down: TouchScreenButton = $BottomRight/KeyDown ## Keyboard [Down] key
@onready var key_down_label: Label = $BottomRight/KeyDown/Label
@onready var key_right: TouchScreenButton = $BottomRight/KeyRight ## Keyboard [Right] key
@onready var key_right_label: Label = $BottomRight/KeyRight/Label

@onready var all_buttons: Array[TouchScreenButton] = [
	joypad_button_0, joypad_button_1, joypad_button_2, joypad_button_3,
	joypad_button_4, joypad_button_15, joypad_button_6, joypad_button_7,
	joypad_button_8, joypad_button_9, joypad_button_10, joypad_axis_4_plus,
	joypad_axis_5_plus, joypad_button_11, joypad_button_12, joypad_button_13,
	joypad_button_14, key_w, key_a, key_s, key_d, key_i, key_j, key_k,
	key_l, key_up, key_left, key_down, key_right,
]
@onready var all_labels: Array[Label] = [
	joypad_button_0_label, joypad_button_1_label, joypad_button_2_label, joypad_button_3_label,
	joypad_button_4_label, joypad_button_15_label, joypad_button_6_label, joypad_button_7_label,
	joypad_button_8_label, joypad_button_9_label, joypad_button_10_label, joypad_axis_4_plus_label,
	joypad_axis_5_plus_label, joypad_button_11_label, joypad_button_12_label, joypad_button_13_label,
	joypad_button_14_label, key_w_label, key_a_label, key_s_label, key_d_label, key_i_label, key_j_label, key_k_label,
	key_l_label, key_up_label, key_left_label, key_down_label, key_right_label,
	left_joystick_label, right_joystick_label,
]
## Buttons whose textures swap per input device, in the order of the [member _vendor_textures] pairs.
@onready var _swappable_buttons: Array[TouchScreenButton] = [
	joypad_button_0, joypad_button_1, joypad_button_2, joypad_button_3, joypad_button_4, joypad_button_15,
	joypad_button_6, joypad_button_7, joypad_button_8, joypad_button_9, joypad_button_10, joypad_axis_4_plus, joypad_axis_5_plus,
]
## Normal/pressed texture pairs per input type, in [member _swappable_buttons] order (touch reuses Microsoft).
@onready var _vendor_textures: Dictionary[InputType, Array] = {
	InputType.KEYBOARD_MOUSE: [
		keyboard_mouse_button_0_normal, keyboard_mouse_button_0_pressed, keyboard_mouse_button_1_normal, keyboard_mouse_button_1_pressed,
		keyboard_mouse_button_2_normal, keyboard_mouse_button_2_pressed, keyboard_mouse_button_3_normal, keyboard_mouse_button_3_pressed,
		keyboard_mouse_button_4_normal, keyboard_mouse_button_4_pressed, keyboard_mouse_button_15_normal, keyboard_mouse_button_15_pressed,
		keyboard_mouse_button_6_normal, keyboard_mouse_button_6_pressed, keyboard_mouse_button_7_normal, keyboard_mouse_button_7_pressed,
		keyboard_mouse_button_8_normal, keyboard_mouse_button_8_pressed, keyboard_mouse_button_9_normal, keyboard_mouse_button_9_pressed,
		keyboard_mouse_button_10_normal, keyboard_mouse_button_10_pressed, keyboard_mouse_axis_4_plus_normal, keyboard_mouse_axis_4_plus_pressed,
		keyboard_mouse_axis_5_plus_normal, keyboard_mouse_axis_5_plus_pressed,
	],
	InputType.MICROSOFT: [
		microsoft_button_0_normal, microsoft_button_0_pressed, microsoft_button_1_normal, microsoft_button_1_pressed,
		microsoft_button_2_normal, microsoft_button_2_pressed, microsoft_button_3_normal, microsoft_button_3_pressed,
		microsoft_button_4_normal, microsoft_button_4_pressed, microsoft_button_15_normal, microsoft_button_15_pressed,
		microsoft_button_6_normal, microsoft_button_6_pressed, microsoft_button_7_normal, microsoft_button_7_pressed,
		microsoft_button_8_normal, microsoft_button_8_pressed, microsoft_button_9_normal, microsoft_button_9_pressed,
		microsoft_button_10_normal, microsoft_button_10_pressed, microsoft_axis_4_plus_normal, microsoft_axis_4_plus_pressed,
		microsoft_axis_5_plus_normal, microsoft_axis_5_plus_pressed,
	],
	InputType.NINTENDO: [
		nintendo_button_0_normal, nintendo_button_0_pressed, nintendo_button_1_normal, nintendo_button_1_pressed,
		nintendo_button_2_normal, nintendo_button_2_pressed, nintendo_button_3_normal, nintendo_button_3_pressed,
		nintendo_button_4_normal, nintendo_button_4_pressed, nintendo_button_15_normal, nintendo_button_15_pressed,
		nintendo_button_6_normal, nintendo_button_6_pressed, nintendo_button_7_normal, nintendo_button_7_pressed,
		nintendo_button_8_normal, nintendo_button_8_pressed, nintendo_button_9_normal, nintendo_button_9_pressed,
		nintendo_button_10_normal, nintendo_button_10_pressed, nintendo_axis_4_plus_normal, nintendo_axis_4_plus_pressed,
		nintendo_axis_5_plus_normal, nintendo_axis_5_plus_pressed,
	],
	InputType.SONY: [
		sony_button_0_normal, sony_button_0_pressed, sony_button_1_normal, sony_button_1_pressed,
		sony_button_2_normal, sony_button_2_pressed, sony_button_3_normal, sony_button_3_pressed,
		sony_button_4_normal, sony_button_4_pressed, sony_button_15_normal, sony_button_15_pressed,
		sony_button_6_normal, sony_button_6_pressed, sony_button_7_normal, sony_button_7_pressed,
		sony_button_8_normal, sony_button_8_pressed, sony_button_9_normal, sony_button_9_pressed,
		sony_button_10_normal, sony_button_10_pressed, sony_axis_4_plus_normal, sony_axis_4_plus_pressed,
		sony_axis_5_plus_normal, sony_axis_5_plus_pressed,
	],
}
## Controls shown only for controller/touch input (the keyboard set is shown instead for keyboard/mouse).
@onready var _joypad_only: Array[CanvasItem] = [joypad_button_11, joypad_button_12, joypad_button_13, joypad_button_14, left_joystick, right_joystick]
@onready var _keyboard_only: Array[CanvasItem] = [key_w, key_a, key_s, key_d, key_i, key_j, key_k, key_l, key_up, key_left, key_down, key_right]

var current_input_type: InputType = InputType.TOUCH:
	set(value):
		if current_input_type != value:
			current_input_type = value
			update_input_ui()
			input_type_changed.emit(value)

var _normal_textures: Dictionary[TouchScreenButton, Texture2D] = {} ## Unpressed texture per button for the current input type.
var _label_texts: Dictionary[Label, String] = {} ## Default label text per label (from the scene).


## Called when the node enters the scene tree for the first time.
func _ready() -> void:
	if player == null and get_parent() is Player:
		player = get_parent() as Player

	set_process(is_multiplayer_authority())
	set_physics_process(is_multiplayer_authority())
	set_process_input(is_multiplayer_authority())

	# Cache the initial normal textures and label texts
	for button: TouchScreenButton in all_buttons:
		_normal_textures[button] = button.texture_normal
	for label: Label in all_labels:
		_label_texts[label] = label.text

	# Register the addon's actions; a project's own bindings are left alone, but the engine's built-in ui_* actions are extended
	for action_name: String in ACTIONS:
		var binding: Dictionary = ACTIONS[action_name]
		if not InputMap.has_action(action_name):
			InputMap.add_action(action_name, binding.get("deadzone", 0.2))
		elif not action_name.begins_with("ui_"):
			continue
		var events: Array[InputEvent] = []
		for key: Key in binding.get("keys", []):
			var key_event: InputEventKey = InputEventKey.new()
			key_event.physical_keycode = key
			events.append(key_event)
		for keycode: Key in binding.get("keycodes", []):
			var key_event: InputEventKey = InputEventKey.new()
			key_event.keycode = keycode
			events.append(key_event)
		for button: JoyButton in binding.get("buttons", []):
			var button_event: InputEventJoypadButton = InputEventJoypadButton.new()
			button_event.button_index = button
			events.append(button_event)
		for axis: Array in binding.get("axes", []):
			var motion_event: InputEventJoypadMotion = InputEventJoypadMotion.new()
			motion_event.axis = axis[0]
			motion_event.axis_value = axis[1]
			events.append(motion_event)
		for mouse_button: MouseButton in binding.get("mouse", []):
			var mouse_event: InputEventMouseButton = InputEventMouseButton.new()
			mouse_event.button_index = mouse_button
			events.append(mouse_event)
		for event: InputEvent in events:
			if not InputMap.action_has_event(action_name, event):
				InputMap.action_add_event(action_name, event)

	update_input_ui()


## Called when there is an input event.
func _input(event: InputEvent) -> void:
	# Detect the input device from the event
	if event is InputEventKey or (event is InputEventMouse and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED):
		current_input_type = InputType.KEYBOARD_MOUSE
	elif event is InputEventJoypadButton or (event is InputEventJoypadMotion and absf((event as InputEventJoypadMotion).axis_value) > input_deadzone):
		var joystick_name: String = Input.get_joy_name(event.device).to_lower()
		# Microsoft [XBox], Nintendo [Switch], or Sony [PlayStation] controller
		if joystick_name.contains("xinput") or joystick_name.contains("standard"):
			current_input_type = InputType.MICROSOFT
		elif joystick_name.contains("nintendo"):
			current_input_type = InputType.NINTENDO
		elif joystick_name.contains("dualsense wireless controller") or joystick_name.contains("ps"):
			current_input_type = InputType.SONY
	elif event is InputEventScreenTouch or event is InputEventScreenDrag:
		current_input_type = InputType.TOUCH

	# Motion events are never button presses; only press/release events update the pressed visuals
	if event is InputEventMouseMotion or event is InputEventScreenDrag:
		return
	for button: TouchScreenButton in all_buttons:
		if button.action.is_empty() or not event.is_action(button.action):
			continue
		if event.is_action_pressed(button.action) and button.texture_pressed:
			button.texture_normal = button.texture_pressed
		elif event.is_action_released(button.action):
			button.texture_normal = _normal_textures[button]


func reset_labels() -> void:
	for label: Label in _label_texts:
		label.text = _label_texts[label]

	if player != null and player.has_firearm_equipped:
		joypad_axis_4_plus_label.text = "Aim"
	var seeker: String = seeker_label_text()
	if seeker != "":
		joypad_button_11_label.text = seeker
		key_i_label.text = seeker
	if player != null and player.abilities != null and player.abilities.active_ability:
		joypad_button_9_label.text = player.abilities.active_ability.display_name


## What Seeker (D-pad Up / I) opens right now: the arrow kinds with a bow out, the ammunition with a gun out, else
## the scene's default label (empty means keep it).
func seeker_label_text() -> String:
	if player == null or player.inventory == null:
		return ""
	if player.has_bow_equipped:
		return "Arrows"
	if player.has_firearm_equipped:
		return "Ammo"
	return ""


func set_labels(label_texts: Dictionary) -> void:
	var final_texts: Dictionary = label_texts.duplicate()
	if left_joystick_label in final_texts and not key_s_label in final_texts:
		final_texts[key_s_label] = final_texts[left_joystick_label]
	if right_joystick_label in final_texts and not key_down_label in final_texts:
		final_texts[key_down_label] = final_texts[right_joystick_label]
	if joypad_button_12_label in final_texts and not key_k_label in final_texts:
		final_texts[key_k_label] = final_texts[joypad_button_12_label]
	if key_k_label in final_texts and not joypad_button_12_label in final_texts:
		final_texts[joypad_button_12_label] = final_texts[key_k_label]
	if joypad_button_11_label in final_texts and not key_i_label in final_texts:
		final_texts[key_i_label] = final_texts[joypad_button_11_label]
	if key_i_label in final_texts and not joypad_button_11_label in final_texts:
		final_texts[joypad_button_11_label] = final_texts[key_i_label]
	if joypad_button_13_label in final_texts and not key_j_label in final_texts:
		final_texts[key_j_label] = final_texts[joypad_button_13_label]
	if key_j_label in final_texts and not joypad_button_13_label in final_texts:
		final_texts[joypad_button_13_label] = final_texts[key_j_label]
	if joypad_button_14_label in final_texts and not key_l_label in final_texts:
		final_texts[key_l_label] = final_texts[joypad_button_14_label]
	if key_l_label in final_texts and not joypad_button_14_label in final_texts:
		final_texts[joypad_button_14_label] = final_texts[key_l_label]

	for label: Label in _label_texts:
		if label in final_texts:
			label.text = final_texts[label]
		# Don't clear joystick labels if they are not explicitly specified
		elif label != left_joystick_label and label != right_joystick_label:
			label.text = ""


## Applies the current input type: device textures on the swappable buttons, keyboard vs joypad visibility, default labels, and held-button visuals.
func update_input_ui() -> void:
	reset_labels()

	var textures: Array = _vendor_textures[InputType.MICROSOFT if current_input_type == InputType.TOUCH else current_input_type]
	for i: int in _swappable_buttons.size():
		_swappable_buttons[i].texture_pressed = textures[i * 2 + 1]
		_normal_textures[_swappable_buttons[i]] = textures[i * 2]

	var is_keyboard: bool = current_input_type == InputType.KEYBOARD_MOUSE
	for item: CanvasItem in _joypad_only:
		item.visible = not is_keyboard
	for item: CanvasItem in _keyboard_only:
		item.visible = is_keyboard

	# Show each button pressed or normal to match the actions currently held
	for button: TouchScreenButton in all_buttons:
		var is_held: bool = not button.action.is_empty() and InputMap.has_action(button.action) and Input.is_action_pressed(button.action)
		button.texture_normal = button.texture_pressed if is_held and button.texture_pressed else _normal_textures[button]


## Shows the boss bar for [param boss_name] at [param ratio] (0-1) health; [Boss] drives these three.
func show_boss(boss_name: String, ratio: float) -> void:
	boss_name_label.text = boss_name
	boss_health_bar.value = ratio
	boss_bar.show()


func update_boss(ratio: float) -> void:
	boss_health_bar.value = ratio


## Shows rounds in the magazine and in reserve while a firearm is equipped.
func set_ammo(rounds: int, reserve: int) -> void:
	ammo_label.text = "%d / %d" % [rounds, reserve]
	ammo_label.show()


func hide_ammo() -> void:
	ammo_label.hide()


## Rumbles the pad for [param seconds] unless the Player is on keyboard/mouse or touch; returns whether it did.
func rumble(weak: float, strong: float, seconds: float) -> bool:
	if current_input_type in [InputType.KEYBOARD_MOUSE, InputType.TOUCH]:
		return false
	Input.start_joy_vibration(0, weak, strong, seconds)
	return true


func hide_boss() -> void:
	boss_bar.hide()
