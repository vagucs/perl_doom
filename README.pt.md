# perl_doom

![DOOM rodando em Perl com SDL2](screenshot/doom.png)

**Vídeo:** [DOOM rodando em Perl](https://youtu.be/VN-lWDOsYrg)

**Repositório:** [github.com/vagucs/perl_doom](https://github.com/vagucs/perl_doom)

DOOM generic portado de **[python_doom](https://github.com/vagucs/python_doom)** para **Perl 5.44 + SDL2**.

Por **Wagner Nunes da Silva**

- vagucs@bol.com.br
- vagucs@vagucs.com.br
- vagucs@gmail.com
- [www.vagucs.com.br](https://www.vagucs.com.br)
- [LinkedIn](https://www.linkedin.com/in/wagner-nunes-da-silva-b0a15360)

O jogo fica em Perl. A `SDL2.dll` abre a janela. Não há fonte C neste porte. Esta etapa abre o IWAD, mostra o título e entra na vista do E1M1. As coisas do mapa aparecem, a parede segura o passo, Espaço abre a porta, a grade mostra o que está atrás, e Ctrl dispara a pistola. O monstro vê, anda e revida. Vida, munição, armadura, chave e espingarda saem do chão.

English version: [README.md](README.md)

---

## O que é este projeto

`python_doom` é um motor de DOOM condensado e jogável, em Python. Este diretório começa a **mesma peça de estudo**, em Perl:

- Janela e teclas: **SDL2**, chamada pelo `Win32::API` (cdecl). O motor não entra nessa ponte
- Framebuffer: 320×200, esticado numa janela de 640×400
- Ponto fixo 16.16: `Doom/Compat.pm`, a mesma conta de `doom/compat.py`. O inteiro do Perl tem 8 bytes
- IWAD: `Doom/Wad.pm`

É preciso um IWAD legal (shareware `doom1.wad` ou comercial `doom.wad` / `doom2.wad`). Este repositório não traz WAD comercial.

---

## Proposta educacional

O port em Python já tirou o pré-processador e os arrays 1-based do Harbour. O port em Perl pergunta o que muda quando a lista continua 0-based e a conta de 32 bits cabe num inteiro de 8 bytes, sem arquivo C.

- **Python, depois Perl.** Abra `python_doom/doom/` ao lado de `perl_doom/Doom/`.
- **Estouro escrito.** `as_i32` devolve o produto 16.16 para 32 bits.
- **Onde o Perl basta.** O diretório do WAD, o patch e o laço ficam em Perl. A SDL2 é a janela.

---

## De Python para Perl

| Python (`python_doom`) | Perl (`perl_doom`) |
| --- | --- |
| `thing.x` | `$thing->{x}` |
| `None` | `undef` |
| `items[0]` | `$items[0]` |
| classe | `package` e um hash abençoado |
| `int` sem limite | inteiro de 8 bytes; `as_i32` corta em 32 |
| `fixed_mul` | `fixed_mul` |
| framebuffer `bytearray` | string de bytes |
| pygame | SDL2 pela `Win32::API` |

---

## Tecnologia

| Camada | Este port | Python (`python_doom`) |
| --- | --- | --- |
| Linguagem | Perl 5.44, `C:\msys64\ucrt64\bin\perl.exe` | Python 3.10+ |
| Janela | SDL2, `Win32::API` | pygame 2.x |
| Ponto fixo 16.16 | `Doom/Compat.pm` | `doom/compat.py` |
| IWAD | `Doom/Wad.pm` | `doom/wad.py` |

O Perl do Cygwin (`C:\msys64\usr\bin\perl.exe`) não serve: ele não deve carregar esta `SDL2.dll`. O `run.bat` coloca `C:\msys64\ucrt64\bin` no começo do `PATH`.

---

## Como rodar

Neste diretório, no Windows:

```
run.bat
run.bat -fps -novsync
```

`-iwad` escolhe o arquivo. Um caminho solto terminado em `.wad` também serve. `-fps` mostra os quadros por segundo no canto superior direito. `-novsync` apresenta sem esperar o monitor.

A busca do IWAD começa em `DOOMWADDIR` ou `DOOMWADPATH`, se a variável existir, e segue pela pasta atual, pela pasta deste programa e pelas pastas acima. O shareware `DOOM1.WAD` da pasta pai entra nessa lista.

---

## Teclas

| Tecla | Ação |
| --- | --- |
| **Enter** | Confirma o item do menu |
| **Seta esquerda / direita** | Virar |
| **Seta cima / baixo** | Andar. Shift corre |
| **Espaço** | Abrir a porta à frente |
| **Ctrl** | Disparar a arma da mão |
| **1** | Pistola |
| **2** | Espingarda |
| **- / +** | Tamanho da tela |
| **Esc** | Abre o menu. No título, sai |
| **Alt+Enter** | Tela cheia |
| **Alt** | Andar de lado |
| **, / .** | Passo lateral |
| **Mouse** | Virar e olhar. Botão dispara |
| **Pause** | Pausa |
| Fechar a janela | Sair |

---

## Organização

```
main.pl              entrada, titulo, vista, colisao, coisas, porta e tiro
Doom/Compat.pm       doom/compat.py
Doom/Wad.pm          doom/wad.py
Doom/Tables.pm       doom/tables.py
Doom/RData.pm        doom/r_data.py
Doom/World.pm        doom/world.py
Doom/Collision.pm    doom/collision.py
Doom/Render.pm       doom/render.py
Doom/Info.pm         doom/info.py
Doom/Sprites.pm      doom/sprites.py
Doom/Specials.pm     porta manual de doom/specials.py
Doom/Attack.pm       pistola de doom/player.py
Doom/Enemy.pm        monstro de doom/enemy.py
Doom/Pickups.pm      itens do chao de doom/mobj.py
Doom/Sound.pm        efeitos e musica de doom/sound.py
Doom/Status.pm       barra de doom/status.py
Doom/Wi.pm           fim de fase de doom/wi_stuff.py
Doom/Wipe.pm         derretimento de doom/wipe.py
Doom/Finale.pm       historia de doom/finale.py
Doom/Automap.pm      mapa do Tab de doom/am_map.py
Doom/Menu.pm         dificuldade de doom/menu.py
Doom/Save.pm         gravar e carregar de doom/saveg.py
Doom/Mus.pm          MUS para MIDI de doom/mus2mid.py
Doom/VVideo.pm       doom/v_video.py
Doom/Video.pm        janela SDL2
Doom/Defs.pm         tela e FRACUNIT
run.bat              Perl 5.44 do UCRT64
```

---

## Linhagem

1. **[python_doom](https://github.com/vagucs/python_doom)** — Python + pygame
2. **[perl_doom](https://github.com/vagucs/perl_doom)** — Perl 5.44 + SDL2 (esta árvore)

---

## Doe

### Patrocínio no GitHub

[github.com/sponsors/vagucs](https://github.com/sponsors/vagucs)

### Ethereum

`0x1b64038A2b1DB73ABd0068d8B9B0d1dC5a90C5F1`

![QR Code Ethereum](docs/qr-ethereum.png)

### PIX

Chave: `vagucs@bol.com.br`

![QR Code PIX](docs/qr-pix.png)
