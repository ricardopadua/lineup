import Config

config :lineup,
  agent_max_attempts: 3,
  agent_base_backoff_ms: 200,
  agent_failure_threshold: 5,
  agent_open_cooldown_ms: :timer.seconds(30),
  session_idle_timeout_ms: :timer.minutes(30)

if config_env() == :test do
  config :lineup,
    agent_base_backoff_ms: 5,
    agent_failure_threshold: 3,
    agent_open_cooldown_ms: 200,
    session_idle_timeout_ms: 100
end
