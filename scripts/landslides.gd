class_name Landslides
extends Node3D
## What a stripped hillside does in the rain. The trees felled on the map are counted per CELL m
## square; where enough of a slope's woods are gone, heavy rain can bring it down: a tongue of mud
## and stones slides off down the fall line, leaving the ground it ran over churned to deep mud
## (WorldTerrain.churn: carts sink in it), knocking pieces off any building in its way and over
## anyone standing there. A slope slides once; grow its trees back (an Ormancı's saplings) and it
## holds again.

signal message(text: String, kind: String)

const CELL := 48.0
const MIN_FELLED := 6 ## trees down in a square before its slope can go
const MIN_SLOPE := 0.17 ## rise over run

var village: Village
var terrain: WorldTerrain
var props: WorldProps

var _t := 0.0
var _slid := {} ## Vector2i square -> true: it's gone once


func _process(dt: float) -> void:
	_t += dt
	if _t < 6.0:
		return
	var t := _t
	_t = 0.0
	var rain := Weather.rain_now
	if rain < 0.5:
		return
	var counts := felled_squares()
	for sq: Vector2i in counts:
		var n: int = counts[sq].size()
		if n < MIN_FELLED:
			if n < 3:
				_slid.erase(sq) # (grown back: it holds again, and could go again)
			continue
		if _slid.has(sq):
			continue
		var c := (sq * 1.0 + Vector2(0.5, 0.5)) * CELL
		var g := _gradient(c.x, c.y, 12.0)
		var slope := g.length()
		if slope < MIN_SLOPE:
			continue
		var chance := (n - MIN_FELLED + 1) * 0.006 * (slope - MIN_SLOPE + 0.05) * 10.0 * rain * t / 6.0
		if randf() < chance:
			_slid[sq] = true
			var top := Vector3.ZERO
			for p: Vector3 in counts[sq]:
				top += p
			slide(top / counts[sq].size())


## The felled trees by square: Vector2i -> Array of where each stood.
func felled_squares() -> Dictionary:
	var out := {}
	for i: int in RutStore.cut:
		if i >= props._xf.size() or str(props._models[props._kind[i]].kind) != "tree":
			continue
		var o: Vector3 = props._xf[i].origin
		var sq := Vector2i(floori(o.x / CELL), floori(o.z / CELL))
		if not out.has(sq):
			out[sq] = []
		(out[sq] as Array).append(o)
	return out


## How dangerous a square is now, 0..1 (for the card / hints): its felled trees and its slope.
func risk_at(p: Vector3) -> float:
	var sq := Vector2i(floori(p.x / CELL), floori(p.z / CELL))
	if _slid.has(sq):
		return 0.0
	var n: int = (felled_squares().get(sq, []) as Array).size()
	var g := _gradient((sq.x + 0.5) * CELL, (sq.y + 0.5) * CELL, 12.0)
	return clampf(float(n) / (MIN_FELLED * 2.0), 0.0, 1.0) * clampf((g.length() - MIN_SLOPE * 0.6) * 6.0, 0.0, 1.0)


## Downhill, as rise over run (x, z).
func _gradient(x: float, z: float, e: float) -> Vector2:
	var hx := (terrain.height_at(x + e, z) - terrain.height_at(x - e, z)) / (2.0 * e)
	var hz := (terrain.height_at(x, z + e) - terrain.height_at(x, z - e)) / (2.0 * e)
	return -Vector2(hx, hz)


## The slope goes, from `top` down the fall line.
func slide(top: Vector3) -> void:
	var path: Array[Vector3] = []
	var p := Vector2(top.x, top.z)
	for k in 30:
		var g := _gradient(p.x, p.y, 3.0)
		if g.length() < 0.05 and k > 4:
			break
		path.append(Vector3(p.x, terrain.height_at(p.x, p.y), p.y))
		p += g.normalized() * 2.5
	if path.size() < 3:
		return
	var dir := (path[path.size() - 1] - path[0])
	dir.y = 0.0
	dir = dir.normalized()
	var side := Vector3(-dir.z, 0, dir.x)
	# Mud where it ran, wide at the top and narrowing.
	for k in path.size():
		var w := lerpf(7.0, 3.5, float(k) / path.size())
		var s := -w
		while s <= w:
			terrain.churn(path[k] + side * s, 1.0)
			s += 1.5
	# The tongue itself: lumps of mud and stones let go at the top.
	var mud := StandardMaterial3D.new()
	mud.albedo_color = Color(0.2, 0.14, 0.09)
	mud.roughness = 1.0
	for k in 22:
		var rb := RigidBody3D.new()
		rb.collision_layer = 4
		rb.collision_mask = 1 | 2 | 4
		var r := randf_range(0.35, 0.9)
		var mi := MeshInstance3D.new()
		var cs := CollisionShape3D.new()
		if k % 3 == 0:
			var bm := BoxMesh.new()
			bm.size = Vector3(r, r * 0.8, r * 1.1)
			mi.mesh = bm
			mi.material_override = Building.material("stone")
			var bs := BoxShape3D.new()
			bs.size = bm.size
			cs.shape = bs
		else:
			var sm := SphereMesh.new()
			sm.radius = r
			sm.height = r * 1.4
			sm.radial_segments = 8
			sm.rings = 4
			mi.mesh = sm
			mi.material_override = mud
			var ss := SphereShape3D.new()
			ss.radius = r * 0.7
			cs.shape = ss
		rb.add_child(mi)
		rb.add_child(cs)
		rb.mass = r * r * r * 1800.0
		add_child(rb)
		var at := path[mini(k % 4, path.size() - 1)] + side * randf_range(-6.0, 6.0) + Vector3.UP * (1.0 + r)
		rb.global_position = at
		rb.linear_velocity = dir * randf_range(5.0, 9.0) + Vector3.UP * randf_range(0.0, 2.0)
		var tw := rb.create_tween()
		tw.tween_interval(randf_range(35.0, 50.0))
		tw.tween_callback(rb.set.bind("freeze", true))
		tw.tween_property(rb, "position:y", at.y - 3.0, 8.0)
		tw.tween_callback(rb.queue_free)
	# What stood in its way.
	var hit_names: Array[String] = []
	for b in village.buildings:
		if b.state == "gone":
			continue
		for q in path:
			if Vector2(q.x - b.global_position.x, q.z - b.global_position.z).length() < b.radius + 5.0:
				b.struck(dir * 5.0, 0.35)
				if b.crop:
					b.crop._fallow()
					b.crop._draw()
				hit_names.append(b.display_name())
				break
	for v in village.villagers.duplicate():
		if v.sleeping or v.dead:
			continue
		for q in path:
			if Vector2(q.x - v.position.x, q.z - v.position.z).length() < 5.0:
				v.hurt(40.0)
				break
	var where := Raids._compass(path[0] - (village.stores()[0].global_position if not village.stores().is_empty() else Vector3.ZERO))
	var text := "Toprak kayması! Çıplak bırakılan yamaç yağmurda kaydı (%s)" % where
	if not hit_names.is_empty():
		text += ": " + ", ".join(hit_names) + " zarar gördü"
	message.emit(text, "bad")
