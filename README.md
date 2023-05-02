# AI Task Agent

This AI Task Agent is a simple Ruby script that utilizes OpenAI's GPT-3 to break down objectives into tasks, execute the tasks, and display the results. It is composed of three main components:

Agent: The main class that manages objectives, tasks, and responses.
GPT3: A wrapper around the OpenAI API to communicate with GPT-3.
Task: A class representing individual tasks that the agent needs to execute.
Requirements

To run this script, you need Ruby and the following gems installed:

dotenv
net/http

## Setup

Clone this repository.
Create a .env file in the project directory.
Add your OpenAI API key to the .env file as follows:

OPENAI_API_KEY=your_api_key_here

Replace your_api_key_here with your actual OpenAI API key.

## Running the Script

After setting up the project, run the main script using:

ruby agent.rb

The script will prompt you to provide an objective. The AI agent will then break down the objective into tasks, execute the tasks, and display the results.
