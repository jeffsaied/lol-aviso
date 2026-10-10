# LoL Aviso

Painel pequeno para o League of Legends (Windows) que cuida da fila por você.

- **Aceita a partida sozinho** quando a fila encontra.
- **No ARAM, manda as cartas para o celular** com o nome de cada campeão e um botão para escolher de lá.
- **Se ninguém escolher a tempo, escolhe sozinho** — pega um campeão que você joga bastante (pela maestria da sua conta); se nenhuma carta for dos seus, pega qualquer uma.
- **Tira a tela de carregamento da frente**: manda para o segundo monitor (jogo em "sem bordas" ou "janela") ou minimiza, e traz o jogo de volta quando ele abre.
- **Avisa no celular** quando o carregamento termina e o jogo abre no mapa.

Um botão só: verde **ON** está ligado, um clique desliga e ele fica vermelho **OFF**.

## Instalar

1. Baixe o **[LoL-Aviso.zip](https://github.com/jeffsaied/lol-aviso/releases/latest/download/LoL-Aviso.zip)**.
2. Extraia a pasta inteira (não rode de dentro do zip).
3. Dê dois cliques em `instalar.bat`.
4. Ao abrir, o programa mostra uma caixa para ligar o celular:
   - instale o app **ntfy** no celular (Android ou iPhone);
   - invente um nome de tópico só seu (algo como `lol-jeffi-exemplo`, mas com o seu nome) e escreva na caixa;
   - no app, toque em **+** e assine esse mesmo nome;
   - clique em **Enviar teste** para conferir e depois em **Salvar**.

A caixa volta a aparecer toda vez que o programa abre, até você salvar um tópico. Para trocar depois, clique na linha do tópico no painel.

O painel aparece no canto da tela e passa a abrir junto com o Windows. Para abrir na mão, use o atalho **LoL Aviso** na área de trabalho.

## Usar

- Botão redondo: liga e desliga.
- Arraste pelo fundo para mudar o painel de lugar.
- **?** mostra ou esconde a lista do que ele faz.
- Clique na linha do tópico para configurar ou trocar o aviso no celular.
- **✕** fecha o programa.

## Bom saber

- Escolha um nome de tópico difícil de adivinhar e não passe para ninguém: quem souber recebe seus avisos.
- Se o Windows perguntar se quer mesmo executar, é porque o arquivo veio da internet. Confirme.
- É um programa de terceiros, sem ligação com a Riot Games, que usa a interface local do cliente do LoL para aceitar a partida e escolher o campeão. Use por sua conta.
- Precisa de Windows 10 ou 11. Não instala nada além dos próprios arquivos, em `%LOCALAPPDATA%\LoL-Aviso`.

## Remover

Dois cliques em `desinstalar.bat`.
