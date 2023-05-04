require 'bundler/setup'
require 'dotenv'
require 'net/http'
require 'json'
require 'concurrent'

Dotenv.load

class GPT3
  OPENAI_API_MODEL = 'gpt-3.5-turbo'
  OPENAI_TEMPERATURE = 0.2

  def self.gpt3_wrapper(prompt, model: OPENAI_API_MODEL, temperature: OPENAI_TEMPERATURE, max_tokens: 600)
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

    if response.key?('choices') && response['choices'].any? && response['choices'][0].key?('message') && response['choices'][0]['message'].key?('content')
      response['choices'][0]['message']['content'].strip
    else
      raise "Unexpected API response format: #{response}"
    end
  end

  def self.request_embedding(text)
    uri = URI('https://api.openai.com/v1/embeddings')
    req = Net::HTTP::Post.new(uri)
    req.content_type = 'application/json'
    req['Authorization'] = "Bearer " + ENV['OPENAI_API_KEY']

    req.body = {
      'input' => text,
      'model' => 'text-embedding-ada-002'
    }.to_json

    res = Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == 'https') do |http|
      http.request(req)
    end

    begin
      parsed_response = JSON.parse(res.body)
    rescue JSON::ParserError
      puts "Error parsing API response: #{res.body}"
      return " "
    end

    if parsed_response['data'] && parsed_response['data'][0] && parsed_response['data'][0]['embedding']
      parsed_response['data'][0]['embedding']
    else
      puts "Unexpected API response format: #{res.body}"
      " "
    end
  end

  def self.cosine_similarity(a, b)
    dot_product = a.zip(b).map { |x, y| x * y }.reduce(:+)
    magnitude_a = Math.sqrt(a.map { |x| x * x }.reduce(:+))
    magnitude_b = Math.sqrt(b.map { |x| x * x }.reduce(:+))
    dot_product / (magnitude_a * magnitude_b)
  end

  def self.semantic_search(query, text, top_k = 15)
    query_embedding = request_embedding(query)
    text_sentences = text.split('.')

    # Request embeddings for all sentences in a single API call
    text_embeddings = text_sentences.map { |sentence| request_embedding(sentence) }

    # Calculate similarity scores in parallel using a thread pool
    similarity_scores = Concurrent::Array.new
    thread_pool = Concurrent::FixedThreadPool.new(10)
    text_embeddings.each_with_index do |embedding, i|
      thread_pool.post do
        similarity_scores[i] = cosine_similarity(query_embedding, embedding)
      end
    end

    thread_pool.shutdown
    thread_pool.wait_for_termination

    # Find the top_k most similar sentences
    top_k_indices = similarity_scores.each_with_index.sort_by { |score, _| -score }.map(&:last).take(top_k)
    top_k_sentences = top_k_indices.map { |idx| text_sentences[idx] }

    top_k_sentences
  end
end
