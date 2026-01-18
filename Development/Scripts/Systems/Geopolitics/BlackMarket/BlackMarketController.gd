class_name BlackMarketController
extends Node

## 黑市與走私 (MVP)

signal illicit_trade_triggered(faction: FactionData, deal: BlackMarketDeal)

@export var tick_interval: float = 10.0

var _active_deals: Array[BlackMarketDeal] = []
var _accumulator: float = 0.0

func add_deal(deal: BlackMarketDeal) -> void:
	if deal == null:
		return
	_active_deals.append(deal)

func _process(delta: float) -> void:
	_accumulator += delta
	if _accumulator < tick_interval:
		return
	_accumulator -= tick_interval
	_tick()

func _tick() -> void:
	if _active_deals.is_empty():
		return
	var deal = _active_deals.pop_front()
	var faction = deal.get_meta("faction", null)
	if faction != null:
		emit_signal("illicit_trade_triggered", faction, deal)
