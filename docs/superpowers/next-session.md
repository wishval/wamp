# Next session — 2026-04-14

Wamp, macOS/Swift/AppKit, Winamp clone, working directory `/Users/valerijbakalenko/Documents/Stranger/Code/AI/WinampMac`.

Just shipped (feature/skin-fixes-2):
- Fixed skinned playlist bottom-button hit rects using positions measured from pledit.bmp (ADD/REM/SEL/MISC at x=11/40/69/98, AppKit y=10..28) and added LIST OPTS click target at (w-42, 16, 20, 18).
- Rewrote the EQ slider sprite mapping: eqSliderThumb is a single sprite (not 14 variants); eqSliderBackground now has 14 position variants at x=13+p*15 with the authentic green→red gradient baked in. Dropped the programmatic 19-stop fill.
- Nullsoft swoosh baked into main.bmp is now a clickable hit-zone at (249, 12, 18, 15) that opens https://github.com/wishval/wamp.

Known concerns: none of the above was visually verified in a running app — user should launch and confirm each playlist button clicks, EQ sliders look right, and the logo link opens.

Next tasks:
- Разобраться с футером плейлиста — как он хранится в теме. Убрать кнопку MISC. Починить кнопку LIST OPTS (сейчас не работает).
- В поле между MISC и LIST OPTS показывается «tracks / total duration» — текст не влазит. Уменьшить шрифт и убрать секунды из длительности.
- Под этим полем в BR corner есть мини-кнопки управления плеером и поле с двоеточием (предположительно для current playback time) — всё это убрать, не нужно.
