# 測試結果（2026-10-01）

## 環境
- 機器：MacBook Air（Apple Silicon），Darwin 25.5.0
- 工具鏈：Swift 6.3.2、Command Line Tools（無 Xcode）
- 測試鏡頭：**內建「MacBook Air 相機」**。測試時沒有接任何 USB 攝影機。
- 量測方式：`top -l N -s 2 -pid <pid>`（每 2 秒一筆；第一筆恆為 0，無意義）、活動監視器、`sample` 取樣。

## 功能驗證
| 項目 | 結果 |
|---|---|
| `make app` / `make run` / `make dmg` | 通過，產出 `USBCamera.app` 與 `.dmg` |
| 啟動後預覽 | 通過（截圖確認有畫面，1280×720 @30fps） |
| 攝影機 / 解析度下拉選單顯示 | 通過（截圖確認） |
| USB 攝影機偵測與插拔 | **未測**（沒有 USB 攝影機） |
| 拍照、錄影、鏡像、切換解析度 | **未測** |

## CPU 量測（內建鏡頭、預覽中、視窗在最前面）

| 版本 | 量測值（%CPU） | 備註 |
|---|---|---|
| v1 初版（麥克風、拍照、錄影輸出常駐） | 17.4、18.0、18.8、15.7、16.3（`ps`） | 使用者回報 21% |
| v2 輸出按需接上 + 預設 720p | 10.2、16.3、14.2（`top`）；活動監視器 17.7 | 與 v1 無明顯差異 |
| v3 再加關閉 Center Stage + plist 關手勢 | 8.9、13.6、14.6、14.3、21.4（`top`） | 無明顯差異 |
| v4 再改 bundle ID 重設手勢預設 | 9.6、14.0、15.3、12.6、11.8（`top`） | 約 12–15% |

- 記憶體：RSS 約 100 MB（`ps`）；`top` 顯示約 200 MB。
- 執行緒：22–23 條。
- **量測異常**：v2、v3 剛啟動且視窗沒在最前面時，`ps`/`top` 曾連續回報 0.0%。把視窗帶到最前面後才出現 10–15%。原因未查明（推測是視窗被遮住時預覽不渲染），所以這些 0% 不能當作優化成果。
- 數字波動大（8.9–21.4），上表只能說「大約 12–15%」，不是精確值。

## 取樣分析（v2～v4）
- app 自己的程式碼幾乎沒有工作：約 2330 個樣本停在 `semaphore_timedwait_trap`（等待）。
- 可見的 CPU 消耗來自系統注入到本行程的相機特效管線：
  - `FigObjectDetectionMetadataGenerator`（人臉偵測）
  - `VNANFDMultiDetector`（Vision 人臉偵測，ANE）
  - `VCPHandGestureVideoRequestSerialQueue`（手勢「反應」偵測）
  - `PTEffect render`（Portrait 渲染）
  - Espresso / ANSTKit（ANE 執行）
- v4 的手勢相關樣本由 10 降到 3，沒有完全消失；人臉偵測與 Portrait 仍在跑。
- 內建鏡頭所有格式都支援 reactions / Center Stage / Portrait / Studio Light / 背景取代，換解析度無法避開。

## 結論
- 內建鏡頭下，app 約 12–15% CPU，**未達到「低於 FaceTime」的目標**，且沒有同機量 FaceTime 做對照。
- 主要消耗來自系統視訊效果，不是 app 程式碼；我們已做的改動（輸出按需接上、720p、關 Center Stage、plist 關手勢）沒有帶來明顯改善。
- 尚待驗證：
  1. 接上真正的 USB 攝影機後的 CPU（預期較低，但未驗證）。
  2. 在控制中心關閉「反應」「人像」等視訊效果後的 CPU。
  3. 同機同鏡頭量 FaceTime 的 CPU 作為基準。
