# frozen_string_literal: true

require 'dotenv'
require_relative 'gpt'
require_relative 'task'

require 'google/apis/customsearch_v1'
require 'nokogiri'
require 'open-uri'
require 'http'
require 'concurrent'


Dotenv.load

class Agent

  def initialize
    @tasks = []
    @responses = []
    @objective = ""
    @raw_tasks=""
  end

  def ask_objective
    puts "\nPlease provide your objective:"
    puts "\n"
    @objective = gets.chomp
    tasks_prompt = "You are an AI agent, please break down the following objective into a list of tasks: #{@objective}. Tasks should be separated by a newline. Tasks should be in order of priority."
    @raw_tasks = GPT3.gpt3_wrapper(tasks_prompt)

    tasks = @raw_tasks.split(/\d+\./).map(&:strip).reject(&:empty?)

    tasks.each do |task_description|
      @tasks << Task.new(task_description.strip)
    end
  end


  def thinking(task)
    # Take a task as input, determine if we need to search the internet to accomplish that task.
    puts 'Thinking'
    search_prompt = "Do I need to search the internet to accomplish the task: #{task.description}? reply by 'yes' or 'no'?"
    search_needed = GPT3.gpt3_wrapper(search_prompt).strip.downcase


    if search_needed.include?('yes')
      puts 'I have to search the internet...\n'

      # Use Google Custom Search to get 5 URLs
      search_results = google_custom_search(task.description)

      puts "I have to read the content of these urls...\n"
      puts search_results

      # Scrape and merge the text content from the URLs
      merged_content = search_results.map do |url|
        text_content = scrape_text_content(url)
        text_content
      end.join(" ")

      # Use the summarize_document function to get a summary
      summary = summarize_document(merged_content)

      # Add the summarized content as context to the task description
      task.add_context(summary)
    end
  end

  def google_custom_search(query)
    # Set up the Google Custom Search API client
    api_key = ENV['API_KEY']
    cx = ENV['CX']
    custom_search = Google::Apis::CustomsearchV1::CustomSearchAPIService.new
    custom_search.key = api_key

    # Perform the search and get the URLs
    search_response = custom_search.list_cses(q: query, cx: cx, num: 5)
    search_response.items.map(&:link)
  end

  def scrape_text_content(url)
    # Scrape the text content from the URL
    response = HTTP.headers("User-Agent" => "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/93.0.4577.63 Safari/537.3").get(url)
    page = Nokogiri::HTML(response.to_s)
    page.search('//script').remove
    page.search('//style').remove
    text_content = page.at('body').text.gsub(/\s+/, ' ').strip

    text_content
  end

# The summarize_document function provided earlier can be used as is, if needed

  # def summarize_document(document)
  #   batch_size = 2000
  #   summary_size = 50
  #   final_summary_size = 100

  #   # Divide the document into batches of 1000 characters
  #   batches = document.scan(/.{1,#{batch_size}}/m)

  #   # Summarize each batch in 100 characters using the gpt3_wrapper
  #   summarized_batches = batches.map do |batch|
  #     summary_prompt = "Please summarize the following content in #{summary_size} characters: #{batch}"
  #     GPT3.gpt3_wrapper(summary_prompt).strip
  #   end

  #   # Summarize items in the merged summary 2 by 2 until all batches are taken into account
  #   while summarized_batches.size > 1
  #     summarized_batches = summarized_batches.each_slice(2).map do |summary_pair|
  #       summary_pair_text = summary_pair.join(" ")
  #       summary_prompt = "Please summarize the following content in #{final_summary_size} characters: #{summary_pair_text}"
  #       GPT3.gpt3_wrapper(summary_prompt).strip
  #     end
  #   end

  #   final_summary = summarized_batches.first

  #   puts "summary of search results: #{final_summary} \n"

  #   final_summary
  # end
  def summarize_document(document)
    batch_size = 2000
    summary_size = 50
    final_summary_size = 100
    max_threads = 8

    # Divide the document into batches of 2000 characters
    batches = document.scan(/.{1,#{batch_size}}/m)

    # Initialize a ThreadPoolExecutor
    thread_pool = Concurrent::ThreadPoolExecutor.new(min_threads: 1, max_threads: max_threads, max_queue: 0)

    # Summarize each batch concurrently using the gpt3_wrapper
    summarized_batches = Concurrent::Array.new

    batches.each do |batch|
      thread_pool.post do
        summary_prompt = "Please summarize the following content in #{summary_size} characters: #{batch}"
        summarized_batches.push(GPT3.gpt3_wrapper(summary_prompt).strip)
      end
    end

    thread_pool.shutdown
    thread_pool.wait_for_termination

    # Summarize the concatenated summaries into a final summary
    summarized_text = summarized_batches.join(" ")
    summary_prompt = "Please summarize the following content in #{final_summary_size} characters: #{summarized_text}"
    final_summary = GPT3.gpt3_wrapper(summary_prompt).strip

    puts "summary of search results: #{final_summary} \n"

    final_summary
  end

  def execute_tasks
    puts "\nTask List:"
    @tasks.each_with_index { |task, index| puts "#{index + 1}. #{task.description}" }

    @tasks.each do |task|
      puts "\nExecuting task: #{task.description}"
      thinking(task)
      task.execute
      store_task(task)
      puts "Result: #{task.gpt3_response}"
      puts "\n"
    end
  end

  def store_task(task)
    @responses << { task: task.description, response: task.gpt3_response }
  end

  def show_responses
    puts "\nThe objective was to #{@objective}. Here are the results:"
    puts "================================================================"

    @responses.each do |response|
      puts "\n #{response[:response]}"
      puts "\n"
    end
  end

  def tasks_descriptions
    @tasks.map(&:description).join("\n")
  end

  def run
    ask_objective
    execute_tasks
    show_responses
  end
end

agent = Agent.new
agent.run
