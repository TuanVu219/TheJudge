extends CharacterBody3D
class_name PlayerCharacter

const Wardrobe = preload("res://scripts/characters/wardrobe.gd")

## A lightweight, reusable cartoon player character.
## Supports modular wardrobe customization: Body Color, Hats, Glasses, Hairstyles, and Outfits.

@onready var display_name_label: Label3D = $DisplayName
@onready var body_mesh: MeshInstance3D = $VisualRoot/Body/Bean
@onready var shirt_mesh: MeshInstance3D = $VisualRoot/Body/Shirt
@onready var animation_player: AnimationPlayer = $AnimationPlayer
@onready var visual_root: Node3D = $VisualRoot
@onready var accessories: Node3D = $VisualRoot/Accessories

var _toon_shader: Shader = preload("res://shaders/toon.gdshader")
var _procedural_initialized := false
var _overalls_straps: Node3D = null


func _ready() -> void:
	_ensure_references()
	_ensure_materials()
	_ensure_accessories_built()
	if animation_player != null and animation_player.has_animation("idle"):
		animation_player.play("idle")


func _ensure_references() -> void:
	if display_name_label == null:
		display_name_label = get_node_or_null("DisplayName") as Label3D
	if visual_root == null:
		visual_root = get_node_or_null("VisualRoot") as Node3D
	if body_mesh == null:
		body_mesh = get_node_or_null("VisualRoot/Body/Bean") as MeshInstance3D
	if shirt_mesh == null:
		shirt_mesh = get_node_or_null("VisualRoot/Body/Shirt") as MeshInstance3D
	if accessories == null:
		accessories = get_node_or_null("VisualRoot/Accessories") as Node3D


func _ensure_materials() -> void:
	_ensure_references()
	if body_mesh != null:
		var shared_body_material := body_mesh.material_override as ShaderMaterial
		if shared_body_material != null:
			body_mesh.material_override = shared_body_material.duplicate()
	if shirt_mesh != null:
		var shared_shirt_material := shirt_mesh.material_override as ShaderMaterial
		if shared_shirt_material != null:
			shirt_mesh.material_override = shared_shirt_material.duplicate()


func set_display_name(value: String) -> void:
	_ensure_references()
	var clean := Wardrobe.clean_name(value)
	if display_name_label != null:
		display_name_label.text = clean


func set_display_name_visible(value: bool) -> void:
	_ensure_references()
	if display_name_label != null:
		display_name_label.visible = value


func set_body_color(color: Color) -> void:
	_ensure_references()
	if body_mesh == null:
		return
	var body_material := body_mesh.material_override as ShaderMaterial
	if body_material == null:
		body_material = ShaderMaterial.new()
		body_material.shader = _toon_shader
		body_mesh.material_override = body_material
	body_material.set_shader_parameter("albedo_color", color)


func set_shirt_color(color: Color) -> void:
	_ensure_references()
	if shirt_mesh == null:
		return
	var shirt_material := shirt_mesh.material_override as ShaderMaterial
	if shirt_material == null:
		shirt_material = ShaderMaterial.new()
		shirt_material.shader = _toon_shader
		shirt_mesh.material_override = shirt_material
	shirt_material.set_shader_parameter("albedo_color", color)


func set_accessory_visible(accessory_name: String, value: bool) -> void:
	_ensure_references()
	_ensure_accessories_built()
	if accessories == null:
		return
	var accessory := accessories.get_node_or_null(accessory_name)
	if accessory != null:
		accessory.visible = value


func hide_all_accessories() -> void:
	_ensure_references()
	_ensure_accessories_built()
	if accessories == null:
		return
	for child in accessories.get_children():
		child.visible = false
	if _overalls_straps != null:
		_overalls_straps.visible = false


## Apply a full modular wardrobe configuration
func apply_wardrobe(skin: Dictionary) -> void:
	_ensure_materials()
	_ensure_accessories_built()
	hide_all_accessories()

	# 1. Body Color
	var color_id := str(skin.get("color", "mint"))
	var color_def := Wardrobe.get_body_color_def(color_id)
	set_body_color(color_def.get("color", Color("#6ee0a7")))

	# 2. Outfit
	var outfit_id := str(skin.get("outfit", "classic"))
	var outfit_def := Wardrobe.get_outfit_def(outfit_id)
	var outfit_color: Color = outfit_def.get("color", Color("#1fa4b8"))
	set_shirt_color(outfit_color)
	if bool(outfit_def.get("is_overalls", false)) and _overalls_straps != null:
		_overalls_straps.visible = true
		_update_overalls_color(outfit_color)

	# 3. Hat
	var hat_id := str(skin.get("hat", "none"))
	match hat_id:
		"tiny_hat": set_accessory_visible("TinyHat", true)
		"feather": set_accessory_visible("Feather", true)
		"party_cone": set_accessory_visible("PartyCone", true)
		"crown": set_accessory_visible("Crown", true)
		"headband": set_accessory_visible("Headband", true)
		"chef_hat": set_accessory_visible("ChefHat", true)

	# 4. Glasses
	var glasses_id := str(skin.get("glasses", "none"))
	match glasses_id:
		"round": set_accessory_visible("TinyGlasses", true)
		"sunglasses": set_accessory_visible("Sunglasses", true)
		"nerd": set_accessory_visible("NerdGlasses", true)
		"monocle": set_accessory_visible("Monocle", true)

	# 5. Hair
	var hair_id := str(skin.get("hair", "bald"))
	match hair_id:
		"sprout": set_accessory_visible("Sprout", true)
		"tuft": set_accessory_visible("Tuft", true)
		"afro": set_accessory_visible("Afro", true)
		"spiky": set_accessory_visible("Spiky", true)


