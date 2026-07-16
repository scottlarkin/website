ExUnit.start()

AgentBackend.LLM.Fake.setup()
AgentBackend.Slack.Fake.setup()

dir = Application.get_env(:agent_backend, :chat_sessions_dir)
File.rm_rf!(dir)
File.mkdir_p!(dir)
