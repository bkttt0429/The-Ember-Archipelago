class_name ResourceNode
extends Resource

## 資源節點
## 代表地圖上的一個可佔領區域，會產出特定資源。

@export var node_name: String = "Unnamed Node"
@export var resource_type: String = "none" # e.g., "coal", "crystals", "food"
@export var production_rate: float = 1.0   # 單位時間產出量
@export var strategic_value: float = 1.0   # 戰略價值 (影響 AI 搶奪意願)

# 當前擁有者 (由 FactionData 管理，這裡作為反向參考或標記)
# 注意：為了避免循環引用問題，這裡可以不強型別為 FactionData，或者僅在邏輯中處理
var current_owner_name: String = ""
