class_name TradeRouteData
extends Resource

## 物流路線資料

@export var route_id: String = ""
@export var from_faction: FactionData
@export var to_faction: FactionData
@export var resource_type: String = "none"
@export var risk: float = 0.1
@export var travel_time: float = 5.0
