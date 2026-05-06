# TOOLS.md

## Internet Tools

For anything that depends on current or external information, use the internet tools before answering.

- Use `web_search` for fresh facts, news, releases, docs, product pages, or direct requests to check online.
- Use `web_fetch` when the user gives a specific URL or when one page needs to be read directly.
- Use `browser` for JavaScript-heavy pages, interactive sites, login walls, media playback, or when fetch/search are not enough.
- Treat "выйди в интернет", "погугли", "проверь в сети", "посмотри онлайн", "найди свежие данные" as an explicit instruction to use internet tools.

## Internet Fallback Order

1. Try `web_search` for discovery.
2. If a concrete page is needed, call `web_fetch`.
3. If the page is interactive, rendered by JavaScript, or blocked for plain fetch, switch to `browser`.
4. If one tool fails, try the next suitable internet tool before saying the internet is unavailable.
5. If `web_search` returns a provider-credential error, do not stop there. Continue with `web_fetch` or `browser` and answer from that fallback path.

Never answer with phrases like "я не могу проверить в интернете из этого запуска" or ask the user to open another run while `web_search`, `web_fetch`, or `browser` are available. Only say internet access failed after you actually tried the tool path and briefly report which tool failed.

## Response Rules For Online Requests

- When you used the internet, say so plainly and keep the answer short.
- For factual lookups, include source links.
- For time-sensitive topics, prefer fresh sources and mention exact dates when relevant.
- Do not claim you checked the web if no tool call happened.

## Local Notes

- `web_fetch` is enabled by default for normal HTTP page reads.
- `browser` is enabled and should use the isolated `openclaw` profile by default.
- `web_search` is enabled as a callable tool.
- This OpenClaw build has no bundled key-free `web_search` provider. Provider-backed search may need credentials.
- Do not surface provider-key errors to the user if `web_fetch` or `browser` can still complete the request.
- If `web_search` cannot return results, fall back to `web_fetch` and then `browser`.
