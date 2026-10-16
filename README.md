# perl_doom

![DOOM running in Perl with SDL2](screenshot/doom.png)

**Video:** [DOOM running in Perl](https://youtu.be/VN-lWDOsYrg)

**Repository:** [github.com/vagucs/perl_doom](https://github.com/vagucs/perl_doom)

DOOM generic ported from **[python_doom](https://github.com/vagucs/python_doom)** to **Perl 5.44 + SDL2**.

By **Wagner Nunes da Silva**

- vagucs@bol.com.br
- vagucs@vagucs.com.br
- vagucs@gmail.com
- [www.vagucs.com.br](https://www.vagucs.com.br)
- [LinkedIn](https://www.linkedin.com/in/wagner-nunes-da-silva-b0a15360)

The game stays in Perl. `SDL2.dll` opens the window. This port has no C source of its own. This step reads an IWAD, shows the title picture, and enters the E1M1 view. Map things appear, walls hold the player back, Space opens a door, a grate shows what is behind it, and Ctrl fires the pistol. A monster sees, walks, and fights back. Health, ammo, armor, keys, and the shotgun leave the floor.

Versão em português: [README.pt.md](README.pt.md)

---

## What this project is

`python_doom` is a condensed, playable DOOM engine in Python. This directory starts the **same study piece**, in Perl:

- Window and keys: **SDL2**, reached through `Win32::API` (cdecl). The engine does not live in that bridge
- Framebuffer: 320×200, stretched to a 640×400 window
- 16.16 fixed-point: `Doom/Compat.pm`, the same math as `doom/compat.py`. A Perl integer is 8 bytes
- IWAD: `Doom/Wad.pm`

You need a legal IWAD (shareware `doom1.wad` or commercial `doom.wad` / `doom2.wad`). This repository does not ship commercial WAD data.

---

## Educational purpose

The Python port already dropped the preprocessor and Harbour's 1-based arrays. The Perl port asks what changes when the lists stay 0-based and the 32-bit math fits in an 8-byte integer, with no C file.

- **Python, then Perl.** Open `python_doom/doom/` next to `perl_doom/Doom/`.
- **Wrap, written down.** `as_i32` brings a 16.16 product back to 32 bits.
- **Where Perl is enough.** The WAD directory, the patch, and the loop stay in Perl. SDL2 is the window.

---

## From Python to Perl

| Python (`python_doom`) | Perl (`perl_doom`) |
| --- | --- |
| `thing.x` | `$thing->{x}` |
| `None` | `undef` |
| `items[0]` | `$items[0]` |
| class | `package` and a blessed hash |
| unbounded `int` | 8-byte integer; `as_i32` cuts it to 32 bits |
| `fixed_mul` | `fixed_mul` |
| framebuffer `bytearray` | a byte string |
| pygame | SDL2 through `Win32::API` |

---

## Technology

| Layer | This port | Python (`python_doom`) |
| --- | --- | --- |
| Language | Perl 5.44, `C:\msys64\ucrt64\bin\perl.exe` | Python 3.10+ |
| Window | SDL2, `Win32::API` | pygame 2.x |
| 16.16 fixed-point | `Doom/Compat.pm` | `doom/compat.py` |
| IWAD | `Doom/Wad.pm` | `doom/wad.py` |

The Cygwin Perl (`C:\msys64\usr\bin\perl.exe`) does not fit: it must not load this `SDL2.dll`. `run.bat` puts `C:\msys64\ucrt64\bin` at the front of `PATH`.

---

## How to run

From this directory, on Windows:

```
run.bat
run.bat -fps -novsync
```

`-iwad` chooses the file. A bare path ending in `.wad` also works. `-fps` draws the frames per second in the upper right. `-novsync` presents without waiting for the monitor.

The IWAD search starts at `DOOMWADDIR` or `DOOMWADPATH` when that variable is set, then the current folder, this program's folder, and the parent folders. The shareware `DOOM1.WAD` in the parent folder is on that list.

---

## Keys

| Key | Action |
| --- | --- |
| **Enter** | Confirm the menu item |
| **Left / right arrow** | Turn |
| **Up / down arrow** | Walk. Shift runs |
| **Space** | Open the door ahead |
| **Ctrl** | Fire the gun in hand |
| **1** | Pistol |
| **2** | Shotgun |
| **- / +** | Screen size |
| **Esc** | Opens the menu. On the title, quits |
| **Alt+Enter** | Full screen |
| **Alt** | Strafe |
| **, / .** | Sidestep |
| **Mouse** | Turn and look. Button fires |
| **Pause** | Pause |
| Close the window | Quit |

---

## Layout

```
main.pl              entry, title, view, collision, things, doors, and shots
Doom/Compat.pm       doom/compat.py
Doom/Wad.pm          doom/wad.py
Doom/Tables.pm       doom/tables.py
Doom/RData.pm        doom/r_data.py
Doom/World.pm        doom/world.py
Doom/Collision.pm    doom/collision.py
Doom/Render.pm       doom/render.py
Doom/Info.pm         doom/info.py
Doom/Sprites.pm      doom/sprites.py
Doom/Specials.pm     manual doors from doom/specials.py
Doom/Attack.pm       pistol from doom/player.py
Doom/Enemy.pm        monsters from doom/enemy.py
Doom/Pickups.pm      floor items from doom/mobj.py
Doom/Sound.pm        effects and music from doom/sound.py
Doom/Status.pm       bar from doom/status.py
Doom/Wi.pm           tally from doom/wi_stuff.py
Doom/Wipe.pm         melt from doom/wipe.py
Doom/Finale.pm       story from doom/finale.py
Doom/Automap.pm      Tab map from doom/am_map.py
Doom/Menu.pm         difficulty from doom/menu.py
Doom/Save.pm         save and load from doom/saveg.py
Doom/Mus.pm          MUS to MIDI from doom/mus2mid.py
Doom/VVideo.pm       doom/v_video.py
Doom/Video.pm        SDL2 window
Doom/Defs.pm         screen size and FRACUNIT
run.bat              UCRT64 Perl 5.44
```

---

## Lineage

1. **[python_doom](https://github.com/vagucs/python_doom)** — Python + pygame
2. **[perl_doom](https://github.com/vagucs/perl_doom)** — Perl 5.44 + SDL2 (this tree)

---

## Donate

### GitHub Sponsors

[github.com/sponsors/vagucs](https://github.com/sponsors/vagucs)

### Ethereum

`0x1b64038A2b1DB73ABd0068d8B9B0d1dC5a90C5F1`

![Ethereum QR Code](docs/qr-ethereum.png)

### PIX

Key: `vagucs@bol.com.br`

![PIX QR Code](docs/qr-pix.png)
