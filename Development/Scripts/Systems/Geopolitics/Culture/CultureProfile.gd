class_name CultureProfile
extends Resource

## 文化距離與偏見資料

@export var honor: float = 0.5
@export var chaos: float = 0.5
@export var xenophobia: float = 0.5

func distance_to(other: CultureProfile) -> float:
	if other == null:
		return 1.0
	var delta_honor = honor - other.honor
	var delta_chaos = chaos - other.chaos
	var delta_xeno = xenophobia - other.xenophobia
	return clamp(sqrt(delta_honor * delta_honor + delta_chaos * delta_chaos + delta_xeno * delta_xeno), 0.0, 1.732)
