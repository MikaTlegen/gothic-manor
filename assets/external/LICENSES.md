# Внешние ассеты и лицензии

Исходники лежат здесь без изменений. Обработанные версии генерирует `tools/process_external.py` в `assets/horror/`.

## Звуки — BigSoundBank (автор Joseph Sardin), CC0 1.0
Лицензия: CC0 (public domain), атрибуция не требуется. Источник файла: `https://bigsoundbank.com/UPLOAD/ogg/<id>.ogg`.

| Файл | id | Название на сайте |
|---|---|---|
| audio/steps_stone.ogg | 0606 | Step, shoe on stone staircase |
| audio/steps_wood_a.ogg | 1517 | Steps on a wooden floor #3 |
| audio/steps_wood_b.ogg | 0165 | Man footsteps on the wooden floor |
| audio/run_concrete_a.ogg | 1318 | Fast steps on concrete |
| audio/run_concrete_b.ogg | 0514 | Footsteps, shoe on concrete |
| audio/clock_tick.ogg | 1567 | Grandfather clock, ticking |
| audio/wind_whistle.ogg | 0147 | Whistling of the wind #1 |
| audio/wood_vibration.ogg | 2436 | Wood vibrations |
| audio/beam_creak.ogg | 3426 | Big rope |
| audio/floor_squeak.ogg | 0518 | Floating floor squeaks |
| audio/door_creak.ogg | 0306 | Long creaking door |
| audio/whisper_1.ogg | 3255 | Whisper #1 |
| audio/whisper_2.ogg | 3256 | Whisper #2 |
| audio/heartbeat.ogg | 1929 | Heart beat 4 |
| audio/fireplace.ogg | 0030 | Fireplace 1 |

Гул (drone), стингеры и скрежет камня синтезированы в `tools/process_external.py` — собственная работа.

## Картины — Wikimedia Commons, общественное достояние (Public domain)
Авторы умерли более 100 лет назад; репродукции двумерных работ — PD-Art. Превью 1280 px (окно — 2048 px).

| Файл | Произведение | Файл на Commons |
|---|---|---|
| paintings/saturn.jpg | Ф. Гойя, «Сатурн, пожирающий сына» (1819–1823) | File:Francisco de Goya, Saturno devorando a su hijo (1819-1823).jpg |
| paintings/leocadia.jpg | Ф. Гойя, «Леокадия» | File:La Leocadia (Goya).jpg |
| paintings/witches.jpg | Ф. Гойя, «Шабаш ведьм» (фрагмент) | File:Francisco de Goya y Lucientes - Witches' Sabbath (The Great He-Goat) crop.jpg |
| paintings/nightmare.jpg | И. Г. Фюсли, «Ночной кошмар» (1790–1791) | File:The Nightmare (1790-1791) - Johann Heinrich Füssli.jpg |
| paintings/bocklin.jpg | А. Бёклин, «Автопортрет со смертью, играющей на скрипке» (1872) | File:Arnold Boecklin-fiedelnder Tod.jpg |
| paintings/innocent.jpg | Д. Веласкес, «Портрет Иннокентия X» (1650) | File:Portrait of Innocentius X by Diego Velázquez in Galleria Doria Pamphilj (Rome).jpg |
| paintings/rembrandt.jpg | Рембрандт, «Автопортрет в 63 года» (1669) | File:Rembrandt, Self Portrait at the Age of 63.jpg |
| paintings/lady_blue.jpg | Т. Гейнсборо, «Дама в голубом» | File:Thomas Gainsborough - Portrait of a Lady in Blue - WGA8414.jpg |
| paintings/tetschen.jpg | К. Д. Фридрих, «Крест в горах» (Тетшенский алтарь, 1808) | File:Caspar David Friedrich - Das Kreuz im Gebirge.jpg |
| paintings/abbey.jpg | К. Д. Фридрих, «Аббатство в дубовом лесу» (1809–1810) | File:Caspar David Friedrich - Abtei im Eichwald - Google Art Project.jpg |
| paintings/graveyard.jpg | К. Д. Фридрих, «Монастырское кладбище в снегу» (1817–1819) | File:Friedrich, Caspar David - Klosterfriedhof im Schnee (Farbe).jpg |

## Референсы пользователя (assets/reference/user_refs)
Права подтверждены владельцем проекта (2026-10-05). В игре используются после обработки `tools/process_external.py refs`:

| Реф | Где в игре |
|---|---|
| 2.png, 4.png | вид из окон бельэтажа (`view_photo_north`, `view_photo_west`) |
| 6.png | ладонь и отпечаток на стекле (`hand_slam`, `hand_print`) |
| 10.png, 11.png, 12.jpg | паутина (`cobweb_corner_*`, `cobweb_sheet_*`) |
| 7.png, 8.webp, 9.webp | образцы для моделей Blender (зеркало, статуя, персонаж); в игру не копируются |

5.png (водяной знак Shutterstock) не используется. Звуки скримеров (`painting_fall`, `glass_slam`, `door_slam`,
`inhale_ear`, `shadow_rush`) синтезированы, в `painting_fall` подмешана CC0-запись `wood_vibration`.

## Этап 3 (2026-10-06)
| Файл | Источник | Лицензия |
|---|---|---|
| audio/glass_knock.ogg | BigSoundBank #0320 «Knock on a Glass Door #2» (DavidGreck), bigsoundbank.com | CC0 |
| audio/glass_broken.ogg | BigSoundBank #0771 «Broken glass» (Joseph Sardin), bigsoundbank.com | CC0 |
| персонаж Character_Gentleman | MPFB 2 (MakeHuman, GPL-3.0 — только инструмент) + makehuman_system_assets (кожа, костюм, обувь, волосы, глаза) | CC0 |
| user_refs/15_shadow_figure.png | реф пользователя, права подтверждены владельцем — силуэт тени (`shadow_photo`) | — |

