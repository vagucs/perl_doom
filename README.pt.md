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

Nesta etapa o programa confere o ponto fixo, lê o IWAD e desenha o `TITLEPIC`. Enter entra no mapa (E1M1, ou MAP01 no Doom 2). As setas viram e andam. Shift corre. O corpo para na parede e escorrega ao longo dela. Um degrau acima de 24 unidades, ou um vão menor que a altura do jogador, também barra. Barris, monstros e itens aparecem no quadro em que nascem. O que é sólido impede o passo. Espaço abre a porta à frente: o teto sobe, a porta normal espera e fecha, e a porta que fica aberta não volta. A trancada abre quando a chave do chão entra no bolso. Passar por cima recupera vida, junta bala e veste armadura. A armadura absorve parte do dano. A grade deixa ver o outro lado, e quem está atrás fica atrás das barras. Ctrl dispara a arma da mão. A pistola recua e gasta uma bala. O que está na frente perde vida, se encolhe ou cai. Um barril estoura. O zumbi, o imp e o demônio acordam quando vêem o jogador: andam até ele, o zumbi atira, o imp joga a bola de fogo e o demônio morde de perto. A tecla 1 volta para a pistola, a 2 escolhe a espingarda e a 3 escolhe a metralhadora. Ctrl dispara a arma da mão: a espingarda gasta um cartucho e espalha sete balas. A metralhadora gasta uma bala por tiro e segue enquanto Ctrl estiver preso. A tecla 4 escolhe o lança-foguetes, que sai do chão. Cada tiro gasta um foguete e ele explode ao bater. A tecla 5 escolhe o rifle de plasma, que sai do chão no Doom 2. Cada tiro gasta uma célula e lança uma bola que queima ao bater. A tecla 6 escolhe a BFG, também no Doom 2. Cada tiro gasta 40 células, solta a bola grande e a explosão varre quem está na frente. A tecla 7 é a serra, a 8 a super espingarda e a 9 o punho. Na fase, iddqd, idkfa, idfa, idclip, idspispopd, idchoppers, idclev, idmus, iddt e idbehold estão ligados. No chão, a esfera de invulnerabilidade, o berserk, a invisibilidade, o traje, o mapa e o visor de luz entram no bolso. A linha de teleporte leva até o marcador, com névoa e a cara virada para a saída. A que dispara uma vez some; a repetida continua no lugar. A parede da linha 48 desliza o desenho para o lado o tempo todo. Ao correr de uma plataforma alta para outra, o corpo cai aos poucos e ainda alcança o piso do outro lado. Atravessar a linha 2 abre a porta e ela fica aberta, a 3 fecha e a 4 abre e depois fecha. A linha 8 sobe uma escada: o piso marcado sobe, e cada sala ao lado com o mesmo chão sobe mais um degrau. A linha 100 faz a mesma escada, com degraus mais altos e mais depressa. A linha 10 desce o piso até o vizinho mais baixo, espera e sobe de volta. A linha some depois. Os outros pisos, tetos, esmagadores, elevadores, escadas e luzes das linhas do mapa também andam. O título abre o menu. Em opções, a resolução muda o tamanho da janela e o tamanho da tela muda a vista. As teclas - e + mudam o tamanho da tela. Alt abre o strafe, a vírgula e o ponto andam de lado, e o mouse vira e olha. Pause pausa. O pesadelo acelera os monstros e os faz renascer. A mochila também enche cartucho, foguete e célula. Uma porta fechada, vista de um piso mais baixo, continua escondendo o monstro que está atrás. O tiro, a porta, o item e o monstro fazem som. O título e o mapa tocam a música. A barra embaixo mostra vida, munição, armadura, rosto e chaves. O interruptor de saída muda de imagem. O piso desce ao cruzar a linha, e o elevador desce e sobe. O lodo tira vida e as luzes piscam. No fim da fase a contagem abre o mapa seguinte, com a vida, a munição e a armadura. Na segunda fase o interruptor abre a porta e o elevador, e um tiro na parede também abre caminho. A tela derrete entre o fim da fase e o mapa seguinte. No fim do episódio a história aparece no piso, a imagem seguinte entra, e uma tecla volta ao título. No episódio 3 o coelho atravessa a tela e leva os tiros. No Doom 2 o texto entre fases segue o jogo, e o mapa 30 abre o desfile de monstros. Um tiro acorda os monstros da sala, mesmo sem acertar. A primeira porta do segundo mapa do Doom 2 abre ao passar por cima. O interruptor da ante-sala abaixa o piso e a passagem abre. Tab mostra o mapa das paredes já vistas, e + e - aproximam. Enter no título abre a dificuldade: no mais fácil o dano cai pela metade e a pistola começa com o dobro de balas; no pesadelo os monstros atiram mais seguido. No Doom registrado a escolha do episódio vem antes. F2 grava a partida e F3 carrega, em seis vagas. Esc, ou fechar a janela, sai.

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
