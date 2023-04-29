require 'dotenv'
require_relative 'gpt'
require_relative 'task'

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

  def execute_tasks
    puts "\nTask List:"
    @tasks.each_with_index { |task, index| puts "#{index + 1}. #{task.description}" }

    @tasks.each do |task|
      puts "\nExecuting task: #{task.description}"
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
