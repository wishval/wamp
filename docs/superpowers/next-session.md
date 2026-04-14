# Next session — 2026-04-14

Wamp, macOS/Swift/AppKit, Winamp clone, working directory
  `/Users/valerijbakalenko/Documents/Stranger/Code/AI/WinampMac`.

Just shipped (feature/skin-polish):
- Window dragging in skinned mode (MainPlayer/EQ/Playlist title areas) and menu icon hit zone in the top-left.
- EqualizerView gained a layoutSkinned() with exact Webamp coordinates; EQ response curve now draws a center line and hue-colored Catmull-Rom spline; EQ band sliders draw the 19-stop palette fill in skinned mode.
- Playlist bottom buttons re-implemented via direct mouseDown hit-testing (NSClickGestureRecognizer on invisible NSViews didn't fire).

Known concerns:
- The mouseDown hit-test for ADD/REM/SEL/MISC may still be intercepted by the scrollView or pledit corner-sprite area — needs investigation when the new session starts (verify hitTest order, consider overriding hitTest(_:) instead of mouseDown).

Next tasks:
- Кнопки add, rem, sel, misc, list opts до сих пор не нажимаются.
- EQ-ползунки очень отличаются стилистически от скина; сами перетаскивающиеся ползунки (thumbs) вообще не получили скин — они должны быть такими же, как ползунки звука или баланса (sprite-based из eqmain.bmp).
- Справа от кнопки повтора в скине есть иконка — она должна быть кликабельной и вести на https://github.com/wishval/wamp.
