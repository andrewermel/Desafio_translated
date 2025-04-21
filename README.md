# Slack Translator

Aplicação Ruby para tradução em tempo real de mensagens do Slack usando LLM.

## Requisitos

- Ruby 2.7+
- Conta no Slack com permissões de Bot
- Conta no Hugging Face
- Ngrok instalado

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

## Expondo o serviço na internet com Ngrok

1. Instale o Ngrok:
   - Faça o download em https://ngrok.com/download
   - Extraia o arquivo baixado
   - Mova o executável para um local no seu PATH

2. Faça login no Ngrok:
   - Crie uma conta em https://ngrok.com
   - Copie o token de autenticação
   - Execute o comando:
```bash
ngrok config add-authtoken SEU_TOKEN_AQUI
```

3. Inicie o túnel Ngrok:
```bash
ngrok http 4567
```

4. Copie a URL HTTPS fornecida pelo Ngrok (exemplo: https://seu-tunnel.ngrok.io)

## Executando a aplicação

1. Inicie o servidor:
```bash
ruby app.rb
```

2. Acesse a aplicação:
   - Localmente: http://localhost:4567
   - Internet: Use a URL HTTPS fornecida pelo Ngrok

## Uso

- As mensagens do canal do Slack serão atualizadas automaticamente a cada 5 segundos
- Para responder em português, use o campo de texto na parte inferior
- Confirme a tradução antes de enviar para o Slack
