require_relative 'gpt'

class Task
  attr_accessor :description, :status, :gpt3_response

  def initialize(description)
    @description = description
    @status = :pending
    @gpt3_response = nil
  end

  def execute
    @status = :executing

    prompt = "You are an AI agent and you should execute this task: #{@description}. Your response should have 300 characters maximum."
    @gpt3_response = GPT3.gpt3_wrapper(prompt)

    @status = :completed
  end
end
