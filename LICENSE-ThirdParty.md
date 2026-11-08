# Third-party notices

## Improved Forever

PadForge's button glyph atlas lists (Pad.lua) come from Improved Forever, and several
techniques are adapted from it: reading the gamepad focus from
`GamepadSharedUtility.InputBindingManager`, passing trigger layers to the crossbar by
clicking its named buttons, picking a wheel slot from `GetGamePadState()` in secure code,
taking the sticks with `EnableGamePadStick` while a wheel is up, and fading the game's
frames with an animation instead of setting their properties.

https://github.com/markgravity/ImprovedForever

```
MIT License

Copyright (c) 2026 markg

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

## Easy Controller - Forever

Improved Forever credits parts of its code to Easy Controller - Forever by moust4ki (MIT);
the override-binding approach PadForge uses for presses descends from it.
https://www.curseforge.com/wow/addons/easy-controller-forever

