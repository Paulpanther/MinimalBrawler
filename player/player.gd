extends KinematicBody2D
class_name Player

const spawn = Vector2(500, 250)

var id
var color: Color setget set_color
var health = 1.0

signal health_changed(new_health)

func _ready():
	rset_config("position", MultiplayerAPI.RPC_MODE_REMOTESYNC)
	set_process(true)
	randomize()
	position = spawn
	
	
	# pick our color, even though this will be called on all clients, everyone
	# else's random picks will be overriden by the first sync_state from the master
	set_color(Color.from_hsv(randf(), 1, 1))

func get_sync_state():
	# place all synced properties in here
	var properties = ['color', 'health']
	
	var state = {}
	for p in properties:
		state[p] = get(p)
	return state

func _process(delta):
	if is_network_master():
		if Input.is_action_just_pressed("ui_accept"):
			rpc("spawn_box", position)
		if Input.is_mouse_button_pressed(BUTTON_LEFT):
			var direction = -(get_viewport().size / 2 - get_viewport().get_mouse_position()).normalized()
			rpc("spawn_projectile", position, direction, Uuid.v4())
		
		do_movement(delta)

const gravity_acceleration = 2000
const max_speed = 1000
const speed = 350
const air_acceleration = 200
const wall_jump_speed = 200
const wall_sliding_speed = 150
const jump_power = -700

var velocity = Vector2(0, 0)
var jump_allowed = false
var want_to_jump = false
var dropping = false

var time_since_contact = 0
const jump_grace_period_in_seconds = 0.1

enum Move {
	LEFT,
	RIGHT,
	DROP,
	NOT
}

func do_movement(delta):
	time_since_contact += delta
	jump_allowed = false
#	
	var move = Move.NOT
	if Input.is_action_pressed("action_left"):
		move = Move.LEFT
	if Input.is_action_pressed("action_right"):
		move = Move.RIGHT
	if Input.is_action_pressed("action_left") && Input.is_action_pressed("action_right"):
		move = Move.NOT
	if Input.is_action_just_pressed("action_down"):
		move = Move.DROP
	
	var jump = Input.is_action_just_pressed("action_jump")
	want_to_jump = want_to_jump || jump
	
	if move == Move.LEFT && !dropping:
		if is_on_floor():
			velocity.x = min(velocity.x, -speed)
		else:
			velocity.x = min(0, velocity.x - air_acceleration * delta)
	elif move == Move.RIGHT && !dropping:
		if is_on_floor():
			velocity.x = max(velocity.x, speed)
		else:
			velocity.x = max(0, velocity.x + air_acceleration * delta)
	elif move == Move.NOT:
		if is_on_floor():
			velocity.x = 0
	elif move == Move.DROP && !is_on_floor():
		velocity.x = 0
		velocity.y -= jump_power
		dropping = true
	
	if is_on_floor():
		velocity.y = 0
		time_since_contact = 0
		dropping = false
		if abs(velocity.x) > speed:
			var slowing = (abs(velocity.x) - speed) * 2 * delta
			print(velocity.x, " ", speed, " ", slowing)
			velocity.x -= slowing
	else:
		# gravity
		velocity.y += gravity_acceleration * delta
	
	if time_since_contact < jump_grace_period_in_seconds:
		jump_allowed = true
	
	if is_on_ceiling():
		velocity.y = max(0, velocity.y)
	
	if is_on_wall():
		time_since_contact = 0
		if !dropping:
			velocity.y = wall_sliding_speed
			if jump:
				var side = get_colliding_wall()
				if side == Wall.LEFT:
					velocity.x = wall_jump_speed
					print("left wall -> ", velocity)
				else:
					velocity.x = -wall_jump_speed
					print("right wall -> ", velocity)
				velocity.y += jump_power
	elif want_to_jump && jump_allowed:
		velocity.y += jump_power
		want_to_jump = false
		time_since_contact = jump_grace_period_in_seconds
	
	$Camera2D/is_jump_allowed.color = Color.red if jump_allowed else Color.white
	$Camera2D/is_drop_allowed.color = Color.red if dropping else Color.white
	$Camera2D/is_touching.color = Color.red if time_since_contact < jump_grace_period_in_seconds else Color.white
	
	if velocity.length() > max_speed:
		velocity = velocity.normalized() * max_speed
	
	move_and_slide(velocity, Vector2(0, -1))
	rset_unreliable("position", position)

enum Wall {
	LEFT,
	RIGHT
}

func get_colliding_wall():
	for i in range(get_slide_count()):
		var collision = get_slide_collision(i)
		if collision.normal.x > 0:
			return Wall.LEFT
		elif collision.normal.x < 0:
			return Wall.RIGHT

func set_color(_color: Color):
	color = _color
	$sprite.modulate = color

remotesync func spawn_projectile(position, direction, name):
	var projectile = preload("res://examples/physics_projectile/physics_projectile.tscn").instance()
	projectile.set_network_master(1)
	projectile.name = name
	projectile.position = position
	projectile.direction = direction
	projectile.owned_by = self
	get_parent().add_child(projectile)
	return projectile

remotesync func spawn_box(position):
	var box = preload("res://examples/block/block.tscn").instance()
	box.position = position
	get_parent().add_child(box)
	
remotesync func hit(element: Node):
	print("health loss")
	if element.is_in_group("projectiles"):
		health -= element.get_damage()
		emit_signal("health_changed", health)
		element.queue_free()
		if health <= 0:
			pass
			
remotesync func die_and_respawn(player: Player):
	if (player == self):
		print("Player died")
		health = 1.0
		position = spawn
		velocity = Vector2(0, 0)
		rset_unreliable("position", position)

remotesync func kill():
	hide()
