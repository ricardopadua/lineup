# Lineup

Lineup is a **multi-agent surf intelligence platform** that collects, validates and synthesizes surf conditions from multiple external providers into a single recommendation.

Rather than relying on sequential AI workflows, Lineup uses specialized agents to gather data concurrently while an LLM focuses only on reasoning over the collected information.

---

## Architecture

```
                   User
                     │
                     ▼
             Buddy (Reasoning)
                     │
      ┌──────────────┼──────────────┐
      ▼              ▼              ▼
    Waves        Weather         Tide
 WaterTemp       Traffic          Sun
                Spots
                     │
                     ▼
          Surf Recommendation
```

Each agent owns a single responsibility and can fail independently without affecting the rest of the system.

---

## Design

- **Multi-agent architecture** — Specialized agents collect domain-specific information.
- **Concurrent execution** — External APIs are queried in parallel to minimize latency.
- **Fault isolation** — Failures are contained within each agent.
- **Graceful degradation** — Recommendations are generated even when some providers fail.
- **Intelligent caching** — TTL cache with stale-data fallback improves resilience.
- **Bounded AI reasoning** — The LLM can re-query agents when needed while preventing infinite tool loops.

---

## Agents

| Agent | Responsibility |
|--------|----------------|
| Waves | Wave conditions |
| Weather | Weather forecast |
| Tide | Tide analysis |
| WaterTemp | Water temperature |
| Traffic | Travel time |
| Sun | Sunrise & sunset |
| Spots | Local surf knowledge |
| Buddy | Recommendation synthesis |

---

## Roadmap

- Intent-aware routing
- Geolocation resolution
- Spot ranking engine
- Historical surf analytics
- Event-driven processing

---

## Why Elixir?

Lineup explores **system design**, not just AI orchestration.

Elixir was chosen because its concurrency model naturally supports independent agents, fault isolation and resilient execution under unreliable network conditions.

---

## Quick Start

```bash
mix deps.get
mix run --no-halt
```

Configure your `LLM_API_KEY` before starting the application.