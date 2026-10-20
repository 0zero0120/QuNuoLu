# 素材与致谢

本项目的程序、数据与素材来源如下。第三方素材均遵循其原始许可。

- 程序代码：[MIT License](LICENSE)
- 自产美术、音频、文案与数据资源：[素材许可说明](LICENSE-ASSETS)（保留所有权利）

## 引擎与工具

- **Godot Engine 4.6.1** — MIT License — https://godotengine.org
- **Funplay MCP for Godot 0.9.3**（FunplayAI）— MIT License — 开发期编辑器辅助插件，随源码保留；运行时只向 `user://` 写入界面状态，不联网。https://github.com/FunplayAI/funplay-godot-mcp

## 背景音乐

游戏内 `assets/audio/bgm/main_theme.ogg` 为 120 秒无缝循环曲，只使用下列真录音片段拼接。没有使用合成器、电子鼓或人声。

所有片段均做过裁剪、变调/变速、EQ、淡入淡出、循环拼接与响度归一。混响为卷积空间处理，不属于乐器音色。

| 用途 | 作者 / 素材 | 来源 | 许可 |
| --- | --- | --- | --- |
| 古筝 | xserra — GuZheng | https://freesound.org/people/xserra/sounds/162088/ | CC BY 4.0 |
| 古琴 | RafaelCaro — Guqin-song (Mei Hua San Nong) | https://freesound.org/people/RafaelCaro/sounds/176265/ | CC BY 4.0 |
| 箫 | xserra — xiao-2 | https://freesound.org/people/xserra/sounds/161911/ | CC BY 4.0 |
| 埙 | franeknflute — Xun Sample.wav | https://freesound.org/people/franeknflute/sounds/200419/ | CC BY 4.0 |
| 铜钟 | the_very_Real_Horst — Chinese Dragon Tempel Bell VI cross-fade | https://freesound.org/people/the_very_Real_Horst/sounds/241069/ | CC0 1.0 |
| 战鼓 | RTB45 — Drums of Xian, China | https://freesound.org/people/RTB45/sounds/234922/ | CC BY 4.0 |
| 大鼓鼓边 | sazanami12 — Chinese Bass Drum Dagu Rim Shot | https://freesound.org/people/sazanami12/sounds/856560/ | CC0 1.0 |
| 锣 | kevp888 — CD_VIE_007FX_Gong_1 / 008FX_Gong_2 / 009FX_Gong_3 | https://freesound.org/people/kevp888/sounds/710378/ · https://freesound.org/people/kevp888/sounds/710557/ · https://freesound.org/people/kevp888/sounds/710760/ | CC BY 4.0 |
| 山风 | kyles — mountain wind heavy strong gusts Swiss Alps | https://freesound.org/people/kyles/sounds/454092/ | CC0 1.0 |

**编钟说明**：没有使用真编钟合奏录音。曲中的编钟声由上述真铜钟（241069）按音高重采样得到八个音（D3、A3、D4、G4、F4、A4、C5、D5），音色来自真铜钟，但不是编钟合奏实录。

授权文本：CC BY 4.0 — https://creativecommons.org/licenses/by/4.0/ ；CC0 1.0 — https://creativecommons.org/publicdomain/zero/1.0/

`assets/audio/bgm/ambience.ogg` 为项目早期生成的环境风声层，仍作为局内底噪使用。

## 音效

`assets/audio/sfx/` 下的战斗与界面音效由 **Stable Audio 3** 生成，经裁剪与响度归一处理。

## 美术

角色立绘、敌人立绘、卡面插画、遗物/药水/成就图标与界面背景，均由作者使用本地部署的 Stable Diffusion 模型（含 GuoFeng、幻墨等社区模型及水墨风格 LoRA）生成，再经筛选、抠图、调色与排版处理。生成图不含第三方商业素材；模型本身的许可遵循其发布页条款。

## 字体

- **Ma Shan Zheng**（马善政毛笔楷书）— SIL Open Font License 1.1 — Google Fonts：https://fonts.google.com/specimen/Ma+Shan+Zheng

## 其他

游戏中的卡牌、遗物、敌人、事件名称与文本，部分取材自《周礼·夏官·方相氏》《后汉书·礼仪志》所载大傩仪，以及《山海经》等公有领域典籍。
