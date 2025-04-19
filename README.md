# Slack Translator

Aplicação Ruby para tradução em tempo real de mensagens do Slack usando LLM.

## Requisitos

- Ruby 2.7+
- Conta no Slack com permissões de Bot
- Conta no Hugging Face
- Cloudflared instalado

## Configuração

1. Clone o repositório
2. Copie `.env.example` para `.env` e configure as variáveis:
```bash
cp .env.example .env
```

3. Configure o bot do Slack:
   - Crie um app em https://api.slack.com/apps
   - Adicione as permissões: `channels:history`, `chat:write`
   - Instale o app no seu workspace
   - Copie o Bot User OAuth Token para `SLACK_BOT_TOKEN`
   - Copie o ID do canal para `SLACK_CHANNEL_ID`

4. Configure o Hugging Face:
   - Crie uma conta em https://huggingface.co
   - Gere um token de API
   - Copie o token para `LLM_API_KEY`

5. Instale as dependências:
```bash
bundle install
```

## Expondo o serviço na internet com Cloudflare Tunnel

1. Instale o cloudflared:
```bash
# Linux
curl -L --output cloudflared.deb https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64.deb
sudo dpkg -i cloudflared.deb

# Mac
brew install cloudflared
```

2. Faça login no Cloudflare:
```bash
cloudflared tunnel login
```

3. Crie um túnel:
```bash
cloudflared tunnel create slack-translator
```

4. Configure o túnel (substitua UUID pelo ID gerado):
```bash
cloudflared tunnel route dns UUID slack-translator.seu-dominio.com
```

5. Crie o arquivo de configuração:
```bash
cat << EOF > ~/.cloudflared/config.yml
tunnel: UUID
credentials-file: /home/user/.cloudflared/UUID.json
ingress:
  - hostname: slack-translator.seu-dominio.com
    service: http://localhost:4567
  - service: http_status:404
EOF
```

6. Inicie o túnel:
```bash
cloudflared tunnel run
```

## Executando a aplicação

1. Inicie o servidor:
```bash
ruby app.rb
```

2. Acesse a aplicação:
   - Localmente: http://localhost:4567
   - Internet: https://slack-translator.seu-dominio.com

## Uso

- As mensagens do canal do Slack serão atualizadas automaticamente a cada 5 segundos
- Para responder em português, use o campo de texto na parte inferior
- Confirme a tradução antes de enviar para o Slack# Desafio_translated
