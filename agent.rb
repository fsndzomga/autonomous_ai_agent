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
    puts "Thinking\n\n"
    search_prompt = "Do I need to search the internet to accomplish the task: #{task.description}? Does it require up-to-date information or data? reply by 'yes' or 'no'?"
    search_needed = GPT3.gpt3_wrapper(search_prompt).strip.downcase

    search_query_prompt = "In four words, what search prompt will help for this task: #{task.description}?"
    search_query = GPT3.gpt3_wrapper(search_query_prompt).strip.downcase

    puts "search query: #{search_query}"


    if search_needed.include?('yes')
      puts "I have to search the internet...\n\n"

      # Use Google Custom Search to get 5 URLs
      search_results = google_custom_search(search_query)

      puts "I have to read the content of these urls...\n\n"
      puts search_results

      # Scrape and merge the text content from the URLs
      merged_content = search_results.map do |url|
        text_content = scrape_text_content(url)
        text_content[0...1000] # Take only the first 1000 characters
      end.join(" ")

      # Use the GPT3.semantic_search function to get the top 3 relevant sentences
      top_sentences = GPT3.semantic_search(task.description + " " + search_query, merged_content)

      # Add the top relevant sentences as context to the task description
      task.add_context(top_sentences.join(" "))
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

    # Return an empty array if there are no items in the search response
    return [] if search_response.items.nil?

    search_response.items.map(&:link)
  end

  def scrape_text_content(url)
    begin
      # Scrape the text content from the URL with a 60-second timeout
      response = HTTP.timeout(60).headers("User-Agent" => "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/93.0.4577.63 Safari/537.3").get(url)
    rescue StandardError
      return " "
    end

    # Check if the content type is HTML
    content_type = response.headers["Content-Type"]
    return "Not an HTML file" unless content_type && content_type.include?("text/html")

    # Parse the HTML content
    page = Nokogiri::HTML(response.to_s)

    # Remove script and style elements
    page.search('//script').remove
    page.search('//style').remove

    # Get the body element and handle potential issues
    body_element = page.at('body')

    if body_element.nil?
      return " "
    else
      text_content = body_element.text.gsub(/\s+/, ' ').strip
    end

    text_content
  end

  def summarize_document(document)
    batch_size = 1000
    summary_size = 50
    final_summary_size = 100
    max_threads = 8

    # Divide the document into batches of 1000 characters
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

    # ...

    if summarized_text.length > 2000
      # Split summarized text into 4 parts
      parts = summarized_text.scan(/.{1,#{summarized_text.length / 4}}/m)

      # Initialize a ThreadPoolExecutor for summarizing parts
      part_thread_pool = Concurrent::ThreadPoolExecutor.new(min_threads: 1, max_threads: max_threads, max_queue: 0)

      # Summarize each part concurrently in 30 characters
      summarized_parts = Concurrent::Array.new

      parts.each do |part|
        part_thread_pool.post do
          summary_prompt = "Please summarize the following content in 30 characters: #{part}"
          summarized_parts.push(GPT3.gpt3_wrapper(summary_prompt).strip)
        end
      end

      part_thread_pool.shutdown
      part_thread_pool.wait_for_termination

      # Merge all the summarized parts for the final summary
      final_summary = summarized_parts.join(" ")
    else
      summary_prompt = "Please summarize the following content in #{final_summary_size} characters: #{summarized_text}"
      final_summary = GPT3.gpt3_wrapper(summary_prompt).strip
    end

    final_summary
  end

  def execute_tasks
    puts "\nTask List:"
    @tasks.each_with_index { |task, index| puts "#{index + 1}. #{task.description}" }

    previous_task = nil

    @tasks.each do |task|
      if previous_task
        task.add_context("Previous task description: #{previous_task.description},
          Previous task result: #{previous_task.gpt3_response}")
      end

      puts "\nExecuting task: #{task.description}\n\n"
      thinking(task)
      task.execute
      store_task(task)
      puts "\n\nResult: #{task.gpt3_response}"
      puts "\n"

      previous_task = task
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
