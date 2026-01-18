extends RefCounted
class_name PlayerMath

static func clamp01(value: float) -> float:
    return clamp(value, 0.0, 1.0)

static func safe_normalize(vec: Vector3) -> Vector3:
    return vec.normalized() if vec.length() > 0.0001 else Vector3.ZERO
