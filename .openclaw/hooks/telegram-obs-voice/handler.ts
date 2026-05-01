type HookEvent = {
  type?: string;
  action?: string;
  sessionKey?: string;
  context?: {
    success?: boolean;
    channelId?: string;
    to?: string;
    conversationId?: string;
    isGroup?: boolean;
    content?: string;
  };
};

const bridgeUrl =
  process.env.OPENCLAW_STREAM_BRIDGE_URL?.trim() || "http://127.0.0.1:7070/speak";
const bridgeToken = process.env.OPENCLAW_STREAM_BRIDGE_TOKEN?.trim() || "";
const minChars = parsePositiveInt(process.env.OPENCLAW_STREAM_MIN_CHARS, 20);
const maxChars = parsePositiveInt(process.env.OPENCLAW_STREAM_MAX_CHARS, 500);
const requireTelegramSessionKey = parseBoolean(
  process.env.OPENCLAW_STREAM_REQUIRE_TELEGRAM_SESSION_KEY,
  true,
);
const ignoreMainSession = parseBoolean(process.env.OPENCLAW_STREAM_IGNORE_MAIN_SESSION, true);
const ignoreTechnicalText = parseBoolean(process.env.OPENCLAW_STREAM_IGNORE_TECH_TEXT, true);
const blockedPhrases = parseBlockedPhraseList(process.env.OPENCLAW_STREAM_BLOCKED_PHRASES);

function parsePositiveInt(raw: string | undefined, fallback: number): number {
  if (!raw) {return fallback;}
  const parsed = Number.parseInt(raw, 10);
  if (!Number.isFinite(parsed) || parsed <= 0) {
    return fallback;
  }
  return parsed;
}

function parseBoolean(raw: string | undefined, fallback: boolean): boolean {
  if (!raw) {
    return fallback;
  }
  const normalized = raw.trim().toLowerCase();
  if (["1", "true", "yes", "on"].includes(normalized)) {
    return true;
  }
  if (["0", "false", "no", "off"].includes(normalized)) {
    return false;
  }
  return fallback;
}

function parseBlockedPhraseList(raw: string | undefined): string[] {
  if (!raw) {
    return [];
  }
  return raw
    .split(",")
    .map((part) => part.trim().toLowerCase())
    .filter(Boolean);
}

function normalizeSpeechText(input: string): string {
  return input
    .replace(/\[\[[\s\S]*?\]\]/g, " ")
    .replace(/<media:[^>]+>/g, " ")
    .replace(/\s+/g, " ")
    .trim();
}

function shouldSkipSpeechText(input: string): boolean {
  const lowered = input.toLowerCase();
  if (lowered.includes("no response generated. please try again.")) {
    return true;
  }
  if (lowered.includes("something went wrong while processing your request")) {
    return true;
  }
  if (/^\s*[\/!]/.test(input)) {
    return true;
  }
  if (ignoreTechnicalText) {
    if (
      /^(тех(?:проверка|тест)|проверка|тест|диагностик[а-я]*)\b/i.test(input) &&
      /(tts|voice|audio|obs|bridge|стрим|озвучк)/i.test(input)
    ) {
      return true;
    }
  }
  if (blockedPhrases.some((phrase) => lowered.includes(phrase))) {
    return true;
  }
  return false;
}

function shouldSkipBySession(event: HookEvent): boolean {
  const sessionKey = event.sessionKey?.trim() || "";
  if (!sessionKey) {
    return requireTelegramSessionKey;
  }
  if (ignoreMainSession && sessionKey === "agent:main:main") {
    return true;
  }
  if (requireTelegramSessionKey && !sessionKey.includes(":telegram:")) {
    return true;
  }
  return false;
}

const handler = async (event: HookEvent) => {
  if (event.type !== "message" || event.action !== "sent") {
    return;
  }

  const ctx = event.context ?? {};
  if (ctx.success === false) {
    return;
  }
  if (ctx.channelId !== "telegram") {
    return;
  }
  if (shouldSkipBySession(event)) {
    return;
  }
  if (typeof ctx.content !== "string") {
    return;
  }

  const normalized = normalizeSpeechText(ctx.content);
  if (normalized.length < minChars) {
    return;
  }
  if (shouldSkipSpeechText(normalized)) {
    return;
  }
  const clipped =
    normalized.length > maxChars
      ? `${normalized.slice(0, Math.max(1, maxChars - 3))}...`
      : normalized;

  const headers: Record<string, string> = {
    "content-type": "application/json",
  };
  if (bridgeToken) {
    headers.authorization = `Bearer ${bridgeToken}`;
  }

  try {
    const response = await fetch(bridgeUrl, {
      method: "POST",
      headers,
      body: JSON.stringify({
        text: clipped,
        source: "openclaw.telegram",
      }),
    });
    if (!response.ok) {
      console.warn(
        `[telegram-obs-voice] bridge rejected payload: status=${response.status} url=${bridgeUrl}`,
      );
    }
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    console.warn(`[telegram-obs-voice] failed to post to bridge: ${message}`);
  }
};

export default handler;
