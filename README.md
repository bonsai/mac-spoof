# mac-spoof

Wi-Fi MAC アドレス改竄で McDonald's 無料Wi-Fi の1時間接続制限を回避するツール。

## 仕組み

```
レジストリ HKEY_LOCAL_MACHINE\...\NetworkAddress にランダムMACを書込
  → Wi-Fiアダプタを Disable/Enable
  → ドライバがレジストリから新MACを読み込む
  → 同じ SSID (00_MCD-FREE-WIFI) に自動再接続
  → AP側で新端末扱い → 1時間タイマーリセット
```

## ファイル

| ファイル | 役割 | 実行環境 |
|----------|------|----------|
| `wifi-mac-rotate.ps1` | MAC 改竄 (レジストリ方式) | Windows PowerShell (管理者) |
| `wifi-mac-rotate.sh` | 上を呼ぶラッパー + DB記録 | WSL |
| `ms.py` | DB 状態表示 CLI | WSL (Python3) |
| `schema.sql` | DB スキーマ (tsubame.db) | SQLite |
| `config/meta.template.json` | 位置情報テンプレ | — |
| `install.sh` | セットアップ | WSL |

## 使い方

```bash
# ステータス確認
./wifi-mac-rotate.sh status

# MAC 改竄 (即時実行)
./wifi-mac-rotate.sh

# DB 確認
python3 ms.py status
python3 ms.py probes
python3 ms.py sessions
python3 ms.py networks
```

## 自動化

cron で45分おきに自動実行:

```cron
0,45  0,3,6,9,12,15,18,21  * * *  wifi-mac-rotate cron
30    1,4,7,10,13,16,19,22 * * *  wifi-mac-rotate cron
15    2,5,8,11,14,17,20,23 * * *  wifi-mac-rotate cron
```

## 切断時間について

| 方法 | 切断時間 | MAC変更 | 備考 |
|------|---------|---------|------|
| Disable/Enable (本方式) | 約8秒 | ✅ | 確実 |
| netsh disconnect/connect | 約1秒 | ❌変わらず | 意味なし |
| Disable/Enable + USBテザリング | **0秒** | ✅ | 最善策 |

USB テザリングをバックアップ回線として繋いでおくと、Wi-Fi 切断時に自動フォールバックするため切断0秒を実現できます。

## 必須環境

- Windows 10/11 (管理者権限)
- WSL2 (Ubuntu)
- PowerShell
- sqlite3
- Python 3 (ms.py を使う場合)

## セットアップ

```bash
git clone https://github.com/YOUR_NAME/mac-spoof.git
cd mac-spoof
chmod +x install.sh && ./install.sh
```

## 詳細

- McDonald's WiFi `00_MCD-FREE-WIFI` はオープン認証（暗号化なし）
- MAC アドレスベースのアクセス制御を採用
- キャプティブポータルなし（HTTP 204 確認済み）
- 改竄後も同一APに自動再接続することを実測確認済み
