require 'httparty'
require 'sinatra'
require 'json'
require 'dotenv/load'
require 'pry'
require 'logger'
require 'cgi'

# Configuração do servidor
set :bind, '0.0.0.0'  # Permite acesso externo
set :port, ENV['PORT'] || 4567
set :logging, true

# Configurar logger como variável global
$logger = Logger.new('application.log')
$logger.level = Logger::INFO

# Cache de traduções
TRANSLATION_CACHE = {}

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

# Função para gerar chave de cache
def cache_key(text, direction)
  "#{text}:#{direction}"
end

# Função para traduzir usando Google Translate como fallback
def translate_with_google(text, direction)
  source_lang = direction == :pt_to_en ? 'pt' : 'en'
  target_lang = direction == :pt_to_en ? 'en' : 'pt'
  
  encoded_text = CGI.escape(text)
  url = "https://translate.googleapis.com/translate_a/single?client=gtx&sl=#{source_lang}&tl=#{target_lang}&dt=t&q=#{encoded_text}"
  
  begin
    response = HTTParty.get(url)
    if response.code == 200
      json = JSON.parse(response.body)
      translated = json[0].map { |segment| segment[0] }.join(' ')
      return translated
    end
  rescue => e
    $logger.error("Erro no Google Translate: #{e.message}")
  end
  nil
end

def translate(text, direction = :en_to_pt)
  # Verificar cache primeiro
  cache_key_str = cache_key(text, direction)
  if TRANSLATION_CACHE[cache_key_str]
    $logger.info("Usando tradução em cache para: #{text}")
    return TRANSLATION_CACHE[cache_key_str]
  end

  # Verifica se as variáveis de ambiente estão configuradas corretamente
  unless ENV['LLM_API_KEY'] && ENV['LLM_EN_PT_URL'] && ENV['LLM_PT_EN_URL']
    $logger.error("LLM_API_KEY ou URLs de tradução não estão configuradas corretamente.")
    return "Erro de configuração"
  end

  # Seleciona a URL baseado na direção da tradução
  url = case direction
        when :pt_to_en
          ENV['LLM_PT_EN_URL']
        else
          ENV['LLM_EN_PT_URL']
        end

  headers = {
    "Authorization" => "Bearer #{ENV['LLM_API_KEY']}", 
    "Content-Type" => "application/json"
  }

  clean_text = text.gsub(/<@[^>]+>/, '').strip
  data = { inputs: clean_text }

  # Configurações de retry
  max_retries = 5  # Aumentado para 5 tentativas
  retry_count = 0
  retry_delay = 2 # segundos

  while retry_count < max_retries
    begin
      $logger.info("Tentativa #{retry_count + 1} de #{max_retries} - Enviando para Hugging Face (#{direction}): #{data.to_json}")
      
      response = HTTParty.post(url, body: data.to_json, headers: headers)

      if response.code == 503
        retry_count += 1
        if retry_count < max_retries
          $logger.info("Erro 503 recebido. Aguardando #{retry_delay} segundos antes de tentar novamente...")
          sleep retry_delay
          retry_delay *= 2
          next
        else
          # Tentar Google Translate como fallback
          $logger.info("Tentando Google Translate como fallback...")
          if result = translate_with_google(clean_text, direction)
            TRANSLATION_CACHE[cache_key_str] = result
            return result
          end
        end
      end

      if response.code != 200
        $logger.error("Erro na tradução: Código #{response.code} - #{response.body}")
        # Tentar Google Translate como fallback
        if result = translate_with_google(clean_text, direction)
          TRANSLATION_CACHE[cache_key_str] = result
          return result
        end
        return "Erro na tradução"
      else
        begin
          json = JSON.parse(response.body)
          result = json.dig(0, "translation_text") || "Erro na tradução"
          # Armazenar no cache
          TRANSLATION_CACHE[cache_key_str] = result
          $logger.info("Resposta da API: #{result}")
          return result
        rescue => e
          $logger.error("Erro ao processar a resposta: #{e.message}")
          return "Erro ao processar resposta"
        end
      end

    rescue StandardError => e
      $logger.error("Erro na requisição: #{e.message}")
      retry_count += 1
      if retry_count < max_retries
        $logger.info("Aguardando #{retry_delay} segundos antes de tentar novamente...")
        sleep retry_delay
        retry_delay *= 2
      else
        # Tentar Google Translate como último recurso
        if result = translate_with_google(clean_text, direction)
          TRANSLATION_CACHE[cache_key_str] = result
          return result
        end
        return "Erro ao traduzir após #{max_retries} tentativas"
      end
    end
  end

  "Erro ao traduzir após #{max_retries} tentativas"
end

# Lista de mensagens em memória
messages = []

# Thread para buscar mensagens do Slack em segundo plano
Thread.new do
  loop do
    begin
      $logger.info("Buscando novas mensagens do Slack...")
      all = fetch_messages
      all.each do |msg|
        # Ignora mensagens já processadas
        next if messages.any? { |m| m[:ts] == msg['ts'] }

        # Adiciona a mensagem original e traduzida à lista
        messages << {
          ts: msg['ts'],
          original: msg['text'],
          translated: translate(msg['text'], :en_to_pt)  # Especifica direção EN->PT
        }
      end
    rescue StandardError => e
      $logger.error("Erro ao buscar mensagens do Slack: #{e.message}")
      $logger.error(e.backtrace.join("\n"))
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

  en = translate(pt, :pt_to_en)  # Especifica direção PT->EN
  { translated: en }.to_json
end

# Rota para enviar a resposta para o Slack
post '/send' do
  text = params[:text]
  original = params[:original]

  # Validação para garantir que o texto não esteja vazio
  if text.nil? || text.strip.empty?
    return { error: "Texto vazio" }.to_json
  end

  # Envia a mensagem traduzida para o Slack
  response = HTTParty.post("https://slack.com/api/chat.postMessage", {
    headers: { "Authorization" => "Bearer #{ENV['SLACK_BOT_TOKEN']}" },
    body: {
      channel: ENV['SLACK_CHANNEL_ID'],
      text: "#{text}"
    }
  })

  if response.code == 200
    # Adiciona a mensagem à lista local imediatamente
    messages.unshift({
      ts: Time.now.to_i.to_s,
      original: text,
      translated: original
    })
    
    content_type :json
    { success: true }.to_json
    redirect '/'
  else
    content_type :json
    { error: "Erro ao enviar mensagem para o Slack" }.to_json
  end
end

# Rota para fornecer as mensagens em formato JSON
get '/messages' do
  content_type :json
  messages.to_json
end
