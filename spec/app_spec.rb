require_relative 'spec_helper'

RSpec.describe 'SlackTranslator App' do

  describe 'Rotas básicas' do
    it 'deve responder à rota principal' do
      get '/'
      expect(last_response).to be_ok
    end

    it 'deve responder à rota /messages' do
      get '/messages'
      expect(last_response).to be_ok
      expect(last_response.content_type).to include('application/json')
    end
  end


  describe 'POST /reply' do
    it 'deve retornar erro para texto vazio' do
      post '/reply', text: ''
      expect(last_response).to be_ok
      expect(JSON.parse(last_response.body)).to include('error' => 'Texto vazio')
    end

    it 'deve traduzir texto com sucesso', :vcr do
      texto_pt = 'Olá, como vai você?'
      post '/reply', text: texto_pt
      
      expect(last_response).to be_ok
      resposta = JSON.parse(last_response.body)
      expect(resposta).to have_key('translated')
      expect(resposta['translated']).not_to be_empty
    end
  end


  describe 'Tradução' do
    it 'deve retornar mensagem de erro para texto vazio' do
      expect(translate(nil)).to eq('Texto vazio')
      expect(translate('')).to eq('Texto vazio')
      expect(translate('  ')).to eq('Texto vazio')
    end

    it 'deve usar cache para textos repetidos', :vcr do
      texto = 'Hello, world!'
      primeira_traducao = translate(texto)
      
      expect(TRANSLATION_CACHE).to have_key(cache_key(texto, :en_to_pt))
      expect(translate(texto)).to eq(primeira_traducao)
    end
  end
  

  describe 'Integração com Slack' do
    before do
      allow(ENV).to receive(:[]).and_return(nil)
      allow(ENV).to receive(:[]).with('SLACK_CHANNEL_ID').and_return('test-channel')
      allow(ENV).to receive(:[]).with('SLACK_BOT_TOKEN').and_return('test-token')
    end

    it 'deve buscar mensagens do Slack com sucesso', :vcr do
      VCR.use_cassette('slack_messages') do
        mensagens = fetch_messages
        expect(mensagens).to be_an(Array)
      end
    end
  end
end