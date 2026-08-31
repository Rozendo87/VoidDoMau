# DTunnel Panel — compatível com BASEV25

Painel de gerenciamento de servidores (SSH / V2Ray / DNSTT / Hysteria) para o
app Android **BASEV25** (fork rebrandeado "Dragoncore" do app DTunnel/SocksRevive).

Este repositório é o painel [DTunnel](https://github.com/) padrão com um
ajuste de compatibilidade pra falar o protocolo exato que o app espera, mais
um instalador automatizado (`install.sh`) com Nginx + HTTPS via Certbot.

---

## Como o app fala com o painel

O app faz, na tela principal, uma requisição pra buscar a lista de servidores:

```
POST https://SEU_DOMINIO/api2
Headers:
  Accept: application/json
  Connection: keep-alive
  dragoncore-token: <uuid do usuário no painel>
  dragoncore-update: app_config
  User-Agent: Dragoncore (@penguinehis, @sisudragon)
Body: vazio
```

**Resposta esperada pelo app:**

```json
{ "data": "<base64 criptografado>" }
```

O campo `data` é o JSON dos servidores (categoria, host, payload, SNI, UUID
v2ray, etc.) criptografado em **AES-256-CBC**:

- chave = `SHA-256("05VE1b3kx10ntsfzvsSmZD3KYuilFXyS")`
- IV = 16 bytes zerados
- padding PKCS5

Essa lógica está implementada em:
- App (Java): `SocksReviveMainActivity.java` → `decryptAES()` / `fetchServerData()`
- Painel (TS): `src/utils/crypto.ts` (`AESCrypt`) + `src/routes/api/dragoncore-api.ts`

> O painel DTunnel "de fábrica" usa outra rota (`GET /api/dtunnelmod`), outros
> headers (`dtunnel-token`, `dtunnel-update`) e outra senha AES. A rota
> `dragoncore-api.ts` foi criada **sem mexer na rota original** — então esse
> painel continua atendendo o DTunnel padrão e o BASEV25 ao mesmo tempo.

---

## Estrutura relevante do projeto

```
DTunnel-main/
├── install.sh                        # instalador automatizado (ver abaixo)
├── prisma/
│   ├── schema.prisma                 # modelo do banco (User, Category, AppConfig...)
│   └── migrations/                   # migrações do banco (SQLite)
├── src/
│   ├── routes/api/
│   │   ├── dtunnel-mod.ts            # rota original do DTunnel (inalterada)
│   │   └── dragoncore-api.ts         # rota nova, compatível com o app BASEV25
│   ├── utils/crypto.ts               # AES-256-CBC (encrypt/decrypt)
│   └── ...
├── frontend/                         # telas do painel (login, configs, categorias...)
└── ecosystem.config.js               # config do PM2 (produção)
```

---

## Instalação automatizada (`install.sh`)

Roda numa VPS Ubuntu/Debian, como root, com o DNS do subdomínio **já
apontando pro IP do servidor** (o Certbot precisa disso pra emitir o
certificado).

```bash
sudo ./install.sh -d painel.seudominio.com -p 3000 -e voce@email.com -s SuaSenhaForte
```

### Parâmetros

| Flag | Obrigatório | Descrição | Padrão |
|---|---|---|---|
| `-d`, `--domain` | sim | Subdomínio que vai apontar pro painel | — |
| `-e`, `--email` | sim | E-mail do admin (login + Certbot) | — |
| `-s`, `--password` | sim | Senha do admin | — |
| `-p`, `--port` | não | Porta interna do Node.js | `3000` |
| `-u`, `--username` | não | Usuário do admin | derivado do e-mail |
| `--env` | não | Caminho de um `.env` já pronto, pra reaproveitar em vez de gerar um novo | — |

Também dá pra deixar domínio/e-mail/senha **pré-cadastrados direto no
script**, editando o topo do arquivo:

```bash
DEFAULT_DOMAIN=""
DEFAULT_PORT="3000"
DEFAULT_EMAIL=""
DEFAULT_PASSWORD=""
```

Aí você só roda `sudo ./install.sh` sem passar nada.

### O que o script faz

1. Instala dependências: `nginx`, `certbot` + `python3-certbot-nginx`, `Node.js 20.x`, `pm2`
2. Monta o `.env`:
   - se `--env` foi passado → usa esse arquivo
   - se já existe um `.env` no projeto → mantém, só ajusta a `PORT`
   - senão → gera um novo, com `CSRF_SECRET`, `JWT_SECRET_KEY` e
     `JWT_SECRET_REFRESH` aleatórios (`openssl rand -hex 32`)
3. `npm install` → `npx prisma generate` → `npx prisma migrate deploy` → `npm run build`
4. Cria (ou atualiza, se já existir o e-mail) o usuário admin no banco, com a
   senha em bcrypt — sem precisar passar pela tela de registro
5. Configura o Nginx como proxy reverso `SEU_DOMINIO → 127.0.0.1:PORTA`
6. Roda `certbot --nginx` pra emitir e configurar o HTTPS automaticamente
7. Sobe o painel com `pm2` (via `ecosystem.config.js`) e registra o
   auto-start no boot (`pm2 startup`)
8. Salva um resumo em `INSTALL_INFO.txt`, na raiz do projeto

### Resultado da instalação

Ao final, `INSTALL_INFO.txt` contém tudo que você precisa:

```
== Painel instalado ==
URL:            https://painel.seudominio.com
Porta interna:  3000
.env:           /caminho/DTunnel-main/.env

== Admin (login no painel) ==
Usuário:  seunome
E-mail:   voce@email.com
Senha:    (a que você informou no parâmetro -s)

== Para configurar no app (BASEV25 / Dragoncore) ==
dragoncore-token = <uuid gerado pro seu usuário admin>
Endpoint         = https://painel.seudominio.com/api2
```

O `dragoncore-token` é o `user_id` do seu usuário no banco — é ele que
identifica de qual painel o app deve puxar os servidores. Cadastre os
servidores no painel (logado com o e-mail/senha) associados a esse mesmo
usuário, e o app vai enxergá-los.

Pode rodar o `install.sh` de novo (por exemplo pra trocar a senha do admin ou
reemitir o certificado) — ele é idempotente: não duplica usuário nem quebra
configuração existente.

---

## Rodando manualmente (sem o install.sh)

```bash
npm install
cp .env.example .env        # edite os valores
npx prisma generate
npx prisma migrate deploy
npm run build
npm run prod                # sobe via pm2 (ecosystem.config.js)
```

Pra desenvolvimento, com hot-reload:

```bash
npm run dev
```

---

## Bug corrigido: migração do banco

A migração `prisma/migrations/20251018193643_database/migration.sql`, como
veio no ZIP original, tentava recriar (`CREATE TABLE`) tabelas que a
migração anterior já tinha criado — isso faz `prisma migrate deploy` falhar
em **qualquer instalação nova** (erro `table already exists` /
`column does not exist`, dependendo do ponto em que trava).

Ela foi reescrita pra aplicar só o delta real (`ALTER TABLE ... ADD COLUMN`
para as colunas novas de `users` e `app_configs`, `CREATE TABLE IF NOT
EXISTS` só para as tabelas realmente novas: `cdn` e `app_layout_storages`).
Testado do zero (banco limpo → migração → build → subida em produção → chamada
real no `/api2`) sem erros.

---

## Segurança

- O `.env` gerado tem `chmod 600` — só o root lê
- `INSTALL_INFO.txt` também fica com `chmod 600` (contém o token de acesso
  aos servidores) — recomenda-se apagar ou mover esse arquivo pra um lugar
  seguro depois de anotar as credenciais
- A senha AES e os headers específicos do app (`dragoncore-token` etc.) estão
  hardcoded tanto no app quanto no painel — são o "protocolo" combinado entre
  os dois lados, não segredos de usuário. Trocar essas strings nos dois
  lados é uma forma simples de descolar esse painel de qualquer outra cópia
  do app rodando por aí com a mesma chave original.
# VoidDoMau
