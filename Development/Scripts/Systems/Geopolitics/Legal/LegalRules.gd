class_name LegalRules
extends Node

## 法律判定工具 (MVP)

func is_trade_allowed(status: LegalStatus, has_license: bool) -> bool:
	if status == null:
		return true
	if status.embargo or status.blockade:
		return false
	if status.license_required:
		return has_license
	return true
