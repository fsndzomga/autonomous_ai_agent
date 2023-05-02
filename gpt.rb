# frozen_string_literal: true

require 'bundler/setup'
require 'dotenv'
require 'net/http'
require 'json'

Dotenv.load

class GPT3
  OPENAI_API_MODEL = 'gpt-3.5-turbo'
  OPENAI_TEMPERATURE = 0.2

  def self.gpt3_wrapper(prompt, model: OPENAI_API_MODEL, temperature: OPENAI_TEMPERATURE, max_tokens: 400)
    uri = URI('https://api.openai.com/v1/chat/completions')
    req = Net::HTTP::Post.new(uri)
    req.content_type = 'application/json'
    req['Authorization'] = 'Bearer ' + ENV['OPENAI_API_KEY']

    req.body = {
      'model' => model,
      'messages' => [
        {
          'role' => 'system',
          'content' => prompt
        }
      ],
      'temperature' => temperature,
      'max_tokens' => max_tokens
    }.to_json

    req_options = {
      use_ssl: uri.scheme == 'https'
    }

    res = Net::HTTP.start(uri.hostname, uri.port, req_options) do |http|
      http.request(req)
    end

    response = JSON.parse(res.body)
    response['choices'][0]['message']['content'].strip
  end
end
