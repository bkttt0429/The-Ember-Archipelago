class_name MultiLayerBlackboard
extends Node

## 多層黑板 (MVP)

signal layer_updated(scope: String, layer: BlackboardLayer)

var _layers: Dictionary = {}

func register_layer(layer: BlackboardLayer) -> void:
	if layer == null:
		return
	_layers[layer.scope] = layer

func get_layer(scope: String) -> BlackboardLayer:
	return _layers.get(scope, null)

func update_value(scope: String, key: String, value) -> void:
	if not _layers.has(scope):
		return
	_layers[scope].data[key] = value
	layer_updated.emit(scope, _layers[scope])
