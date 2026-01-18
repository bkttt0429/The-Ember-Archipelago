class_name LogisticsController
extends Node

## 物流與補給線 (MVP)

signal resource_arrived(route: TradeRouteData, cargo_amount: float)

@export var tick_interval: float = 1.0

var _convoys: Array[ConvoyData] = []
var _accumulator: float = 0.0

func dispatch_convoy(route: TradeRouteData, cargo_amount: float, escort_level: float = 0.0) -> ConvoyData:
	var convoy = ConvoyData.new()
	convoy.route = route
	convoy.cargo_amount = cargo_amount
	convoy.escort_level = escort_level
	convoy.eta = route.travel_time
	_convoys.append(convoy)
	return convoy

func _process(delta: float) -> void:
	_accumulator += delta
	if _accumulator < tick_interval:
		return
	_accumulator -= tick_interval
	_tick()

func _tick() -> void:
	var arrived: Array[ConvoyData] = []
	for convoy in _convoys:
		convoy.eta -= tick_interval
		if convoy.eta <= 0.0:
			arrived.append(convoy)
	
	for convoy in arrived:
		_convoys.erase(convoy)
		emit_signal("resource_arrived", convoy.route, convoy.cargo_amount)