func _update_overalls_color(color: Color) -> void:
	if _overalls_straps == null:
		return
	for strap in _overalls_straps.get_children():
		var mesh_inst := strap as MeshInstance3D
		if mesh_inst != null and mesh_inst.material_override is ShaderMaterial:
			if mesh_inst.name.begins_with("Strap"):
				(mesh_inst.material_override as ShaderMaterial).set_shader_parameter("albedo_color", color)


func _create_toon_mat(color: Color) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = _toon_shader
	mat.set_shader_parameter("albedo_color", color)
	return mat


func _ensure_accessories_built() -> void:
	if _procedural_initialized:
		return
	_ensure_references()
	if accessories == null:
		return

	# Party Cone
	if accessories.get_node_or_null("PartyCone") == null:
		var cone_root := Node3D.new()
		cone_root.name = "PartyCone"
		cone_root.visible = false
		cone_root.position = Vector3(0.05, 1.55, 0.0)
		cone_root.rotation_degrees = Vector3(0, 0, -10)

		var cone_mesh := CylinderMesh.new()
		cone_mesh.top_radius = 0.01
		cone_mesh.bottom_radius = 0.17
		cone_mesh.height = 0.36
		cone_mesh.radial_segments = 16

		var cone_inst := MeshInstance3D.new()
		cone_inst.mesh = cone_mesh
		cone_inst.material_override = _create_toon_mat(Color("#f39c12"))
		cone_inst.position = Vector3(0, 0.18, 0)
		cone_root.add_child(cone_inst)

		var pom := SphereMesh.new()
		pom.radius = 0.05
		pom.height = 0.1
		var pom_inst := MeshInstance3D.new()
		pom_inst.mesh = pom
		pom_inst.material_override = _create_toon_mat(Color("#ffffff"))
		pom_inst.position = Vector3(0, 0.36, 0)
		cone_root.add_child(pom_inst)
		accessories.add_child(cone_root)

	# Crown
	if accessories.get_node_or_null("Crown") == null:
		var crown_root := Node3D.new()
		crown_root.name = "Crown"
		crown_root.visible = false
		crown_root.position = Vector3(0, 1.48, 0)

		var base_ring := CylinderMesh.new()
		base_ring.top_radius = 0.22
		base_ring.bottom_radius = 0.20
		base_ring.height = 0.08
		base_ring.radial_segments = 16
		var base_inst := MeshInstance3D.new()
		base_inst.mesh = base_ring
		base_inst.material_override = _create_toon_mat(Color("#f1c40f"))
		crown_root.add_child(base_inst)

		for i in range(4):
			var angle := float(i) * PI * 0.5
			var spike := CylinderMesh.new()
			spike.top_radius = 0.01
			spike.bottom_radius = 0.05
			spike.height = 0.12
			var spike_inst := MeshInstance3D.new()
			spike_inst.mesh = spike
			spike_inst.material_override = _create_toon_mat(Color("#f1c40f"))
			spike_inst.position = Vector3(sin(angle) * 0.19, 0.08, cos(angle) * 0.19)
			crown_root.add_child(spike_inst)
		accessories.add_child(crown_root)

	# Headband
	if accessories.get_node_or_null("Headband") == null:
		var hb_root := Node3D.new()
		hb_root.name = "Headband"
		hb_root.visible = false
		hb_root.position = Vector3(0, 1.34, 0)

		var band := TorusMesh.new()
		band.inner_radius = 0.49
		band.outer_radius = 0.54
		band.rings = 24
		var band_inst := MeshInstance3D.new()
		band_inst.mesh = band
		band_inst.scale = Vector3(1.0, 0.45, 1.0)
		band_inst.material_override = _create_toon_mat(Color("#e74c3c"))
		hb_root.add_child(band_inst)
		accessories.add_child(hb_root)

	# Chef Hat
	if accessories.get_node_or_null("ChefHat") == null:
		var chef_root := Node3D.new()
		chef_root.name = "ChefHat"
		chef_root.visible = false
		chef_root.position = Vector3(0, 1.48, 0)

		var cuff := CylinderMesh.new()
		cuff.top_radius = 0.22
		cuff.bottom_radius = 0.22
		cuff.height = 0.12
		var cuff_inst := MeshInstance3D.new()
		cuff_inst.mesh = cuff
		cuff_inst.material_override = _create_toon_mat(Color("#f5f6fa"))
		chef_root.add_child(cuff_inst)

		var puff := SphereMesh.new()
		puff.radius = 0.32
		puff.height = 0.32
		var puff_inst := MeshInstance3D.new()
		puff_inst.mesh = puff
		puff_inst.scale = Vector3(1.0, 0.85, 1.0)
		puff_inst.position = Vector3(0, 0.18, 0)
		puff_inst.material_override = _create_toon_mat(Color("#ffffff"))
		chef_root.add_child(puff_inst)
		accessories.add_child(chef_root)

	# Sunglasses
	if accessories.get_node_or_null("Sunglasses") == null:
		var sg_root := Node3D.new()
		sg_root.name = "Sunglasses"
		sg_root.visible = false
		sg_root.position = Vector3(0, 1.20, 0.53)

		var lens := BoxMesh.new()
		lens.size = Vector3(0.24, 0.14, 0.05)
		var sg_mat := _create_toon_mat(Color("#1e272e"))

		var left_lens := MeshInstance3D.new()
		left_lens.mesh = lens
		left_lens.position = Vector3(-0.16, 0, 0)
		left_lens.material_override = sg_mat
		sg_root.add_child(left_lens)

		var right_lens := MeshInstance3D.new()
		right_lens.mesh = lens
		right_lens.position = Vector3(0.16, 0, 0)
		right_lens.material_override = sg_mat
		sg_root.add_child(right_lens)

		var bridge := BoxMesh.new()
		bridge.size = Vector3(0.12, 0.04, 0.04)
		var bridge_inst := MeshInstance3D.new()
		bridge_inst.mesh = bridge
		bridge_inst.material_override = sg_mat
		sg_root.add_child(bridge_inst)
		accessories.add_child(sg_root)

	# Nerd Glasses
	if accessories.get_node_or_null("NerdGlasses") == null:
		var nerd_root := Node3D.new()
		nerd_root.name = "NerdGlasses"
		nerd_root.visible = false
		nerd_root.position = Vector3(0, 1.20, 0.53)

		var frame := TorusMesh.new()
		frame.inner_radius = 0.10
		frame.outer_radius = 0.16
		var nerd_mat := _create_toon_mat(Color("#2c3e50"))

		var lf := MeshInstance3D.new()
		lf.mesh = frame
		lf.position = Vector3(-0.16, 0, 0)
		lf.material_override = nerd_mat
		nerd_root.add_child(lf)

		var rf := MeshInstance3D.new()
		rf.mesh = frame
		rf.position = Vector3(0.16, 0, 0)
		rf.material_override = nerd_mat
		nerd_root.add_child(rf)

		var tape := BoxMesh.new()
		tape.size = Vector3(0.08, 0.08, 0.05)
		var tape_inst := MeshInstance3D.new()
		tape_inst.mesh = tape
		tape_inst.material_override = _create_toon_mat(Color("#ecf0f1"))
		nerd_root.add_child(tape_inst)
		accessories.add_child(nerd_root)

	# Monocle
	if accessories.get_node_or_null("Monocle") == null:
		var mono_root := Node3D.new()
		mono_root.name = "Monocle"
		mono_root.visible = false
		mono_root.position = Vector3(0.16, 1.21, 0.54)

		var rim := TorusMesh.new()
		rim.inner_radius = 0.11
		rim.outer_radius = 0.15
		var rim_inst := MeshInstance3D.new()
		rim_inst.mesh = rim
		rim_inst.material_override = _create_toon_mat(Color("#f1c40f"))
		mono_root.add_child(rim_inst)
		accessories.add_child(mono_root)

	# Sprout Hair
	if accessories.get_node_or_null("Sprout") == null:
		var sprout_root := Node3D.new()
		sprout_root.name = "Sprout"
		sprout_root.visible = false
		sprout_root.position = Vector3(0, 1.50, 0)

		var stem := CylinderMesh.new()
		stem.top_radius = 0.02
		stem.bottom_radius = 0.03
		stem.height = 0.16
		var stem_inst := MeshInstance3D.new()
		stem_inst.mesh = stem
		stem_inst.position = Vector3(0, 0.08, 0)
		stem_inst.material_override = _create_toon_mat(Color("#2ecc71"))
		sprout_root.add_child(stem_inst)

		var leaf := SphereMesh.new()
		leaf.radius = 0.08
		leaf.height = 0.04
		var leaf_mat := _create_toon_mat(Color("#27ae60"))

		var l1 := MeshInstance3D.new()
		l1.mesh = leaf
		l1.position = Vector3(-0.07, 0.16, 0)
		l1.rotation_degrees = Vector3(0, 0, -25)
		l1.material_override = leaf_mat
		sprout_root.add_child(l1)

		var l2 := MeshInstance3D.new()
		l2.mesh = leaf
		l2.position = Vector3(0.07, 0.16, 0)
		l2.rotation_degrees = Vector3(0, 0, 25)
		l2.material_override = leaf_mat
		sprout_root.add_child(l2)
		accessories.add_child(sprout_root)

	# Tuft Hair
	if accessories.get_node_or_null("Tuft") == null:
		var tuft_root := Node3D.new()
		tuft_root.name = "Tuft"
		tuft_root.visible = false
		tuft_root.position = Vector3(0, 1.50, 0)

		var puff := SphereMesh.new()
		puff.radius = 0.12
		puff.height = 0.16
		var puff_inst := MeshInstance3D.new()
		puff_inst.mesh = puff
		puff_inst.position = Vector3(0, 0.08, 0)
		puff_inst.scale = Vector3(0.8, 1.4, 0.8)
		puff_inst.material_override = _create_toon_mat(Color("#4a3728"))
		tuft_root.add_child(puff_inst)
		accessories.add_child(tuft_root)

	# Afro Hair
	if accessories.get_node_or_null("Afro") == null:
		var afro_root := Node3D.new()
		afro_root.name = "Afro"
		afro_root.visible = false
		afro_root.position = Vector3(0, 1.52, -0.05)

		var puff := SphereMesh.new()
		puff.radius = 0.38
		puff.height = 0.38
		var puff_inst := MeshInstance3D.new()
		puff_inst.mesh = puff
		puff_inst.material_override = _create_toon_mat(Color("#2c1b10"))
		afro_root.add_child(puff_inst)
		accessories.add_child(afro_root)

	# Spiky Hair
	if accessories.get_node_or_null("Spiky") == null:
		var spiky_root := Node3D.new()
		spiky_root.name = "Spiky"
		spiky_root.visible = false
		spiky_root.position = Vector3(0, 1.48, 0)

		var spike_mat := _create_toon_mat(Color("#f39c12"))
		for idx in range(3):
			var sp := CylinderMesh.new()
			sp.top_radius = 0.01
			sp.bottom_radius = 0.08
			sp.height = 0.22
			var sp_inst := MeshInstance3D.new()
			sp_inst.mesh = sp
			sp_inst.material_override = spike_mat
			var offset_x := (float(idx) - 1.0) * 0.14
			sp_inst.position = Vector3(offset_x, 0.12, 0)
			sp_inst.rotation_degrees = Vector3(0, 0, (float(idx) - 1.0) * -18.0)
			spiky_root.add_child(sp_inst)
		accessories.add_child(spiky_root)

	# Overalls Straps (Parented to VisualRoot/Body)
	var body_node := visual_root.get_node_or_null("Body") as Node3D
	if body_node != null and body_node.get_node_or_null("OverallsStraps") == null:
		_overalls_straps = Node3D.new()
		_overalls_straps.name = "OverallsStraps"
		_overalls_straps.visible = false

		var strap_mesh := BoxMesh.new()
		strap_mesh.size = Vector3(0.09, 0.55, 0.04)
		var strap_mat := _create_toon_mat(Color("#28528c"))

		var left_strap := MeshInstance3D.new()
		left_strap.name = "StrapLeft"
		left_strap.mesh = strap_mesh
		left_strap.position = Vector3(-0.24, 0.62, 0.49)
		left_strap.material_override = strap_mat
		_overalls_straps.add_child(left_strap)

		var right_strap := MeshInstance3D.new()
		right_strap.name = "StrapRight"
		right_strap.mesh = strap_mesh
		right_strap.position = Vector3(0.24, 0.62, 0.49)
		right_strap.material_override = strap_mat.duplicate()
		_overalls_straps.add_child(right_strap)

		# 2 cute yellow button accents
		var btn_mesh := SphereMesh.new()
		btn_mesh.radius = 0.035
		btn_mesh.height = 0.05
		var btn_mat := _create_toon_mat(Color("#f1c40f"))

		var lb := MeshInstance3D.new()
		lb.mesh = btn_mesh
		lb.position = Vector3(-0.24, 0.42, 0.52)
		lb.material_override = btn_mat
		_overalls_straps.add_child(lb)

		var rb := MeshInstance3D.new()
		rb.mesh = btn_mesh
		rb.position = Vector3(0.24, 0.42, 0.52)
		rb.material_override = btn_mat
		_overalls_straps.add_child(rb)

		body_node.add_child(_overalls_straps)

	_procedural_initialized = true
