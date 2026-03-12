"""
Mixamo 動畫批量下載工具
========================
使用 Mixamo 非官方 API 批量下載 FBX 動畫。

使用方法:
1. 用瀏覽器登入 https://www.mixamo.com
2. 開 DevTools (F12) → Network → 找任意 API 請求 → 複製 Cookie 中的 Bearer token
3. 執行: python mixamo_downloader.py --token "YOUR_TOKEN" --query "walk"

需求: pip install requests
"""

import requests
import json
import os
import sys
import time
import argparse
from pathlib import Path

# Mixamo API 端點
MIXAMO_API = "https://www.mixamo.com/api/v1"
MIXAMO_SEARCH = f"{MIXAMO_API}/products"
MIXAMO_EXPORT = f"{MIXAMO_API}/animations/export"
MIXAMO_MONITOR = f"{MIXAMO_API}/characters/export/monitor"

# 預設角色 ID (Mixamo 的 Y-Bot)
DEFAULT_CHARACTER_ID = "dae19637-5c52-40c3-b87e-2fa3c5e220a5"

# 預定義的搜尋關鍵字組（用於 Motion Matching）
MOTION_MATCHING_QUERIES = {
    "locomotion": [
        "walking", "walk forward", "walk backward",
        "walk left", "walk right", "walk turn",
        "running", "run forward", "run backward",
        "run left", "run right", "run turn",
        "jog", "jog forward", "jog backward",
        "sprint",
    ],
    "starts_stops": [
        "start walking", "stop walking",
        "start running", "stop running",
        "idle", "standing idle",
        "braking", "skid",
    ],
    "turns": [
        "turn left", "turn right",
        "turn 90", "turn 180",
        "pivot", "quick turn",
    ],
    "crouching": [
        "crouch", "crouch walk", "crouch idle",
        "sneak", "stealth",
    ],
    "jumping": [
        "jump", "jump forward", "landing",
        "jump in place", "running jump",
    ],
    "climbing": [
        "climb", "climbing", "hanging",
        "braced hang", "free hang",
        "wall climb", "ledge",
    ],
}


