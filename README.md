# mac-spoof

Wi-Fi MAC アドレス改竄で McDonald's 無料Wi-Fi の1時間接続制限を回避するツール。

## 仕組み

```
レジストリ HKLM\...\NetworkAddress にランダムMACを書込
  → Wi-Fiアダプタを Disable/Enable
  → ドライバがレジストリから新MACを読み込み直す
  → 同じ SSID (00_MCD-FREE-WIFI) に自動再接続
  → AP側で新端末扱い → 1時間タイマーリセット
```

## ファイル一覧

| ファイル | 役割 | 環境 |
|----------|------|------|
| `wifi-mac-rotate.ps1` | MAC改竄エンジン (レジストリ方式) | Windows PowerShell (管理者) |
| `wifi-mac-rotate.sh` | WSLラッパー + DB記録 | WSL |
| `tray.ps1` | タスクトレイ常駐 (通知/手動rotate) | Windows PowerShell |
| `ms` (Go) | 状態確認CLI (detect/speed/scan/status) | WSL / Windows |
| `schema.sql` | DBスキーマ | SQLite |
| `go.mod` / `main.go` | ms のソース | Go |

## 使い方

### CLI (ms)

```bash
ms detect       # 今のWiFi情報を表示 (DB不使用)
ms speed        # 速度測定のみ
ms scan         # detect + speed → DB記録
ms status       # DBから最新状態を表示
ms probes       # プローブ履歴
ms sessions     # セッション履歴
ms networks     # 既知ネットワーク一覧
```

### MAC改竄 (手動)

```bash
# WSLから
bash wifi-mac-rotate.sh          # 改竄 + DB記録
bash wifi-mac-rotate.sh status   # MAC確認のみ

# Windows PowerShell (管理者) から直接
powershell -ExecutionPolicy Bypass -File wifi-mac-rotate.ps1
```

### タスクトレイ常駐

管理者PowerShellで起動:

```powershell
powershell -ExecutionPolicy Bypass -File tray.ps1
```

タスクトレイアイコンを右クリック → Rotate Now / Show Status / Exit

## 自動化

cron (WSL) で45分おきに自動実行:

```cron
0,45 0,3,6,9,12,15,18,21 * * * wifi-mac-rotate cron
30    1,4,7,10,13,16,19,22   * * * wifi-mac-rotate cron
15    2,5,8,11,14,17,20,23   * * * wifi-mac-rotate cron
```

## 切断時間について

| 方法 | 切断時間 | MAC変更 | 備考 |
|------|---------|---------|------|
| Disable/Enable (本方式) | 約8秒 | ✅ 確実 | 実測済み |
| netsh disconnect/connect | 約1秒 | ❌ 変わらず | MAC未変更 |
| + USBテザリング併用 | **0秒** | ✅ | バックアップ回線 |

USBテザリングをバックアップに繋いでおくと、Wi-Fi切断時に自動フォールバックして切断0秒になります。

## ビルド

```bash
# Go 1.21+ が必要
go build -o ms .
```

## 環境変数

| 変数 | デフォルト | 説明 |
|------|-----------|------|
| `MAC_SPOOF_DB` | `~/.wifi-mac-tracker/mac-spoof.db` | DBファイルパス |
| `MAC_SPOOF_META` | `~/.wifi-mac-tracker/meta.json` | 位置情報メタ |

## 必須環境

- Windows 10/11 (管理者権限)
- WSL2 (Ubuntu)
- Go 1.21+ (ビルド時)
- PowerShell
- sqlite3 (wifi-mac-rotate.sh用)
