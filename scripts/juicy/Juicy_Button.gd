class_name JuicyButton
extends Button

## ===================== 果汁参数配置 =====================
@export_group("果汁效果配置")
## 果汁溅射的颜色（默认鲜橙汁色，可调成草莓红、青柠绿等）
@export var juice_color: Color = Color(1.0, 0.55, 0.0, 1.0)
## 悬停时整体放大比例
@export var hover_scale: Vector2 = Vector2(1.08, 1.08)
## 溅射水滴数量
@export var droplet_count: int = 14
## 是否启用点击时的爆汁效果
@export var juice_on_click: bool = true

# 内部引用与动画变量
var _scale_tween: Tween
var _rot_tween: Tween
var _particles: CPUParticles2D


func _ready() -> void:
	# 1. 自动校准轴心点到按钮中心（非常关键，否则缩放会以左上角为中心拉伸）
	_update_pivot()
	resized.connect(_update_pivot)

	# 2. 绑定鼠标进出及点击信号
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	button_down.connect(_on_button_down)
	button_up.connect(_on_button_up)

	# 3. 动态构建果汁粒子发射器（无需美术资源）
	_setup_particles()


func _update_pivot() -> void:
	pivot_offset = size / 2.0


# -------------------------------------------------------------
# 核心果汁动画逻辑
# -------------------------------------------------------------
func _on_mouse_entered() -> void:
	_kill_tweens()

	# 1. Q弹挤压拉伸链：先压扁蓄力 -> 纵向弹高拉伸 -> 来回震荡回弹到悬停大小
	_scale_tween = create_tween()
	_scale_tween.tween_property(self, "scale", Vector2(1.22, 0.78), 0.08)\
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_scale_tween.tween_property(self, "scale", Vector2(0.92, 1.18), 0.10)\
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_scale_tween.tween_property(self, "scale", Vector2(1.10, 0.96), 0.08)\
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	_scale_tween.tween_property(self, "scale", hover_scale, 0.12)\
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	# 2. 俏皮的微摆晃动
	_rot_tween = create_tween()
	var random_tilt = randf_range(3.0, 6.0) * (1.0 if randf() > 0.5 else -1.0)
	_rot_tween.tween_property(self, "rotation_degrees", random_tilt, 0.08)\
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_rot_tween.tween_property(self, "rotation_degrees", -random_tilt * 0.5, 0.10)\
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	_rot_tween.tween_property(self, "rotation_degrees", 0.0, 0.12)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

	# 3. 蹦出果汁水滴
	_splash_juice(1.0)


func _on_mouse_exited() -> void:
	_kill_tweens()

	# 鼠标移出时带有弹簧阻尼的恢复原状
	_scale_tween = create_tween().set_parallel(true)
	_scale_tween.tween_property(self, "scale", Vector2.ONE, 0.25)\
		.set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	_scale_tween.tween_property(self, "rotation_degrees", 0.0, 0.15)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


func _on_button_down() -> void:
	_kill_tweens()
	# 按下时强力挤压变扁
	_scale_tween = create_tween()
	_scale_tween.tween_property(self, "scale", Vector2(0.90, 0.85), 0.05)\
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


func _on_button_up() -> void:
	_kill_tweens()
	# 抬起回弹
	_scale_tween = create_tween()
	_scale_tween.tween_property(self, "scale", hover_scale, 0.15)\
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	if juice_on_click:
		_splash_juice(1.4) # 点击时爆出更多更大的果汁


func _kill_tweens() -> void:
	if _scale_tween and _scale_tween.is_valid():
		_scale_tween.kill()
	if _rot_tween and _rot_tween.is_valid():
		_rot_tween.kill()


# -------------------------------------------------------------
# 纯代码动态构建果汁粒子（无需导入任何水滴贴图）
# -------------------------------------------------------------
func _setup_particles() -> void:
	_particles = CPUParticles2D.new()
	_particles.emitting = false
	_particles.one_shot = true
	_particles.explosiveness = 0.95
	_particles.amount = droplet_count
	_particles.lifetime = 0.45
	_particles.position = size / 2.0
	_particles.spread = 180.0
	_particles.gravity = Vector2(0, 480) # 果汁受重力稍往下落
	_particles.initial_velocity_min = 120.0
	_particles.initial_velocity_max = 220.0
	_particles.scale_amount_min = 0.8
	_particles.scale_amount_max = 1.6
	_particles.color = juice_color
	
	# 代码动态烘焙一张小圆水滴贴图
	_particles.texture = _create_droplet_texture(5)
	
	add_child(_particles)
	# 保证粒子在按钮下方或上方不被剪裁
	_particles.top_level = false
	_particles.show_behind_parent = false


func _splash_juice(scale_factor: float = 1.0) -> void:
	if not _particles:
		return
	_particles.position = size / 2.0
	_particles.amount = int(droplet_count * scale_factor)
	_particles.initial_velocity_min = 120.0 * scale_factor
	_particles.initial_velocity_max = 220.0 * scale_factor
	_particles.restart()
	_particles.emitting = true


## 动态生成一张圆形纯白像素贴图作为水滴基础
func _create_droplet_texture(radius: int) -> ImageTexture:
	var img = Image.create(radius * 2, radius * 2, false, Image.FORMAT_RGBA8)
	var center = Vector2(radius, radius)
	for x in range(radius * 2):
		for y in range(radius * 2):
			if Vector2(x + 0.5, y + 0.5).distance_to(center) <= radius:
				img.set_pixel(x, y, Color.WHITE)
	return ImageTexture.create_from_image(img)
