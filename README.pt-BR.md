# J4 Home Server

Transforme um celular Android antigo e travado em um **pequeno servidor doméstico privado**: nuvem pessoal,
bloqueador de anúncios por DNS e controle remoto pelo Telegram, usando só [Termux](https://termux.dev),
[Tailscale](https://tailscale.com) e algumas centenas de linhas de shell e Python.
**Sem root, sem desbloquear o bootloader, sem abrir portas.**

Foi feito em um Samsung Galaxy J4 (SM-J400M: Android 10, ARM de 32 bits, 1,8 GB de RAM, sem cartão SD), que é quase o
pior caso para um servidor. Então deve rodar na maioria dos celulares parados que sejam melhores que ele.
A parte mais valiosa do repositório não é o código: é a **lista do que quebra no Android antigo e como contornar**
([docs/11](docs/11-android10-pitfalls.md), em inglês).

> A documentação está em inglês ([README.md](README.md) e `docs/`). As mensagens do bot e a maioria dos comentários do
> código estão em português do Brasil. Traduções são bem-vindas ([CONTRIBUTING](CONTRIBUTING.md)).

## O que você ganha

| Peça | O que faz | Doc |
|---|---|---|
| **Debloat** | Remove apps do Google, da Samsung e da operadora para o usuário 0, por `adb` (reversível), para a pilha inteira caber em cerca de 910 MB dos 1,84 GB | [02](docs/02-debloat.md) |
| **Termux + inicialização** | Tudo sobe no boot com Termux:Boot e wake lock | [03](docs/03-termux.md), [04](docs/04-ssh-and-autostart.md) |
| **Tailscale** | Rede privada + certificados HTTPS, em modo userspace (sem VPN, sem root) | [05](docs/05-tailscale.md) |
| **Nuvem** | Servidor de arquivos [dufs](https://github.com/sigoden/dufs) (WebDAV, busca, zip) atrás do `tailscale serve` | [06](docs/06-dufs-cloud.md) |
| **Interface web** | UI responsiva em um arquivo só: grade/lista, visualizador de vídeo e imagem, arrastar pastas, renomear/mover, painel de armazenamento, tema claro/escuro | [07](docs/07-web-ui.md) |
| **Bot do Telegram** | `/status`, `/foto` (câmera), `/tocar`, `/despertador`, `/dns`, `/parar`; só responde a você | [08](docs/08-telegram-bot.md) |
| **Despertador** | Programe alarmes pelo Telegram; o celular toca até você mandar `/parar` | [09](docs/09-alarm-clock.md) |
| **Bloqueador de anúncios** | ~76 mil domínios servidos como DNS sobre TLS no seu tailnet, para o *DNS privado* do Android, com vigia | [10](docs/10-dns-adblocker.md) |
| **Ferramentas** | Rodar scripts dentro do Termux pelo PC via `adb` (sem SSH), testes offline | [13](docs/13-deploying-from-a-pc.md) |

## Começo rápido

Você precisa de um PC com `adb`, um celular Android com depuração USB, uma conta gratuita do Tailscale e, se quiser o bot,
um token de bot do Telegram. Os detalhes e todas as armadilhas estão nos documentos numerados:

1. [Prepare o celular](docs/01-prepare-the-phone.md) (depuração USB, F-Droid, Termux, Termux:Boot, Termux:API).
2. *(opcional, agressivo)* [Debloat](docs/02-debloat.md): `debloat/debloat.sh --dry-run`, leia a lista e só então rode.
3. [Pacotes do Termux e scripts de boot](docs/03-termux.md), [SSH](docs/04-ssh-and-autostart.md), [Tailscale](docs/05-tailscale.md).
4. Instale as peças que quiser, a partir do PC (o celular precisa estar acordado):
   ```sh
   tools/adb-run.sh install/cloud.sh      # dufs + interface (mostra uma senha aleatória uma vez, na tela do celular)
   tools/adb-run.sh install/tgbot.sh      # bot do Telegram (crie ~/.tgbot/config antes, veja docs/08)
   tools/adb-run.sh install/dnsblock.sh   # bloqueador de anúncios (+ tailscale serve na :853)
   ```
5. Rode os testes offline quando quiser: `make test`.

## Estado: o que foi e o que não foi verificado

É um projeto pessoal que funciona em **um aparelho** (o J4 do autor).

- **Verificado no aparelho:** nuvem + interface por HTTPS do Tailscale, SSH, comandos do bot usados no dia a dia
  (alarme, `/parar`, alertas), bloqueio de DNS em dois celulares Android via DNS privado, resolução de nomes do tailnet,
  alertas de queda e volta do vigia.
- **Coberto por testes automáticos (sem celular):** o servidor de DNS e a lógica do despertador. Veja [tests/](tests/).
- **Não verificado:** um reinício completo do celular com todos os serviços voltando sozinhos; `install/cloud.sh` em um
  aparelho limpo; outros modelos e versões de Android.

## Segurança em um parágrafo

Os serviços escutam só em `127.0.0.1` e são expostos **apenas** ao seu tailnet pelo `tailscale serve`; o bot ignora todos
menos o seu usuário do Telegram; o SSH só aceita chave. Um Android 10 não recebe mais correções de segurança, então
**nunca** o coloque na internet pública (sem redirecionar portas, sem `tailscale funnel`). Leia o [SECURITY.md](SECURITY.md).

## Créditos e licença

Construído sobre [Termux](https://termux.dev), [Tailscale](https://tailscale.com), [dufs](https://github.com/sigoden/dufs) e a
[API de bots do Telegram](https://core.telegram.org/bots/api). O bloqueador baixa a lista
[StevenBlack/hosts](https://github.com/StevenBlack/hosts) (MIT) em tempo de execução; ela não vem no repositório.
Este repositório usa a [Licença MIT](LICENSE).
