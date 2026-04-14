# Next session — 2026-04-15

Wamp, macOS/Swift/AppKit, Winamp clone, working directory `/Users/valerijbakalenko/Documents/Stranger/Code/AI/WinampMac`.

Just shipped (feature/playlist-footer-cleanup):
- Skinned playlist footer: disabled MISC click (baked sprite stays visible but inert), fixed LIST OPTS hit rect using measured pledit.bmp pixels (w-45, 12, 23, 18), masked the unused mini-transport row and ":"-timer baked into the BR corner.
- Running-time label shortened to "N / H:MM" — added PlaylistManager.formattedTotalDurationCompact with a unit test. Applied to both skinned sprite-text path and the unskinned NSTextField.

Known concerns: changes were not visually verified in a running app — user should launch and confirm LIST OPTS opens the menu, MISC click is inert, the masked BR area looks clean, and the new "N / H:MM" text fits the LCD.

Next tasks:
- В оригинальную (unskinned) версию добавить кнопку MISC с полным функционалом из оригинала, и оживить её при подключении скинов.
- EQ-график сейчас гладкий — попробовать сделать его пиксельным, как в оригинале.
- Очень важно: когда подключается скин, EQ-график должен тянуть свои цвета из скина (в оригинале Winamp это делает через eqmain.bmp / PLEDIT.TXT / region.txt — найти точный источник). Сейчас во всех скинах используется один и тот же цвет.