class MixamoDownloader:
    def __init__(self, token: str, character_id: str = DEFAULT_CHARACTER_ID):
        self.token = token
        self.character_id = character_id
        self.session = requests.Session()
        self.session.headers.update({
            "Accept": "application/json",
            "Content-Type": "application/json",
            "Authorization": f"Bearer {token}",
            "X-Api-Key": "mixamo2",
        })
        self.downloaded = set()
        self._load_history()

    def _history_path(self):
        return Path(__file__).parent / "mixamo_download_history.json"

    def _load_history(self):
        """載入已下載歷史，避免重複下載"""
        p = self._history_path()
        if p.exists():
            with open(p, "r", encoding="utf-8") as f:
                self.downloaded = set(json.load(f))
            print(f"[INFO] 已載入 {len(self.downloaded)} 筆下載記錄")

    def _save_history(self):
        with open(self._history_path(), "w", encoding="utf-8") as f:
            json.dump(list(self.downloaded), f, indent=2)

    def search(self, query: str, page: int = 1, per_page: int = 96) -> list:
        """搜尋 Mixamo 動畫"""
        params = {
            "query": query,
            "page": page,
            "limit": per_page,
            "type": "Motion",
        }
        try:
            resp = self.session.get(MIXAMO_SEARCH, params=params, timeout=30)
            resp.raise_for_status()
            data = resp.json()
            results = data.get("results", [])
            total = data.get("pagination", {}).get("num_results", 0)
            print(f"[搜尋] '{query}' → 找到 {total} 個動畫 (顯示 {len(results)} 個)")
            return results
        except requests.exceptions.RequestException as e:
            print(f"[錯誤] 搜尋失敗: {e}")
            return []

    def search_all(self, query: str, max_results: int = 200) -> list:
        """搜尋所有頁面"""
        all_results = []
        page = 1
        per_page = 96
        while len(all_results) < max_results:
            results = self.search(query, page=page, per_page=per_page)
            if not results:
                break
            all_results.extend(results)
            if len(results) < per_page:
                break
            page += 1
            time.sleep(0.5)  # 避免過快請求
        return all_results[:max_results]

    def request_export(self, anim_id: str, anim_name: str,
                       fps: int = 30, skin: bool = False) -> str | None:
        """請求匯出動畫 FBX"""
        # Mixamo 匯出格式選項
        # format: "fbx7_2019" / "fbx7" / "fbx6"
        # skin: 是否包含角色網格（Motion Matching 不需要）
        payload = {
            "character_id": self.character_id,
            "gms_hash": [{
                "model-id": anim_id,
                "params": "{}",  # 預設參數
            }],
            "preferences": {
                "format": "fbx7_2019",
                "skin": "true" if skin else "false",
                "fps": str(fps),
                "reducekf": "0",  # 不減少關鍵幀（Motion Matching 需要完整數據）
            },
            "type": "Motion",
            "product_name": anim_name,
        }

        try:
            resp = self.session.post(MIXAMO_EXPORT, json=payload, timeout=30)
            resp.raise_for_status()
            # 回傳的是匯出任務 ID 或直接的下載 URL
            data = resp.json()
            return data  # 包含 uuid 或 job_id
        except requests.exceptions.RequestException as e:
            print(f"[錯誤] 匯出請求失敗 ({anim_name}): {e}")
            return None

    def poll_export(self, character_id: str, max_wait: int = 120) -> str | None:
        """輪詢匯出狀態，取得下載 URL"""
        params = {"character_id": character_id}
        start = time.time()

        while time.time() - start < max_wait:
            try:
                resp = self.session.get(MIXAMO_MONITOR, params=params, timeout=30)
                resp.raise_for_status()
                data = resp.json()

                status = data.get("status", "")
                if status == "completed":
                    return data.get("job_result", "")
                elif status == "failed":
                    print(f"[錯誤] 匯出失敗")
                    return None
                else:
                    print(f"  [等待] 匯出中... ({status})")
                    time.sleep(2)
            except requests.exceptions.RequestException as e:
                print(f"[錯誤] 輪詢失敗: {e}")
                time.sleep(3)

        print(f"[超時] 匯出等待超過 {max_wait} 秒")
        return None

    def download_file(self, url: str, save_path: Path) -> bool:
        """下載 FBX 檔案"""
        try:
            resp = self.session.get(url, timeout=60, stream=True)
            resp.raise_for_status()
            save_path.parent.mkdir(parents=True, exist_ok=True)
            with open(save_path, "wb") as f:
                for chunk in resp.iter_content(chunk_size=8192):
                    f.write(chunk)
            size_mb = save_path.stat().st_size / (1024 * 1024)
            print(f"  [✅] 已下載: {save_path.name} ({size_mb:.1f} MB)")
            return True
        except requests.exceptions.RequestException as e:
            print(f"  [❌] 下載失敗: {e}")
            return False

    def download_animation(self, anim_id: str, anim_name: str,
                           output_dir: Path, fps: int = 30) -> bool:
        """完整流程：請求匯出 → 輪詢 → 下載"""
        # 檢查是否已下載
        if anim_id in self.downloaded:
            print(f"  [跳過] 已下載: {anim_name}")
            return True

        safe_name = "".join(c if c.isalnum() or c in " _-" else "_" for c in anim_name)
        save_path = output_dir / f"{safe_name}.fbx"

        if save_path.exists():
            print(f"  [跳過] 檔案已存在: {save_path.name}")
            self.downloaded.add(anim_id)
            self._save_history()
            return True

        print(f"\n[下載] {anim_name} (ID: {anim_id})")

        # 1. 請求匯出
        export_result = self.request_export(anim_id, anim_name, fps=fps)
        if not export_result:
            return False

        # 2. 輪詢等待
        download_url = self.poll_export(self.character_id)
        if not download_url:
            return False

        # 3. 下載
        success = self.download_file(download_url, save_path)
        if success:
            self.downloaded.add(anim_id)
            self._save_history()

        time.sleep(1)  # 禮貌延遲
        return success

    def batch_download(self, query: str, output_dir: Path,
                       max_count: int = 50, fps: int = 30):
        """批量搜尋並下載"""
        print(f"\n{'='*60}")
        print(f"批量下載: '{query}'")
        print(f"輸出目錄: {output_dir}")
        print(f"{'='*60}")

        results = self.search_all(query, max_results=max_count)
        if not results:
            print("[WARN] 沒有搜尋結果")
            return

        success_count = 0
        for i, anim in enumerate(results):
            anim_id = anim.get("id", "")
            anim_name = anim.get("description", f"anim_{i}")
            print(f"\n[{i+1}/{len(results)}] ", end="")
            if self.download_animation(anim_id, anim_name, output_dir, fps=fps):
                success_count += 1

        print(f"\n{'='*60}")
        print(f"完成! 成功 {success_count}/{len(results)}")
        print(f"{'='*60}")

    def batch_download_motion_matching(self, output_base: Path, fps: int = 30):
        """下載 Motion Matching 所需的完整動畫集"""
        print("\n" + "=" * 60)
        print("Motion Matching 動畫集批量下載")
        print("=" * 60)

        total = 0
        for category, queries in MOTION_MATCHING_QUERIES.items():
            category_dir = output_base / category
            for query in queries:
                self.batch_download(query, category_dir, max_count=10, fps=fps)
                total += 1

        print(f"\n完成所有類別下載 ({total} 個查詢)")

    def list_animations(self, query: str):
        """僅列出搜尋結果（不下載）"""
        results = self.search_all(query, max_results=200)
        print(f"\n{'ID':<40} {'名稱'}")
        print("-" * 80)
        for anim in results:
            anim_id = anim.get("id", "???")
            name = anim.get("description", "???")
            duration = anim.get("duration", 0)
            print(f"{anim_id:<40} {name} ({duration:.1f}s)")
        print(f"\n共 {len(results)} 個動畫")


