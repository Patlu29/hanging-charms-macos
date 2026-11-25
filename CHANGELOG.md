# Changelog

## 1.1.0

### Hanging
- **Hang from** the menu bar, the camera notch, the top of the front window (the rope
  swings as you move the window), or anywhere on screen.
- **Drag the top of the rope** to hang it somewhere new; it stays pinned there.
- **Breeze:** still, gentle or windy, an idle sway that never repeats in an obvious loop.
  Reduce Motion calms it.

### Hooks and grapples
- No more yellow ring on every charm. Each charm hangs from a **tied knot** by default,
  or an **S-hook**, **fish hook**, **lobster clasp**, **carabiner** or **jump ring**, in a
  finish that matches the rope or is gold, silver, rose gold, bronze or black, at any size.
- The top of the rope hangs from a **grappling hook** by default, or a **pin**, **nail**,
  **binder clip**, **suction cup** or nothing, with its own finish and size.

### Rope
- **Thread thickness** from 25% to 600% of the style's width, with a thinner minimum line.
- **Link and twist size**, and **beads** along the cord (none, a few, many) with their own
  colour and size.

### Customisation
- **Chain and cord:** your own main and detail colours, and a pattern of your choice
  (twisted, braided, chain links, lit filament or fine silk) on any rope.
- **Light:** glow colour matched to the charm or one you pick, brightness, size, slow
  breathing on or off, and a glow along the cord on any rope.
- **Charm size:** each charm on the rope has its own size, set from the Library or from
  Appearance › Charms. A larger charm is heavier too. Drop shadows can be turned off.
- **Motion:** swing weight, settle speed, and how far below the menu bar the rope hangs.
- Appearance is split into Rope, Hooks, Hanging, Light, Charms, Motion and System tabs.

### Fixes
- A held charm stays under the pointer. The grab used to be fixed in screen space while
  the charm turned with the rope, so the charm slid away from the pointer as you dragged.
- Reaching for a charm no longer pushes it away. The pointer now knocks a charm only on a
  quick pass, once per pass, and adds to its swing rather than stopping it.
- Hover tracking no longer stops once the pointer reaches a charm, a swinging charm can
  be caught under a still pointer, and a click where the charm used to be goes through
  to the app underneath.
- A quick flick through a charm now knocks it even if the pointer had been resting.

### Testing
- `--self-test` drives the real overlay with synthetic mouse events (46 checks: hover,
  grab, drag, throw, flick, every hook, grapple, rope style and hanging mode, grapple
  dragging, breeze, visibility and sleep). CI runs it on every push.

## 1.0.0

- First release: Verlet rope at a fixed 240 Hz, up to three charms per rope, nine rope
  styles, 50 original charms in 8 collections, custom charms from photos with Vision
  cut-out, chimes, glow, pointer-reactive and time-of-day motion, full-screen hiding,
  open at login, and a menu bar app with a Customize window.
