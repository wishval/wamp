# Next session — 2026-04-14

Wamp, macOS/Swift/AppKit, Winamp clone, working directory
  `/Users/valerijbakalenko/Documents/Stranger/Code/AI/WinampMac`.

Just shipped:
- Confirmed EQ presets DO change audio — the issue was persisted `eqEnabled: false` bypassing the entire AVAudioUnitEQ node. No code fix needed; saved state corrected.
- Spectrum analyzer dotted scale line moved into SpectrumView with `masksToBounds` clipping so it no longer extends 2px beyond the view bounds.

Known concern: P3 wide-gamut MacBook displays render sRGB greens/reds slightly more vivid than standard sRGB monitors. This is inherent to macOS color management and not fixable without breaking colors on other displays.

Next tasks:
Доработать скины — чтобы скины адекватно вставали везде на свои позиции и все стили подтягивались адекватно. Из прям видимых текущих проблем:
- Иконка меню в левом верхнем углу приложения игнорирует клики.
- График в эквалайзере рисуется очень странно.
- Вообще практически всё кроме кнопок в секции эквалайзера выглядит очень криво.
- Часть приложения под плейлистом тоже полностью не рабочая.
