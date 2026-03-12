/**
 * Mixamo 批量下載 - 瀏覽器 Console 腳本
 * ==========================================
 * 
 * 使用方法:
 * 1. 登入 https://www.mixamo.com
 * 2. 選擇一個角色 (例如 Y-Bot)
 * 3. F12 打開 DevTools → Console
 * 4. 複製貼上此腳本，按 Enter
 * 5. 腳本會自動搜尋並下載動畫
 * 
 * ⚠️ 注意: 
 * - 瀏覽器可能會阻止多檔下載，需允許
 * - 每次下載間隔 3 秒，避免被封
 * - 動畫以 FBX Binary 格式下載 (含骨架，不含皮膚)
 */

// ========== 設定區 ==========
const CONFIG = {
    // Motion Matching 所需的搜尋關鍵字
    queries: [
        // 基礎移動
        "walking", "walk forward", "walk backward", "walk left", "walk right",
        "running", "run forward", "run backward", "run left", "run right",
        "jog forward", "jog backward",
        "sprint",

        // 起停
        "start walking", "stop walking",
        "start running", "stop running",
        "standing idle", "idle",

        // 轉向
        "turn left", "turn right",
        "turn 90", "turn 180",
        "quick turn",

        // 蹲姿
        "crouch walk", "crouch idle", "sneak walk",

        // (可自行增減)
    ],

    maxPerQuery: 5,       // 每個關鍵字最多下載幾個
    delayMs: 3000,        // 下載間隔 (毫秒)
    fps: 30,              // FBX 幀率
    format: "fbx7_2019",  // FBX 格式
    skinIncluded: false,  // 是否包含角色網格 (Motion Matching 通常不需要)
    reducekf: 0,          // 關鍵幀簡化 (0 = 不簡化，MM 需要完整數據)
};

// ========== 工具函數 ==========

function getToken() {
    // 從頁面 cookie/storage 取得 token
    const cookies = document.cookie.split(';');
    for (const c of cookies) {
        const [k, v] = c.trim().split('=');
        if (k === 'access_token') return v;
    }
    // 嘗試 localStorage
    const stored = localStorage.getItem('access_token');
    if (stored) return stored;

    console.warn("⚠️ 自動取得 token 失敗，嘗試從 Network 請求中提取...");
    return null;
}

function getCharacterId() {
    // 從頁面 URL 或 API 取得當前角色 ID
    try {
        const state = JSON.parse(localStorage.getItem('characters') || '{}');
        const selected = state.selectedCharacter;
        if (selected) return selected;
    } catch (e) { }

    // 預設 Y-Bot
    return "dae19637-5c52-40c3-b87e-2fa3c5e220a5";
}

async function sleep(ms) {
    return new Promise(resolve => setTimeout(resolve, ms));
}

async function searchAnimations(query, limit = 96) {
    const url = `https://www.mixamo.com/api/v1/products?query=${encodeURIComponent(query)}&page=1&limit=${limit}&type=Motion`;

    const resp = await fetch(url, {
        headers: {
            "Accept": "application/json",
            "X-Api-Key": "mixamo2",
        },
        credentials: "include",
    });

    if (!resp.ok) throw new Error(`搜尋失敗: ${resp.status}`);
    const data = await resp.json();
    return data.results || [];
}

async function requestExport(characterId, animId, animName) {
    const payload = {
        character_id: characterId,
        gms_hash: [{
            "model-id": animId,
            params: "{}",
        }],
        preferences: {
            format: CONFIG.format,
            skin: CONFIG.skinIncluded ? "true" : "false",
            fps: String(CONFIG.fps),
            reducekf: String(CONFIG.reducekf),
        },
        type: "Motion",
        product_name: animName,
    };

    const resp = await fetch("https://www.mixamo.com/api/v1/animations/export", {
        method: "POST",
        headers: {
            "Accept": "application/json",
            "Content-Type": "application/json",
            "X-Api-Key": "mixamo2",
        },
        credentials: "include",
        body: JSON.stringify(payload),
    });

    if (!resp.ok) throw new Error(`匯出請求失敗: ${resp.status}`);
    return await resp.json();
}

async function pollExport(characterId, maxAttempts = 60) {
    const url = `https://www.mixamo.com/api/v1/characters/export/monitor?character_id=${characterId}`;

    for (let i = 0; i < maxAttempts; i++) {
        const resp = await fetch(url, {
            headers: { "X-Api-Key": "mixamo2" },
            credentials: "include",
        });

        if (!resp.ok) { await sleep(2000); continue; }
        const data = await resp.json();

        if (data.status === "completed") {
            return data.job_result;
        } else if (data.status === "failed") {
            throw new Error("匯出失敗");
        }

        await sleep(2000);
    }
    throw new Error("匯出超時");
}

function triggerDownload(url, filename) {
    const a = document.createElement('a');
    a.href = url;
    a.download = filename;
    document.body.appendChild(a);
    a.click();
    document.body.removeChild(a);
}

// ========== 主流程 ==========

async function batchDownload() {
    const characterId = getCharacterId();
    console.log(`🎭 角色 ID: ${characterId}`);
    console.log(`📋 搜尋關鍵字: ${CONFIG.queries.length} 個`);
    console.log(`📁 每個關鍵字最多下載 ${CONFIG.maxPerQuery} 個`);
    console.log("");

    let totalDownloaded = 0;
    let totalFailed = 0;
    const downloaded = new Set();

    for (const query of CONFIG.queries) {
        console.log(`\n🔍 搜尋: "${query}"`);

        try {
            const results = await searchAnimations(query, CONFIG.maxPerQuery);
            console.log(`   找到 ${results.length} 個動畫`);

            for (const anim of results.slice(0, CONFIG.maxPerQuery)) {
                const animId = anim.id;
                const animName = anim.description || `anim_${animId}`;

                if (downloaded.has(animId)) {
                    console.log(`   ⏭️ 跳過 (已下載): ${animName}`);
                    continue;
                }

                try {
                    console.log(`   ⬇️ 下載中: ${animName}`);

                    await requestExport(characterId, animId, animName);
                    const downloadUrl = await pollExport(characterId);

                    if (downloadUrl) {
                        const safeName = animName.replace(/[^a-zA-Z0-9 _-]/g, '_');
                        triggerDownload(downloadUrl, `${safeName}.fbx`);
                        downloaded.add(animId);
                        totalDownloaded++;
                        console.log(`   ✅ 完成: ${animName}`);
                    }
                } catch (e) {
                    console.error(`   ❌ 失敗: ${animName} - ${e.message}`);
                    totalFailed++;
                }

                await sleep(CONFIG.delayMs);
            }
        } catch (e) {
            console.error(`   ❌ 搜尋失敗: ${e.message}`);
        }
    }

    console.log("\n" + "=".repeat(50));
    console.log(`🎉 批量下載完成!`);
    console.log(`   ✅ 成功: ${totalDownloaded}`);
    console.log(`   ❌ 失敗: ${totalFailed}`);
    console.log("=".repeat(50));
}

// 開始執行
batchDownload();
