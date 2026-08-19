# dsh-undo-savepoint 鈥?DSH 鎾ら攢/鍥為€€绯荤粺

[![awesome 路 DSH plugin](https://awesome-dsh-plugin.com/badge.svg)](https://awesome-dsh-plugin.com)
[![CI](https://github.com/lire1131/dsh-undo-savepoint/actions/workflows/ci.yml/badge.svg)](https://github.com/lire1131/dsh-undo-savepoint/actions/workflows/ci.yml)

> 涓枃 | [English](README.en.md) | [鏇存柊鏃ュ織](CHANGELOG.md)

**DSH 宕╂簝鎬ユ晳鎻掍欢锛氶厤缃笌鎻掍欢浠ｇ爜涓€閿洖婊氥€佸揩鐓у瘑閽ヨ劚鏁忋€佷竴閿畨鍏ㄦā寮忥紝DSH 璧蜂笉鏉ユ椂涔熻兘鐢紙绂荤嚎 CLI/GUI锛夈€?*

**杩樺湪涓?DSH 宕╂簝鑰岃嫤鎭?杩樺湪鎷呭績灏忔敼鍔ㄤ細甯︽潵澶х伨闅?杩欐宸ュ叿鑳藉府鍒颁綘!**

涓?[DeepSeek Harness (DSH)](https://github.com/deepseek-ai/deepseek-harness) 鎵撻€犵殑鎾ら攢/鍥為€€绯荤粺:**瑁呮彃浠躲€佹崲鐨偆銆佹敼璁剧疆,鑷姩淇濆瓨鍗冲瓨妗?鎵嬪姩淇濆瓨闅忔椂瀛樻。;涓€閿挙閿€/鎭㈠/鍥為€€鍒颁换鎰忕増鏈?*,DSH 鍚姩涓嶄簡鏃惰繕鏈夊眬澶栧伐鍏?GUI 绐楀彛 + 鍛戒护琛?鍏滃簳銆?

## 棰勮

| v0.3.5 浼氳瘽澶撮儴:鎾ら攢/鎭㈠/蹇収鎸夐挳鍏ㄩ儴鍥炬爣鍖?+ 鑷姩蹇収鐘舵€佸窘绔?鐐瑰嚮寰界珷鎵撳紑蹇収闈㈡澘) |
|---|
| ![header](https://cdn.jsdelivr.net/gh/lire1131/dsh-undo-savepoint@master/docs/webui-header.png) |

| WebUI 蹇収绠＄悊闈㈡澘(宸紓/鍥為€€/鍒犻櫎/娓呯悊/瀵煎嚭/瀵煎叆/瀹夊叏妯″紡) | WebUI 璁剧疆銆屽揩鐓с€嶇嫭绔嬫爮鐩?鏁忔劅妯″紡/鎻掍欢鐧藉悕鍗?鐩綍閫夋嫨) |
|---|---|
| ![panel](https://cdn.jsdelivr.net/gh/lire1131/dsh-undo-savepoint@master/docs/webui-panel.png) | ![settings](https://cdn.jsdelivr.net/gh/lire1131/dsh-undo-savepoint@master/docs/webui-settings-section.png) |

| 灞€澶栫▼搴忕獥鍙?涓よ宸ュ叿鏍?+ 瀹夊叏妯″紡鎸夐挳,DSH 鎸備簡涔熻兘鐢? | 灞€澶栬缃璇濇(鏁忔劅妯″紡/娴忚閫夌洰褰? |
|---|---|
| ![gui](https://cdn.jsdelivr.net/gh/lire1131/dsh-undo-savepoint@master/docs/gui-main.png) | ![guisettings](https://cdn.jsdelivr.net/gh/lire1131/dsh-undo-savepoint@master/docs/gui-settings.png) |

| 瀹夊叏妯″紡纭(杩涘叆/閫€鍑? | 瀹夊叏妯″紡鐘舵€佹彁绀?|
|---|---|
| ![confirm](https://cdn.jsdelivr.net/gh/lire1131/dsh-undo-savepoint@master/docs/safe-mode-confirm.png) | ![done](https://cdn.jsdelivr.net/gh/lire1131/dsh-undo-savepoint@master/docs/safe-mode-done.png) |

## 鍔熻兘涓€瑙?

| 鑳藉姏 | 璇存槑 |
|---|---|
| **閰嶇疆 + 鎻掍欢浠ｇ爜涓€閿洖婊?* | 蹇収瑕嗙洊閰嶇疆涓庣敤鎴锋彃浠朵唬鐮佹爲锛屾敼鍧忎换浣曚竴澶勯兘鑳芥挙閿€锛堝惈 yield\* 绫荤函浠ｇ爜浜嬫晠锛夛紱鏀寔 undo / redo / 鍥為€€浠绘剰鐗堟湰锛學ebUI / 瀵硅瘽 / 绂荤嚎 CLI 涓夊叆鍙?|
| **瀵嗛挜鑴辨晱 + 鏈満 vault** | `.env` / 鍑嵁杩涘揩鐓ц嚜鍔ㄨ劚鏁忥紙缁撴瀯淇濈暀锛夛紝瀵煎嚭 ZIP 闆舵硠闇诧紱鐪熷疄鍊煎瓨鏈満 vault锛?*鏈満鍥炴粴瀹屾暣杩樺師** |
| **涓€閿畨鍏ㄦā寮?* | DSH 瀹屽叏璧蜂笉鏉ユ椂锛岀鐢ㄩ櫎鎾ら攢绯荤粺澶栨墍鏈夋彃浠朵繚璇佽兘鍚姩锛岃嚜鍔ㄥ揩鐓?澶囦唤閰嶇疆锛屼竴閿€€鍑?|
| **宕╂簝褰掑洜** | 涓婃寮傚父閫€鍑烘椂鐩存帴缁欏嚭銆屾渶鍚庢甯稿揩鐓с€峣d + 涓€閿洖閫€鎸夐挳锛屼笉鐢ㄨ嚜宸辩寽鍥為€€鍒板摢 |
| **璺ㄦ満杩佺Щ瀹夊叏** | 鎭㈠鍓嶈嚜鍔ㄩ妫€缂哄け鎻掍欢骞舵槑纭彁绀猴紱蹇収鍙竴閿鍑?瀵煎叆 ZIP 杩佺Щ锛堣 [docs/migration.md](docs/migration.md)锛?|
| **灞€澶栨€ユ晳锛圖SH 鎸備簡涔熻兘鐢級** | 绂荤嚎 CLI + GUI 绐楀彛 + 涓€閿闈㈠揩鎹锋柟寮忥細鎾ら攢/鍥為€€/瀹夊叏妯″紡/宕╂簝妯箙/鍥炴粴鏃ュ織涓€搴斾勘鍏?|

> 鍩虹鑳藉姏锛堥敭鐩樺揩鎹烽敭銆佸璇濇寚浠ゃ€佽嚜鍔ㄦ竻鐞嗐€佸弻妯″紡淇濆瓨銆佸彲閰嶇疆鍙傛暟绛夛級璇﹁涓嬫枃涓?[鏇存柊鏃ュ織](CHANGELOG.md)銆?

## 宕╂簝鎬ユ晳閫熸煡锛堟寜鍦烘櫙閫夊伐鍏凤級

| 鍦烘櫙 | 鎿嶄綔 |
|---|---|
| 閰嶇疆/鎻掍欢琚敼鍧?| 瀵硅瘽/WebUI/CLI:`undo` 鎴?`restore -Id <id>` |
| 鎻掍欢浠ｇ爜琚敼鍧?| 鍚屼笂(蹇収鍚彃浠朵唬鐮佹爲,涓€閿繕鍘? |
| 涓婃寮傚父閫€鍑?涓嶇煡鍥為€€鍒板摢 | WebUI 妯箙 / GUI 妯箙 鏄剧ず last-good 蹇収,涓€閿洖閫€ |
| **DSH 瀹屽叏璧蜂笉鏉?* | 妗岄潰銆孌SH鎾ら攢绠＄悊鍣ㄣ€嶁啋 **瀹夊叏妯″紡**鎸夐挳(鎴?CLI `safe-mode -Label on`)鈫?閲嶅惎 DSH 淇濊瘉鑳藉惎鍔?|
| 鎭㈠鍚庡彲鑳界己鎻掍欢(璺ㄦ満) | 鎭㈠鎶ュ憡棰勬鎻愮ず;鍏堣鎻掍欢鎴栧畨鍏ㄦā寮?|
| 閰嶇疆"绐佺劧鍙樹簡" | CLI `recent` / 瀵硅瘽 `undo_recent` 鏌ュ洖婊氭棩蹇?|
| 鎾ら攢娑夊強鎻掍欢/鎸傝浇 | 鎶ュ憡鎻愮ず"閲嶅惎 DSH 鍚庣敓鏁? |

## 蹇収鍐呭涓庡瓨鍌?

蹇収瀵硅薄鏄?DSH 鐨?6 涓厤缃枃浠?`cordis.patch.yml`銆乣package.json`銆乣cordis.yml`銆乣pnpm-workspace.yaml`(profile 涓?+ `settings.yaml`銆乣.env`($DSH_HOME 涓?榛樿 ~/.dsh)銆?

| 搴?| 榛樿璺緞(鍙湪璁剧疆涓慨鏀? | 鍐呭 |
|---|---|---|
| 鎵嬪姩搴?| `<蹇収鏍?\manual\` | 鎵嬪姩淇濆瓨鐨勫揩鐓?姘镐笉鑷姩娓呯悊) |
| 鑷姩搴?| `<蹇収鏍?\auto\` | 鑷姩蹇収銆佸惎鍔ㄥ熀绾裤€佹挙閿€鍚庢倲妗?鑷姩妗ｄ繚鐣欐渶杩?20 浠? |
| 鏃у簱(鍏煎) | `<蹇収鏍?\` 鏍?| 鏃х増鎵佸钩甯冨眬,璇诲彇鍏煎,鍚姩鏃惰嚜鍔ㄨ縼绉诲埌鏂板簱 |

> 鈿狅笍 蹇収鍚?`.env` 绛夐厤缃壇鏈?鍙兘鍚瘑閽モ€斺€斾笉瑕佸浼犮€?

## 澶?profile 鏀寔(v0.3.3)

鎻掍欢浠庡惎鍔ㄥ弬鏁拌嚜鍔ㄨ瘑鍒綋鍓?profile(`dsh --profile mine` / `--profile=mine`;`dsh web` 鍥為€€涓?`web`),骞舵寜褰撳墠 profile 宸ヤ綔:

- **閰嶇疆鐩綍**:榛樿 `$DSH_HOME/profiles/<褰撳墠 profile>`(DSH_HOME 榛樿 ~/.dsh;姝ゅ墠纭紪鐮?`web`鈥斺€旈潪 web profile 涓嬪揩鐓ц閿欍€佺洃鍚敊銆佹仮澶嶅啓閿欎綅缃?;
- **蹇収浠撳簱**:榛樿 `<蹇収鏍?/<褰撳墠 profile>/{auto,manual}`(鎸?profile 闅旂);浣滅敤鍩熺洰褰曚笉瀛樺湪鑰屾棫鐗堝钩閾虹洰褰曞瓨鍦ㄦ椂鑷姩鍥為€€骞抽摵,鏃у揩鐓т笉浼?闅愯韩";
- **褰掑睘鏍囪瘑**:蹇収 manifest 璁板綍 `profile` 瀛楁,`undo_list` 鏄剧ず褰撳墠 profile銆?

绂荤嚎 CLI/GUI 鐪嬩笉鍒板惎鍔ㄥ弬鏁?閫氳繃鐜鍙橀噺 `DSH_UNDO_PROFILE` 鎴?settings 閲岀殑 `profileName` 鎸囧畾(榛樿 `web`)銆?

鏄惧紡閰嶇疆浼樺厛绾т笉鍙?`profileDir` / `manualDir` / `autoDir` / `profileName`(config 鎴?settings)濮嬬粓鐢熸晥銆?

## 鑷畾涔夊鐩綍鏀寔(v0.3.5,issue #6)

DSH 鏁版嵁瀹剁洰褰曠殑瑙ｆ瀽涓庡畼鏂瑰惎鍔ㄥ櫒(`@deepseek-ai/dsh-home-paths`)瀹屽叏涓€鑷?**`DSH_HOME` 鐜鍙橀噺浼樺厛**(绌虹櫧瑙嗕负鏈缃?鏀寔 `~` / `~/` / `~\` 鍓嶇紑),鍚﹀垯鍥為€€ `<鐢ㄦ埛瀹剁洰褰?\.dsh`銆傝缃枃浠?`$DSH_HOME\undo\settings.json`)銆侀粯璁ゅ揩鐓ф牴(`$DSH_HOME\undo-snapshots`)銆乸rofile 鐩綍(`$DSH_HOME\profiles\<profile>`)銆乭ome 鏍广€佹彃浠跺彂鐜拌矾寰勫叏閮ㄥ熀浜庡畠鈥斺€旂涓夋柟瀹㈡埛绔?鑷畾涔?`DSH_HOME`)涓嶅啀鍑虹幇"璁剧疆鍐欏埌 `~/.dsh`銆丏SH 瀹為檯鐢?`$DSH_HOME`"鐨勪袱濂楀鍒嗚,閲嶅惎鍚庤嚜瀹氫箟鐩綍绋冲畾淇濈暀銆?

鏄惧紡瑕嗙洊浠嶇劧淇濈暀:`DSH_UNDO_SETTINGS` / `DSH_UNDO_ROOT` / `DSH_UNDO_EXPORT`(鐜鍙橀噺)涓?config 閲岀殑 `homeDir` / `profileDir` / `manualDir` / `autoDir` 浼樺厛绾ф渶楂樸€?

## 浠撳簱鏍囩 (Topics)

鏂逛究鍦?GitHub 鎼滅储涓?Explore 涓鍙戠幇,浠撳簱宸茶缃互涓?topics:

`deepseek-harness` 路 `dsh` 路 `dsh-plugin` 路 `undo` 路 `rollback` 路 `snapshot` 路 `crash-recovery` 路 `backup` 路 `windows` 路 `powershell`

## 瀹夎

鍓嶇疆:宸插畨瑁?DSH(`@deepseek-ai/dsh`)涓?Node.js(鈮?0)銆?

**鏂瑰紡 A(鎺ㄨ崘,npm 鍙戝竷鐗?** 鈥?鏈彃浠跺凡鍙戝竷鍒?npm registry(`dsh-undo-savepoint`)骞跺０鏄?`dsh.bundle` manifest,涓€鏉″懡浠ゅ畨瑁?

```bat
dsh plugin --profile web add dsh-undo-savepoint
```

瀹夎瀹屾垚鍚庨噸鍚?DSH 鍗崇敓鏁?蹇収鐩綍銆佸弬鏁扮瓑鍧囧彲鍦ㄨ缃腑淇敼)銆?

闇€瑕佹墜鍔ㄦ寕杞芥椂,涔熷彲鍦?DSH 瀹夎鏍圭洰褰曠洿鎺ョ敤 npm 瀹夎(peer 渚濊禆鐢?DSH 鎻愪緵,鏃犻渶棰濆瀹夎):

```bat
npm install dsh-undo-savepoint
```

**鏂瑰紡 A2(GitHub 鐩磋)** 鈥?鎯宠 master 鏈€鏂版彁浜ゃ€佷笉绛?npm 鍚屾鏃?

```bat
dsh plugin --profile web add github:lire1131/dsh-undo-savepoint#master
```

**鏂瑰紡 B(鏈湴婧愮爜/鍏嶅彂甯?** 鈥?clone 鍒版湰鍦扮洰褰曞苟鎵嬪伐鎸傝浇:

1. **鎶婁粨搴撴斁鍒版湰鍦版彃浠剁洰褰?*(鏃犱腑鏂囪矾寰勬洿绋冲Ε),渚嬪 `D:\dsh\plugins\dsh-undo-savepoint`:

```bat
git clone https://github.com/lire1131/dsh-undo-savepoint.git D:\dsh\plugins\dsh-undo-savepoint
```

2. **寤虹珛 junction**,璁?DSH 鐨勬ā鍧楄В鏋愬櫒閫氳繃鍖呭悕 `dsh-undo-savepoint` 鎵惧埌鏈湴婧愮爜(host 鎻掍欢涓?WebUI client 鎻掍欢閮介潬瀹?:

```bat
mklink /J "<浣犵殑DSH瀹夎>\node_modules\dsh-undo-savepoint" "D:\dsh\plugins\dsh-undo-savepoint"
```

> 璇存槑:DSH 浠庡畠鑷繁鐨?`node_modules` 鍚戜笂瑙ｆ瀽鍖呭悕銆傞粯璁ゅ畨瑁呬綅缃槸 `C:\Users\<鐢ㄦ埛鍚?\node_modules`(npm 瀹夎鍦ㄧ敤鎴风洰褰曟椂);鑻ョ敤 npx 缂撳瓨杩愯,鍒欏 npx 缂撳瓨鐩綍涓嬬殑 `node_modules` 寤?junction銆傛墽琛?`npm root -g` / 妫€鏌?DSH 鍚姩鎶ラ敊璺緞鍗冲彲纭銆?

3. **鎸傝浇鍒?profile 琛ヤ竵灞?*:缂栬緫 `<DSH_HOME>\profiles\web\cordis.patch.yml`,杩藉姞:

```yaml
- insert:
    - id: dsh-undo-savepoint
      name: dsh-undo-savepoint
```

4. **鐢熸晥**:淇濆瓨鍗崇儹鍔犺浇(host 閮ㄥ垎);鍒锋柊椤甸潰鍑虹幇澶撮儴鎸夐挳涓庤缃」;閲嶅惎 DSH 鍚庝竴鍒囪繘鍏ョǔ鎬?鏃х増鎵佸钩蹇収浼氳嚜鍔ㄨ縼绉?銆?

> 渚濊禆璇存槑:host 鎻掍欢閫氳繃 `createRequire('<DSH瀹夎鏍?/package.json')` 鍔犺浇 `@deepseek-ai/dsh-tools`銆傝嫢 DSH 瀹夎鍦ㄥ叾浠栦綅缃?璁剧疆鐜鍙橀噺 `DSH_ROOT=<DSH瀹夎鏍?` 鍗冲彲,鏃犻渶棰濆瀹夎渚濊禆銆?

## 灞€澶栧伐鍏峰湪鍝?瑁呭畬鎵句笉鍒?)

灞€澶栨挙閿€宸ュ叿(GUI 绐楀彛 + 鍛戒护琛?**涓嶈鍒版闈?鑰屾槸闅忔彃浠惰鍦ㄥ畨瑁呯洰褰曢噷**:

| 瀹夎鏂瑰紡 | 宸ュ叿浣嶇疆 |
|---|---|
| 鏂瑰紡 A:`dsh plugin add` | `$DSH_HOME\profiles\web\node_modules\dsh-undo-savepoint\tools\`(DSH_HOME 榛樿 %USERPROFILE%\.dsh) |
| 鏂瑰紡 B:clone + junction | 浣?clone 鐨勭洰褰?`...\dsh-undo-savepoint\tools\` |

**涓€閿垱寤烘闈㈠揩鎹锋柟寮?鎺ㄨ崘,浠ュ悗浠庢闈㈢洿鎺ユ墦寮€):**

鍙屽嚮 `tools\make-desktop-shortcut.bat`(瀹冧細鑷姩瀹氫綅鎻掍欢鐩綍),妗岄潰鍑虹幇銆孌SH鎾ら攢绠＄悊鍣ㄣ€嶅浘鏍?
鎴栬€呮妸涓嬮潰鏁存澶嶅埗鍒?PowerShell 绐楀彛鍥炶溅(鏃犻渶鍏堟壘鏂囦欢,鑷姩瀹氫綅):

```powershell
$dshHome = if ($env:DSH_HOME) { $env:DSH_HOME } else { "$env:USERPROFILE\.dsh" }
$d = @("$dshHome\profiles\web\node_modules\dsh-undo-savepoint", "$dshHome\profiles\node_modules\dsh-undo-savepoint", "$env:USERPROFILE\node_modules\dsh-undo-savepoint") | Where-Object { Test-Path (Join-Path $_ 'tools\dsh-undo-savepoint-gui.bat') } | Select-Object -First 1
if ($d) {
  $w = New-Object -ComObject WScript.Shell
  $s = $w.CreateShortcut((Join-Path ([Environment]::GetFolderPath('Desktop')) 'DSH鎾ら攢绠＄悊鍣?lnk'))
  $s.TargetPath = Join-Path $d 'tools\dsh-undo-savepoint-gui.bat'
  $s.WorkingDirectory = Join-Path $d 'tools'
  $s.Save()
  Write-Host "宸插垱寤烘闈㈠揩鎹锋柟寮?$($s.FullName)"
} else { Write-Host '鏈壘鍒版彃浠剁洰褰?璇峰厛瀹夎:dsh plugin --profile web add github:lire1131/dsh-undo-savepoint#master' }
```

**鍙兂鎵撳紑宸ュ叿鐩綍鐪嬩竴鐪?**

```powershell
$dshHome = if ($env:DSH_HOME) { $env:DSH_HOME } else { "$env:USERPROFILE\.dsh" }
explorer "$dshHome\profiles\web\node_modules\dsh-undo-savepoint\tools"
```

涔嬪悗鍙屽嚮妗岄潰銆孌SH鎾ら攢绠＄悊鍣ㄣ€嶅嵆鍙墦寮€灞€澶栧伐鍏?DSH 宕╂簝銆佸惎鍔ㄤ笉浜嗘椂涔熻兘鐢?銆?

## 浣跨敤

- **鎾ら攢**:澶撮儴銆屾挙閿€銆嶆寜閽?/ `Ctrl+Alt+Z` / 瀵?AI 璇?鎾ら攢涓婁竴姝?銆?
- **鎭㈠**:銆屾仮澶嶃€嶆寜閽?/ `Ctrl+Alt+Y`(浠呭綋鎾ら攢鍚庢病鏈夋柊鎿嶄綔)銆?
- **鎵嬪姩淇濆瓨**:闈㈡澘閲屻€屾墜鍔ㄤ繚瀛樸€? 瀵?AI 璇?淇濆瓨蹇収" / CLI `snapshot`銆?
- **鍥為€€鍒版寚瀹氱増鏈?*:闈㈡澘閲岀偣蹇収琛屻€屽洖閫€鍒版鐗堟湰銆?鎴栧 AI 璇?鍥為€€鍒?<id>";鎴?CLI `restore -Id <id>`銆?
- **鍒犻櫎蹇収**:闈㈡澘閲岀偣銆屽垹闄ゃ€?鎴?CLI `remove -Id <id>`銆?
- **鑷畾涔夊揩鎹烽敭**:璁剧疆 鈫?閫氱敤 鈫?鎾ら攢/鎭㈠蹇嵎閿?鐐瑰嚮杈撳叆妗嗗悗鎸夌粍鍚堥敭,Backspace 娓呴櫎)銆?
- **淇濆瓨鍙傛暟**:璁剧疆 鈫?閫氱敤 鈫?蹇収璁剧疆(鑷姩淇濆瓨寮€鍏炽€侀槻鎶栥€佷繚鐣欐暟銆佷袱涓洰褰?鐩綍鏃?馃搧 鎸夐挳鍙墦寮€绯荤粺鐩綍閫夋嫨鍣?銆?

### 灞€澶栧伐鍏?DSH 鎸備簡涔熻兘鐢?

> 鐣岄潰璇█:绋嬪簭绐楀彛鎸夌郴缁?UI 璇█鑷姩鏄剧ず涓枃/鑻辨枃;鍙敤鐜鍙橀噺 `DSH_UNDO_LANG=zh|en` 寮哄埗鎸囧畾銆?

杩涘叆浠撳簱鐩綍鍚?

```powershell
# 绋嬪簭绐楀彛(鎺ㄨ崘):鍙屽嚮 tools\dsh-undo-savepoint-gui.bat,鎴?
powershell -NoProfile -ExecutionPolicy Bypass -File "tools\dsh-undo-savepoint-gui.ps1"

# 鍛戒护琛?
powershell -NoProfile -ExecutionPolicy Bypass -File "tools\dsh-undo-savepoint.ps1" list
powershell -NoProfile -ExecutionPolicy Bypass -File "tools\dsh-undo-savepoint.ps1" snapshot -Label "鍘熷洜"
powershell -NoProfile -ExecutionPolicy Bypass -File "tools\dsh-undo-savepoint.ps1" undo
powershell -NoProfile -ExecutionPolicy Bypass -File "tools\dsh-undo-savepoint.ps1" redo
powershell -NoProfile -ExecutionPolicy Bypass -File "tools\dsh-undo-savepoint.ps1" restore -Id <id> -Force
powershell -NoProfile -ExecutionPolicy Bypass -File "tools\dsh-undo-savepoint.ps1" remove -Id <id>
powershell -NoProfile -ExecutionPolicy Bypass -File "tools\dsh-undo-savepoint.ps1" prune -KeepAuto 20

# 瀹夊叏瑁呮彃浠?鑷姩鍓嶅悗瀛樻。,澶辫触鑷姩鍥為€€)
powershell -NoProfile -ExecutionPolicy Bypass -File "tools\dsh-plugin.ps1" add <鍖呭悕>
```

甯歌浜嬫晠鍦烘櫙:**DSH 鍚姩鎶?`duplicate loader entry id` 涔嬬被閿欒** 鈫?鎵撳紑銆孌SH 鎾ら攢绠＄悊鍣ㄣ€嶉€変腑鍑洪棶棰樺墠鐨勫揩鐓?鈫?鍥為€€ 鈫?閲嶅惎 DSH銆備笉鐢ㄩ噸瑁呫€佷笉涓細璇濄€?

## REST API(WebUI 鐨勫悗绔?

| 绔偣 | 璇存槑 |
|---|---|
| `GET /api/undo/status` | `{canUndo, canRedo, total}` |
| `GET /api/undo/list` | 蹇収鍒楄〃(鍚?location: manual/auto/legacy) |
| `GET/POST /api/undo/settings` | 璇?鍐欎繚瀛樺弬鏁?鑷姩淇濆瓨銆侀槻鎶栥€佷繚鐣欐暟銆佺洰褰?,POST 鍗虫椂鐢熸晥 |
| `POST /api/undo/undo` | 鎾ら攢涓婁竴姝?|
| `POST /api/undo/redo` | 鎭㈠ |
| `POST /api/undo/restore` | body `{id}` 鍥為€€鍒版寚瀹氱増鏈?|
| `POST /api/undo/remove` | body `{id}` 鍒犻櫎蹇収 |
| `POST /api/undo/snapshot` | body `{reason}` 鎵嬪姩淇濆瓨 |
| `POST /api/undo/pick-dir` | 寮瑰嚭绯荤粺鐩綍閫夋嫨鍣?杩斿洖閫変腑璺緞 |

## 璁捐瑕佺偣

- **鎾ら攢璇箟**:鑷姩蹇収鍦ㄥ彉鏇?*涔嬪悗**鐢熸垚,鎵€浠?鎭㈠鏈€鏂板瓨妗?鏄┖鎿嶄綔;鐪熷疄鎾ら攢 = 鍥為€€鍒颁笌褰撳墠鐘舵€?*鍐呭涓嶅悓**鐨勬渶鏂板揩鐓?鍏ㄩ儴鐩稿悓鍒欐槑纭彁绀?娌℃湁鍙挙閿€鐨勫彉鍖?銆?
- **鎾ら攢涓嶄細鎾ら攢鎺夎嚜宸?*:鎭㈠ `cordis.patch.yml` 鍚庤嚜鍔ㄦ鏌ュ苟閲嶆柊鍐欏叆 dsh-undo-savepoint 鎸傝浇鏉°€?
- **鑷姩瀛樻。涓嶈浼ゆ挙閿€**:watcher 璁板綍鎭㈠鎿嶄綔鍐欏叆鐨勫唴瀹瑰搱甯?鎭㈠鍔ㄤ綔鑷繁鐨勬枃浠跺彉鍖栦笉浼氳鑷姩瀛樻。(鍚﹀垯浼氭尅浣?redo);鐪熷疄鍙樻洿鐓у父瀛樻。銆?
- **鏍煎紡浜掗€?*:Node 鎻掍欢涓?PowerShell 宸ュ叿鍏辩敤蹇収浠撳簱涓?manifest 鏍煎紡;Windows PowerShell 5.1 涓?PowerShell 7 鍧囧吋瀹广€?

## 寮€鍙?

- 渚濊禆瑙ｆ瀽:host 鎻掍欢閫氳繃 `createRequire(<DSH瀹夎鏍?/package.json)` 鍔犺浇 `@deepseek-ai/dsh-tools`(鐜鍙橀噺 `DSH_ROOT` 鍙鐩?,鏃犻渶鍦ㄤ粨搴撳唴瀹夎渚濊禆銆?
- 娴嬭瘯(涓嶉渶瑕?DSH 杩愯,鍦ㄤ粨搴撶洰褰曟墽琛?:

```bat
node tools\smoke-test.mjs     :: 29 椤归€昏緫娴嬭瘯(蹇収/鎾ら攢/閲嶅仛/瀛樺偍鍒嗘祦/鏃犲彉鍖栨彁绀?
node tools\e2e-watch.mjs      :: 6 椤圭湡瀹炴椂搴忓洖褰?鑷姩瀛樻。/鎾ら攢涓嶈浼?閲嶅仛)
```
