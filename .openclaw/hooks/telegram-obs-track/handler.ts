type ReceivedHookEvent = {
  type?: string;
  action?: string;
  context?: {
    from?: string;
    content?: string;
    channelId?: string;
    conversationId?: string;
    messageId?: string;
    metadata?: {
      senderName?: string;
      senderUsername?: string;
      senderId?: string;
      to?: string;
      threadId?: string | number;
    };
  };
};

type TrackPayload = {
  url?: string;
  query?: string;
};

const trackBridgeUrl =
  process.env.OPENCLAW_TRACK_BRIDGE_URL?.trim() || "http://127.0.0.1:7072/track";
const bridgeToken = process.env.OPENCLAW_STREAM_BRIDGE_TOKEN?.trim() || "";
const onlyGroups = parseBoolean(process.env.OPENCLAW_TRACK_ONLY_GROUPS, true);
const autoLinks = parseBoolean(process.env.OPENCLAW_TRACK_AUTO_LINKS, true);

const seenMessageIds = new Set<string>();
const seenMessageOrder: string[] = [];
const seenMessageLimit = 500;

function parseBoolean(raw: string | undefined, fallback: boolean): boolean {
  if (!raw) {
    return fallback;
  }
  const value = raw.trim().toLowerCase();
  if (["1", "true", "yes", "on"].includes(value)) {
    return true;
  }
  if (["0", "false", "no", "off"].includes(value)) {
    return false;
  }
  return fallback;
}

function rememberMessageId(messageId: string): void {
  if (seenMessageIds.has(messageId)) {
    return;
  }
  seenMessageIds.add(messageId);
  seenMessageOrder.push(messageId);
  if (seenMessageOrder.length <= seenMessageLimit) {
    return;
  }
  const oldest = seenMessageOrder.shift();
  if (oldest) {
    seenMessageIds.delete(oldest);
  }
}

function normalizeConversationId(raw: string | undefined): string {
  if (!raw) {
    return "";
  }
  if (raw.startsWith("telegram:")) {
    return raw.slice("telegram:".length);
  }
  if (raw.startsWith("chat:")) {
    return raw.slice("chat:".length);
  }
  return raw;
}

function looksLikeGroupConversation(raw: string | undefined): boolean {
  if (!raw) {
    return false;
  }
  const normalized = normalizeConversationId(raw);
  return (
    normalized.startsWith("-") ||
    normalized.includes(":topic:") ||
    raw.includes(":group:") ||
    raw.includes(":supergroup:") ||
    raw.includes(":chat:-") ||
    raw.includes(":topic:")
  );
}

function isTelegramGroupContext(context: NonNullable<ReceivedHookEvent["context"]>): boolean {
  if (looksLikeGroupConversation(context.conversationId)) {
    return true;
  }
  if (looksLikeGroupConversation(context.metadata?.to)) {
    return true;
  }
  const threadId = context.metadata?.threadId;
  if (threadId == null) {
    return false;
  }
  // Topic replies arrive with thread metadata separate from the canonical chat id.
  return looksLikeGroupConversation(context.conversationId || context.metadata?.to);
}

function cleanUrl(raw: string): string {
  return raw.replace(/[)>\],.!?;:'"`]+$/g, "");
}

function extractUrl(text: string): string | undefined {
  const match = text.match(/https?:\/\/\S+/i);
  if (!match) {
    return undefined;
  }
  const candidate = cleanUrl(match[0]);
  if (!candidate.startsWith("http://") && !candidate.startsWith("https://")) {
    return undefined;
  }
  return candidate;
}

function isSupportedTrackUrl(rawUrl: string): boolean {
  try {
    const parsed = new URL(rawUrl);
    const host = parsed.hostname.toLowerCase();
    return [
      "youtube.com",
      "www.youtube.com",
      "youtu.be",
      "music.youtube.com",
      "soundcloud.com",
      "on.soundcloud.com",
      "bandcamp.com",
      "www.bandcamp.com",
      "mixcloud.com",
      "www.mixcloud.com",
    ].some((value) => host === value || host.endsWith(`.${value}`));
  } catch {
    return false;
  }
}

function extractQuery(text: string): string | undefined {
  const trimmed = text.trim();
  const commandMatch = trimmed.match(
    /^(?:[!/])?(?:track|song|music|play|трек|музыка|включи|поставь)\s+(.+)$/iu,
  );
  if (!commandMatch) {
    return undefined;
  }
  const query = commandMatch[1]?.trim();
  if (!query) {
    return undefined;
  }
  if (query.length > 180) {
    return query.slice(0, 180).trim();
  }
  return query;
}

function resolveTrackPayload(text: string): TrackPayload | null {
  const url = extractUrl(text);
  if (
    url &&
    (autoLinks || /(?:[!/])?(?:track|song|music|play|трек|музыка|включи|поставь)/iu.test(text))
  ) {
    if (isSupportedTrackUrl(url)) {
      return { url };
    }
  }

  const query = extractQuery(text);
  if (query) {
    return { query };
  }

  return null;
}

function resolveSenderLabel(event: ReceivedHookEvent): string {
  const metadata = event.context?.metadata;
  if (typeof metadata?.senderUsername === "string" && metadata.senderUsername.trim()) {
    return `@${metadata.senderUsername.trim().replace(/^@+/, "")}`;
  }
  if (typeof metadata?.senderName === "string" && metadata.senderName.trim()) {
    return metadata.senderName.trim();
  }
  if (typeof metadata?.senderId === "string" && metadata.senderId.trim()) {
    return metadata.senderId.trim();
  }
  if (typeof event.context?.from === "string" && event.context.from.trim()) {
    return event.context.from.trim();
  }
  return "unknown";
}

const handler = async (event: ReceivedHookEvent) => {
  if (event.type !== "message" || event.action !== "received") {
    return;
  }

  const context = event.context;
  if (!context || context.channelId !== "telegram") {
    return;
  }

  if (onlyGroups && !isTelegramGroupContext(context)) {
    return;
  }

  if (typeof context.content !== "string") {
    return;
  }

  const messageId = typeof context.messageId === "string" ? context.messageId.trim() : "";
  if (messageId && seenMessageIds.has(messageId)) {
    return;
  }

  const text = context.content.trim();
  if (!text || /^[!/](?:help|new|reset|stop|status)\b/i.test(text)) {
    return;
  }

  const payload = resolveTrackPayload(text);
  if (!payload) {
    return;
  }

  if (messageId) {
    rememberMessageId(messageId);
  }

  const headers: Record<string, string> = {
    "content-type": "application/json",
  };
  if (bridgeToken) {
    headers.authorization = `Bearer ${bridgeToken}`;
  }

  try {
    const response = await fetch(trackBridgeUrl, {
      method: "POST",
      headers,
      body: JSON.stringify({
        ...payload,
        source: "openclaw.telegram.track",
        requestedBy: resolveSenderLabel(event),
        conversationId: context.conversationId,
        messageId,
      }),
    });

    if (!response.ok) {
      const body = await response.text().catch(() => "");
      console.warn(
        `[telegram-obs-track] bridge rejected request: status=${response.status} url=${trackBridgeUrl} body=${body}`,
      );
    }
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    console.warn(`[telegram-obs-track] failed to post track request: ${message}`);
  }
};

export default handler;
