require 'httparty'
require 'sinatra'
require 'json'
require 'dotenv/load'
require 'pry'
require 'logger'

# Configuração do servidor
set :bind, '0.0.0.0'  # Permite acesso externo
set :port, ENV['PORT'] || 4567
set :logging, true

# Configurar logger
logger = Logger.new('application.log')
logger.level = Logger::INFO

# Removido print das variáveis sensíveis no console
puts "============================================="
puts "SLACK_CHANNEL_ID: #{ENV['SLACK_CHANNEL_ID']}"
puts "============================================="
puts "============================================="
puts "LLM_API_KEY: #{ENV['LLM_API_KEY']}"
puts "============================================="
puts "LLM_BASE_URL: #{ENV['LLM_BASE_URL']}"
puts "============================================="

# Função para buscar mensagens do Slack
def fetch_messages
  url = "https://slack.com/api/conversations.history?channel=#{ENV['SLACK_CHANNEL_ID']}"
  headers = { "Authorization" => "Bearer #{ENV['SLACK_BOT_TOKEN']}" }

  response = HTTParty.get(url, headers: headers)
  json = JSON.parse(response.body)

  # Retorna um array vazio caso algo dê errado
  return [] unless json['ok'] && json['messages']

  json['messages']
end


def translate(text)
  # Verifica se as variáveis de ambiente estão configuradas corretamente
  unless ENV['LLM_API_KEY'] && ENV['LLM_BASE_URL']
    puts "LLM_API_KEY ou LLM_BASE_URL não estão configurados corretamente."
    return "Erro de configuração"
  end

  # Definindo os cabeçalhos para a requisição
  headers = {
    "Authorization" => "Bearer #{ENV['LLM_API_KEY']}", # Token da API
    "Content-Type" => "application/json" # Tipo de conteúdo como JSON
  }

  # Removendo menções do Slack e limpando o texto
  clean_text = text.gsub(/<@[^>]+>/, '').strip

  # Preparando os dados para enviar na requisição
  data = {
    inputs: clean_text
  }

  # Log da requisição para verificar o que está sendo enviado
  puts "Enviando para Hugging Face: #{data.to_json}"

  begin
    # binding.pry
    # Enviando a requisição POST para a API
    response = HTTParty.post(ENV['LLM_BASE_URL'], body: data.to_json, headers: headers)
  rescue StandardError => e
    # Tratamento de erros na requisição
    puts "Erro na requisição: #{e.message}"
    return "Erro ao traduzir"
  end

  # Verificando se a resposta foi bem-sucedida
  if response.code != 200
    puts "Erro na tradução: Código #{response.code} - #{response.body}"
    return "Erro na tradução"
  else
    # Processa a resposta caso o código de status seja 200
    begin
      json = JSON.parse(response.body)
      result = json.dig(0, "translation_text") || "Erro na tradução"
      puts "Resposta da API: #{result}"
      result
    rescue => e
      puts "Erro ao processar a resposta: #{e.message}"
      "Erro ao processar resposta"
    end
  end
end

# Lista de mensagens em memória
messages = []

# Thread para buscar mensagens do Slack em segundo plano
Thread.new do
  loop do
    begin
      all = fetch_messages
      all.each do |msg|
        # Ignora mensagens já processadas
        next if messages.any? { |m| m[:ts] == msg['ts'] }

        # Adiciona a mensagem original e traduzida à lista
        messages << {
          ts: msg['ts'],
          original: msg['text'],
          translated: translate(msg['text'])
        }
      end
    rescue StandardError => e
      puts "Erro ao buscar mensagens do Slack: #{e.message}"
    end
    sleep 5
  end
end

# Rota para exibir as mensagens no navegador
get '/' do
  erb :index, locals: { messages: messages }
end

# Rota para traduzir a resposta do usuário
post '/reply' do
  content_type :json
  pt = params[:text]

  # Validação para garantir que o texto não esteja vazio
  if pt.nil? || pt.strip.empty?
    return { error: "Texto vazio" }.to_json
  end

  en = translate(pt)  # Traduz o texto para o inglês
  { translated: en }.to_json
end

# Rota para enviar a resposta para o Slack
post '/send' do
  text = params[:text]

  # Validação para garantir que o texto não esteja vazio
  if text.nil? || text.strip.empty?
    return { error: "Texto vazio" }.to_json
  end

  # Envia a mensagem para o Slack
  response = HTTParty.post("https://slack.com/api/chat.postMessage", {
    headers: { "Authorization" => "Bearer #{ENV['SLACK_BOT_TOKEN']}" },
    body: {
      channel: ENV['SLACK_CHANNEL_ID'],
      text: text
    }
  })

  if response.code == 200
    redirect '/'
  else
    return { error: "Erro ao enviar mensagem para o Slack" }.to_json
  end
end

# Rota para fornecer as mensagens em formato JSON
get '/messages' do
  content_type :json
  messages.to_json
end
