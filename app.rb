require 'httparty'
require 'sinatra'
require 'json'
require 'dotenv/load'
require 'pry'
require 'logger'
require 'cgi'
require 'rack'
require 'rack/cors'





# Configuração do Sinatra

set :bind, '0.0.0.0'
set :port, ENV['PORT'] || 4567
set :environment, :production
enable :logging

disable :protection
set :protection, except: [:remote_token, :frame_options, :json_csrf]







# CORS (Cross-Origin Resource Sharing)

before do
  headers 'Access-Control-Allow-Origin' => '*',
          'Access-Control-Allow-Methods' => ['OPTIONS', 'GET', 'POST'],
          'Access-Control-Allow-Headers' => 'Content-Type'
end

options "*" do
  200
end

use Rack::Cors do
  allow do
    origins '*'
    resource '*', 
      methods: [:get, :post, :options],
      headers: :any
  end
end





# Logger e cache

$logger = Logger.new('application.log')
$logger.level = Logger::INFO

TRANSLATION_CACHE = {}






# Busca mensagens do Slack

def fetch_messages
  params = {
    channel: ENV['SLACK_CHANNEL_ID'],
    limit: 100,
    inclusive: true,
    oldest: (Time.now - (7 * 24 * 60 * 60)).to_i
  }
  
  query = params.map { |k,v| "#{k}=#{v}" }.join('&')
  url = "https://slack.com/api/conversations.history?#{query}"
  headers = { "Authorization" => "Bearer #{ENV['SLACK_BOT_TOKEN']}" }

  begin
    $logger.info("Buscando mensagens do Slack com os parâmetros: #{params.inspect}")
    response = HTTParty.get(url, headers: headers)
    json = JSON.parse(response.body)

    if !json['ok']
      $logger.error("Erro ao buscar mensagens do Slack: #{json['error']}")
      return []
    end

    if json['messages']
      $logger.info("Encontradas #{json['messages'].length} mensagens no canal")
    end

    return [] unless json['ok'] && json['messages']
    json['messages'].reverse
  rescue StandardError => e
    $logger.error("Erro ao buscar mensagens do Slack: #{e.message}")
    []
  end
end

def cache_key(text, direction)
  "#{text}:#{direction}"
end




# Função de tradução

def translate(text, direction = :en_to_pt)
  return "Texto vazio" if text.nil? || text.strip.empty?

  cache_key_str = cache_key(text, direction)
  if TRANSLATION_CACHE[cache_key_str]
    $logger.info("Usando tradução em cache para: #{text}")
    return TRANSLATION_CACHE[cache_key_str]
  end

  unless ENV['LLM_API_KEY'] && ENV['LLM_EN_PT_URL'] && ENV['LLM_PT_EN_URL']
    $logger.error("Configuração incompleta das variáveis de ambiente")
    return "Erro de configuração"
  end

  url = direction == :pt_to_en ? ENV['LLM_PT_EN_URL'] : ENV['LLM_EN_PT_URL']

  headers = {
    "Authorization" => "Bearer #{ENV['LLM_API_KEY']}", 
    "Content-Type" => "application/json"
  }

  clean_text = text.gsub(/<@[^>]+>/, '').strip
  data = { 
    inputs: clean_text,
    options: { 
      wait_for_model: true,
      use_cache: true
    }
  }

  max_retries = 3
  retry_count = 0
  retry_delay = 2

  while retry_count < max_retries
    begin
      $logger.info("Tentando tradução (#{retry_count + 1}/#{max_retries})")
      $logger.info("URL: #{url}")
      $logger.info("Texto para tradução: #{clean_text}")
      
      response = HTTParty.post(
        url, 
        body: data.to_json,
        headers: headers,
        timeout: 30
      )

      $logger.info("Código de resposta: #{response.code}")
      $logger.info("Resposta completa: #{response.body}")

      case response.code
      when 200
        begin
          json = JSON.parse(response.body)
          if json.is_a?(Array) && json[0] && json[0]["translation_text"]
            result = json[0]["translation_text"].strip
            TRANSLATION_CACHE[cache_key_str] = result
            $logger.info("Tradução bem sucedida: #{result}")
            return result
          else
            $logger.error("Formato inesperado na resposta: #{json}")
            return "Erro no formato da resposta"
          end
        rescue JSON::ParserError => e
          $logger.error("Erro ao processar JSON: #{e.message}")
          return "Erro ao processar resposta"
        end
      when 402
        $logger.error("Erro 402: Payment Required - Modelo pode requerer assinatura")
        return "Modelo temporariamente indisponível"
      when 503
        $logger.info("Modelo carregando, tentando novamente...")
        retry_count += 1
        sleep retry_delay
        retry_delay *= 2
        next
      else
        $logger.error("Erro HTTP #{response.code}: #{response.body}")
        return "Erro na tradução (#{response.code})"
      end

    rescue Net::OpenTimeout, Net::ReadTimeout => e
      $logger.error("Timeout na requisição: #{e.message}")
      retry_count += 1
      if retry_count < max_retries
        sleep retry_delay
        retry_delay *= 2
      else
        return "Tempo limite excedido"
      end
    rescue StandardError => e
      $logger.error("Erro inesperado: #{e.message}")
      retry_count += 1
      if retry_count < max_retries
        sleep retry_delay
        retry_delay *= 2
      else
        return "Erro inesperado na tradução"
      end
    end
  end

  "Não foi possível realizar a tradução"
end

messages = []






# Thread para escutar mensagens do Slack

Thread.new do
  loop do
    begin
      $logger.info("Buscando novas mensagens do Slack...")
      all = fetch_messages
      all.each do |msg|
        next if messages.any? { |m| m[:ts] == msg['ts'] }

        messages << {
          ts: msg['ts'],
          original: msg['text'],
          translated: translate(msg['text'], :en_to_pt)
        }
      end
    rescue StandardError => e
      $logger.error("Erro ao buscar mensagens do Slack: #{e.message}")
      $logger.error(e.backtrace.join("\n"))
    end
    sleep 1
  end
end






# Rotas da aplicação

get '/' do
  erb :index, locals: { messages: messages }
end


# Recebe texto em português, traduz para inglês e retorna em JSON.

post '/reply' do
  content_type :json
  pt = params[:text]

  if pt.nil? || pt.strip.empty?
    return { error: "Texto vazio" }.to_json
  end

  en = translate(pt, :pt_to_en)
  { translated: en }.to_json
end


# Recebe um texto traduzido e o envia para o Slack.

post '/send' do
  text = params[:text]
  original = params[:original]

  if text.nil? || text.strip.empty?
    return { error: "Texto vazio" }.to_json
  end

  response = HTTParty.post("https://slack.com/api/chat.postMessage", {
    headers: { "Authorization" => "Bearer #{ENV['SLACK_BOT_TOKEN']}" },
    body: {
      channel: ENV['SLACK_CHANNEL_ID'],
      text: "#{text}"
    }
  })

  if response.code == 200
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


# Retorna as mensagens traduzidas em formato JSON para serem consumidas via API.

get '/messages' do
  content_type :json
  messages.to_json
end
