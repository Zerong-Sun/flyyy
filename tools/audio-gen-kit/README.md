# Audio Gen Kit — 《环球航商》Demo 音频

程序合成 + 可选 CC0 拉取，输出到 `game/assets/audio/`。

## 依赖

```bash
pip install -r requirements.txt   # numpy
# 系统需安装 ffmpeg（用于 WAV→Ogg Vorbis）
```

## 生成 Demo 包（P0）

```bash
# 从仓库根目录
python3 tools/audio-gen-kit/synthesize_demo_audio.py
```

产出：

- `game/assets/audio/bgm/audio_bgm_globe_day.ogg`
- `game/assets/audio/sfx/audio_sfx_*.ogg`（§2.3 P0 全项）
- `game/assets/audio/AUDIO_MANIFEST.csv`

## 可选：CC0 UI 音效

```bash
python3 tools/audio-gen-kit/fetch_cc0_ui.py
# 再跑 synthesize（会优先使用已下载的 CC0 文件覆盖 UI 类条目）
python3 tools/audio-gen-kit/synthesize_demo_audio.py --prefer-cc0
```

网络失败时自动回退程序合成，`source=procedural`。

## 气质与外包提示

见 [AUDIO_PROMPTS.md](AUDIO_PROMPTS.md)。