def main():
    parser = argparse.ArgumentParser(
        description="Mixamo 動畫批量下載工具",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
使用範例:
  # 列出搜尋結果
  python mixamo_downloader.py --token TOKEN --list --query "walking"
  
  # 下載特定搜尋結果
  python mixamo_downloader.py --token TOKEN --query "walk forward" --output ./animations
  
  # 下載 Motion Matching 完整動畫集
  python mixamo_downloader.py --token TOKEN --motion-matching --output ./animations
  
取得 Token:
  1. 登入 https://www.mixamo.com
  2. F12 → Network → 找任意 API 請求
  3. 複製 Request Headers 中的 Authorization: Bearer <TOKEN>
        """,
    )
    parser.add_argument("--token", required=True, help="Mixamo Bearer token")
    parser.add_argument("--query", "-q", help="搜尋關鍵字")
    parser.add_argument("--output", "-o", default="./mixamo_animations",
                        help="輸出目錄 (預設: ./mixamo_animations)")
    parser.add_argument("--list", "-l", action="store_true",
                        help="僅列出搜尋結果，不下載")
    parser.add_argument("--max", "-m", type=int, default=50,
                        help="最大下載數量 (預設: 50)")
    parser.add_argument("--fps", type=int, default=30,
                        help="FBX 幀率 (預設: 30)")
    parser.add_argument("--motion-matching", action="store_true",
                        help="下載 Motion Matching 所需的完整動畫集")
    parser.add_argument("--character", default=DEFAULT_CHARACTER_ID,
                        help="Mixamo 角色 ID (預設: Y-Bot)")

    args = parser.parse_args()

    downloader = MixamoDownloader(args.token, args.character)
    output_dir = Path(args.output)

    if args.list:
        if not args.query:
            print("[錯誤] --list 需要搭配 --query")
            sys.exit(1)
        downloader.list_animations(args.query)
    elif args.motion_matching:
        downloader.batch_download_motion_matching(output_dir, fps=args.fps)
    elif args.query:
        downloader.batch_download(args.query, output_dir,
                                  max_count=args.max, fps=args.fps)
    else:
        parser.print_help()


if __name__ == "__main__":
    main()