Жуткие варианты картин (`painting_*_creep`) — собственная переработка PD-оригиналов Веласкеса и Гойи;
рефы 13 (Ф. Бэкон, охраняется) и 14 (иллюстрация современного автора) в игру не попадают, только как образец.

## Этап 4 (2026-10-06)
Записи пользователя, источник — Pixabay (подтверждено владельцем проекта), Pixabay Content License:
бесплатно, в том числе в коммерческих играх, атрибуция не требуется. Обработка — `tools/process_external.py stage4`.

| Файл (audio/user) | Автор на Pixabay | В игре |
|---|---|---|
| dragon-studio-slow-cinematic-clock-ticking-357979.mp3 | DRAGON-STUDIO | часы «Своей комнаты» (`clock_user_loop`, 3D) |
| soumages-running-363346.mp3 | soumages | бег преследователя в Game Over (`stalker_run_loop`) |
| ribhavagrawal-heavy-breathing-sound-effect-type-02-294195.mp3 | ribhavagrawal | дыхание преследователя (`stalker_breath`) |
| freesound_community-respiracion-baja-asustada-31479.mp3 | freesound_community | дыхание в склепе (`crypt_breath_loop`, 3D) |
| руки от первого лица FP_Glove_* | MPFB 2 + makehuman_system_assets (кисть, рукав костюма), перчатки — своя текстура | CC0 |

user_refs/16_fp_hand_candle.png — реф позы левой руки над свечой; в игру не копируется.

## Этап 5 (2026-10-06)
### Статуи-сканы — ⚠ CC BY-NC-SA 4.0 (только некоммерческое использование)
| Ассет | Источник | Лицензия |
|---|---|---|
| models/decor/Statue_Angel_Leubner (F1) | «cemetery angel - Leubner», misterdevious, https://sketchfab.com/3d-models/b38e47e47ada4081852557c9ccaf3b71 (архив пользователя `_downloads/cemetery-angel-leubner.zip`) | CC BY-NC-SA 4.0 |
| models/decor/Statue_Angel_Miller (F2) | «cemetery angel - Miller», misterdevious, Sketchfab (архив пользователя `_downloads/cemetery-angel-miller.zip`) | CC BY-NC-SA 4.0 |

Атрибуция: «Cemetery Angel — Leubner» и «Cemetery Angel — Miller» © misterdevious (Sketchfab), CC BY-NC-SA 4.0,
https://creativecommons.org/licenses/by-nc-sa/4.0/. Изменения: срез грунта, масштаб, децимация до ~20 тыс.
треугольников, запечённые нормали, отделённая голова (Miller) — `GothicManorAssets/scripts/build_angels.py`.
Производные модели распространяются под той же лицензией (SA). **NC: в коммерческой версии игры эти статуи
нужно заменить** (решение владельца проекта: пока проект некоммерческий).

### Записи пользователя (Pixabay Content License, подтверждено владельцем проекта)
| Файл (audio/user) | Автор на Pixabay | В игре |
|---|---|---|
| dragon-studio-wooden-walls-creaking-474057.mp3 | DRAGON-STUDIO | скрип открывания двери «Своей комнаты» (`door_creak`, 1.15–3.75 с записи) |
| freesound_community-door-closing-41414.mp3 | freesound_community | захлопнутая дверь, скример 3 (`door_slam`, + низкий удар и хвост зала) |

`glass_slam` пересобран из прежних CC0-записей (#0320 + #0771) с синтезом: резкая атака, щелчок стекла,
дребезг переплёта, низкий удар (`tools/process_external.py stage5`).

### Руки от первого лица — CC BY 4.0
| Ассет | Источник | Лицензия |
|---|---|---|
| models/characters/FP_Glove_Hold_R, FP_Glove_Shield_L (+ textures/fp_arms_*) | «Hands first person view FPS arms», GoldGryphon, https://sketchfab.com/3d-models/hands-first-person-view-fps-arms-50898e9112c54ff38fcdfb0827b27397 (скачан владельцем проекта, `_downloads/hands_first_person_view_fps_arms.zip`) | CC BY 4.0 |

Атрибуция (обязательна, в титрах игры): This work is based on "Hands first person view FPS arms"
(https://sketchfab.com/3d-models/hands-first-person-view-fps-arms-50898e9112c54ff38fcdfb0827b27397) by GoldGryphon
(https://sketchfab.com/GoldGryphon) licensed under CC-BY-4.0 (http://creativecommons.org/licenses/by/4.0/).
Изменения: пальцы согнуты в позы хвата и ладони «лодочкой», предплечье обрезано и окрашено в чёрное сукно,
текстуры уменьшены до 1K — `GothicManorAssets/scripts/build_fp_arms.py`. Коммерческое использование разрешено.

## Этап 6 (2026-10-06)
| Файл | Источник | Лицензия |
|---|---|---|
| audio/glass_strike_door.ogg | BigSoundBank #0198 «Striking at a Glass Door» (Joseph Sardin), bigsoundbank.com | CC0 |
| reference/user_refs/17_glass_silhouette.png | реф пользователя (фигура за матовым стеклом), права подтверждены владельцем — силуэт `glass_silhouette` в скримере окна | — |

`glass_slam` — самый резкий удар из #0198 (stage6) + низкий удар рамы; будет пересобран, когда добавится запись Pixabay.
