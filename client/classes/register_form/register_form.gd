class_name RegisterForm
extends VBoxContainer

@onready var _username_field: LineEdit = $Columns/Fields/Username
@onready var _password_field: LineEdit = $Columns/Fields/Password
@onready var _confirm_password_field: LineEdit = $Columns/Fields/ConfirmPassword
@onready var _confirm_button: Button = $Columns/Fields/HBoxContainer/ConfirmButton
@onready var _cancel_button: Button = $Columns/Fields/HBoxContainer/CancelButton
@onready var _color_wheel: ColorWheel = $Columns/ColourColumn/ColorWheel


signal form_submitted(username: String, password: String, confirm_password: String, color: Color)
signal form_cancelled()

func _ready() -> void:
	_confirm_button.pressed.connect(_on_confirm_button_pressed)
	_cancel_button.pressed.connect(_on_cancel_button_pressed)

func _on_confirm_button_pressed() -> void:
	form_submitted.emit(_username_field.text, _password_field.text, _confirm_password_field.text, _color_wheel.color)

func _on_cancel_button_pressed() -> void:
	form_cancelled.emit()
