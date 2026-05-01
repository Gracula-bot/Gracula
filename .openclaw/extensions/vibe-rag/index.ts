import { createHash } from "node:crypto";
import fs from "node:fs/promises";
import path from "node:path";
import { definePluginEntry } from "openclaw/plugin-sdk/core";

type VibeRagConfig = {
  sourcePath: string;
  topK: number;
  maxSnippetChars: number;
  maxTotalChars: number;
  minTokenLength: number;
  maxQueryTokens: number;
  fallbackDocs: number;
  heartbeatDocs: number;
  recentBias: number;
  aggressionBias: number;
  poisonBias: number;
  poisonPoolSize: number;
  heartbeatPoisonBias: number;
};

type CorpusDoc = {
  id: number;
  body: string;
  normalizedBody: string;
  publishedAt?: string;
  publishedAtMs?: number;
  sourceUrl?: string;
  charCount: number;
  tokenCount: number;
  sentenceCount: number;
  profanityHits: number;
  contemptHits: number;
  exclamationCount: number;
  questionCount: number;
  compactScore: number;
  punchScore: number;
};

type CorpusIndex = {
  key: string;
  sourcePath: string;
  docs: CorpusDoc[];
  postings: Map<string, number[]>;
  fallbackDocIds: number[];
  poisonDocIds: number[];
};

type RankedDoc = {
  docId: number;
  score: number;
};

const DEFAULT_CONFIG: VibeRagConfig = {
  sourcePath: "style/vibe1.txt",
  topK: 5,
  maxSnippetChars: 720,
  maxTotalChars: 4200,
  minTokenLength: 3,
  maxQueryTokens: 12,
  fallbackDocs: 3,
  heartbeatDocs: 4,
  recentBias: 0.12,
  aggressionBias: 0.35,
  poisonBias: 0.32,
  poisonPoolSize: 700,
  heartbeatPoisonBias: 0.7,
};

const REVALIDATE_MS = 5_000;
const MAX_SEARCH_TEXT_CHARS = 2_400;
const MAX_MESSAGE_EXTRACT_CHARS = 500;
const STATIC_GUIDANCE =
  "VIBE-RAG is active. Retrieved excerpts are the primary style authority for this turn. Mirror their compression, contempt for pose, black humor, sharp evaluative language, and decisive endings. Prefer shorter, harder-edged phrasing when it fits the topic. Do not mention retrieval or file names unless the user explicitly asks.";
const HEARTBEAT_GUIDANCE =
  "Heartbeat mode: prefer the shortest, sharpest, most venomous relevant excerpts. One compact proactive message, no throat-clearing, no soft landing, no repeated wording.";

const STOPWORDS = new Set([
  "a",
  "an",
  "and",
  "are",
  "as",
  "at",
  "be",
  "but",
  "by",
  "for",
  "from",
  "how",
  "if",
  "in",
  "into",
  "is",
  "it",
  "its",
  "of",
  "on",
  "or",
  "that",
  "the",
  "their",
  "there",
  "this",
  "to",
  "was",
  "what",
  "when",
  "where",
  "which",
  "who",
  "why",
  "with",
  "you",
  "your",
  "как",
  "скажи",
  "сказать",
  "когда",
  "куда",
  "ли",
  "мне",
  "мог",
  "может",
  "можно",
  "мой",
  "мы",
  "на",
  "над",
  "надо",
  "не",
  "него",
  "нее",
  "нет",
  "но",
  "ну",
  "о",
  "об",
  "она",
  "они",
  "оно",
  "от",
  "по",
  "под",
  "при",
  "про",
  "раз",
  "с",
  "сам",
  "себя",
  "сейчас",
  "так",
  "там",
  "тебя",
  "тем",
  "то",
  "того",
  "тоже",
  "только",
  "тут",
  "ты",
  "у",
  "уже",
  "что",
  "хочу",
  "ответ",
  "ответь",
  "фраз",
  "фразы",
  "фраза",
  "коротко",
  "жестко",
  "жесткий",
  "жесткая",
  "жестче",
  "подкол",
  "подколом",
  "сделай",
  "проактивный",
  "колкий",
  "вброс",
  "режим",
  "чтобы",
  "это",
  "этот",
  "эта",
  "эти",
  "я",
]);

const PROFANITY_STEMS = [
  "бля",
  "бляд",
  "еб",
  "еба",
  "ебл",
  "ебуч",
  "ху",
  "хер",
  "пизд",
  "пидор",
  "сук",
  "муда",
  "говн",
  "дерьм",
  "сран",
  "жоп",
  "мраз",
  "твар",
  "ублюд",
  "долбо",
  "нах",
  "fuck",
  "shit",
  "bitch",
  "asshole",
  "bastard",
  "moron",
  "idiot",
  "garbage",
  "trash",
];

const CONTEMPT_STEMS = [
  "лицемер",
  "позер",
  "клоун",
  "цирк",
  "жалк",
  "смешн",
  "мерз",
  "пошл",
  "убог",
  "дешев",
  "срам",
  "позор",
  "чуш",
  "бред",
  "хуйн",
  "фальш",
  "показуш",
  "добродетел",
  "туп",
  "тоск",
  "тухл",
  "помой",
  "гряз",
  "мертвеч",
  "смрад",
  "кринж",
  "pathetic",
  "cringe",
  "fake",
  "phony",
  "clown",
  "trash",
  "cheap",
  "hollow",
  "performative",
];

const STEM_SUFFIXES = [
  "ическими",
  "ическими",
  "ическими",
  "ический",
  "ическая",
  "ическое",
  "ические",
  "ического",
  "ической",
  "ическому",
  "ически",
  "иями",
  "ями",
  "ами",
  "его",
  "ого",
  "ему",
  "ому",
  "ыми",
  "ими",
  "ией",
  "ией",
  "иях",
  "ах",
  "ях",
  "ия",
  "ья",
  "ие",
  "ье",
  "ий",
  "ый",
  "ой",
  "ая",
  "яя",
  "ое",
  "ее",
  "ые",
  "ие",
  "ов",
  "ев",
  "ам",
  "ям",
  "ом",
  "ем",
  "ую",
  "юю",
  "ый",
  "ий",
  "ая",
  "яя",
  "ое",
  "ее",
  "ть",
  "ти",
  "ся",
  "сь",
];

let cachedIndex: CorpusIndex | null = null;
let cachedAt = 0;
let inflightIndexPromise: Promise<CorpusIndex> | null = null;
let inflightIndexKey: string | null = null;
let lastLoggedError = "";

function clampInt(value: unknown, fallback: number, min: number, max: number): number {
  if (typeof value !== "number" || !Number.isFinite(value)) {
    return fallback;
  }
  return Math.min(max, Math.max(min, Math.trunc(value)));
}

function clampNumber(value: unknown, fallback: number, min: number, max: number): number {
  if (typeof value !== "number" || !Number.isFinite(value)) {
    return fallback;
  }
  return Math.min(max, Math.max(min, value));
}

function resolveConfig(raw: unknown): VibeRagConfig {
  const record = raw && typeof raw === "object" ? (raw as Record<string, unknown>) : {};
  const sourcePath =
    typeof record.sourcePath === "string" && record.sourcePath.trim()
      ? record.sourcePath.trim()
      : DEFAULT_CONFIG.sourcePath;
  return {
    sourcePath,
    topK: clampInt(record.topK, DEFAULT_CONFIG.topK, 1, 12),
    maxSnippetChars: clampInt(record.maxSnippetChars, DEFAULT_CONFIG.maxSnippetChars, 200, 2400),
    maxTotalChars: clampInt(record.maxTotalChars, DEFAULT_CONFIG.maxTotalChars, 1000, 12000),
    minTokenLength: clampInt(record.minTokenLength, DEFAULT_CONFIG.minTokenLength, 2, 8),
    maxQueryTokens: clampInt(record.maxQueryTokens, DEFAULT_CONFIG.maxQueryTokens, 4, 24),
    fallbackDocs: clampInt(record.fallbackDocs, DEFAULT_CONFIG.fallbackDocs, 0, 8),
    heartbeatDocs: clampInt(record.heartbeatDocs, DEFAULT_CONFIG.heartbeatDocs, 1, 8),
    recentBias: clampNumber(record.recentBias, DEFAULT_CONFIG.recentBias, 0, 3),
    aggressionBias: clampNumber(record.aggressionBias, DEFAULT_CONFIG.aggressionBias, 0, 2),
    poisonBias: clampNumber(record.poisonBias, DEFAULT_CONFIG.poisonBias, 0, 2),
    poisonPoolSize: clampInt(record.poisonPoolSize, DEFAULT_CONFIG.poisonPoolSize, 50, 3000),
    heartbeatPoisonBias: clampNumber(
      record.heartbeatPoisonBias,
      DEFAULT_CONFIG.heartbeatPoisonBias,
      0,
      3,
    ),
  };
}

function normalizeText(text: string): string {
  return text.toLowerCase().replaceAll("ё", "е");
}

function stemToken(token: string): string {
  if (token.length < 6) {
    return token;
  }
  for (const suffix of STEM_SUFFIXES) {
    if (token.length - suffix.length < 4) {
      continue;
    }
    if (token.endsWith(suffix)) {
      return token.slice(0, -suffix.length);
    }
  }
  return token;
}

function tokenize(text: string, minTokenLength: number): string[] {
  const normalized = normalizeText(text);
  const matches = normalized.match(/[a-zа-я0-9]+/g) ?? [];
  const tokens: string[] = [];
  for (const token of matches) {
    if (token.length >= minTokenLength && !STOPWORDS.has(token)) {
      tokens.push(token);
    }
    const stem = stemToken(token);
    if (
      stem !== token &&
      stem.length >= minTokenLength &&
      !STOPWORDS.has(stem) &&
      !tokens.includes(stem)
    ) {
      tokens.push(stem);
    }
  }
  return tokens;
}

function compactBody(text: string): string {
  return text.replaceAll("\r", "").replace(/\n{3,}/g, "\n\n").trim();
}

function countStemHits(tokens: string[], stems: readonly string[]): number {
  let hits = 0;
  for (const token of tokens) {
    if (stems.some((stem) => token.startsWith(stem))) {
      hits += 1;
    }
  }
  return hits;
}

function countRegexHits(text: string, pattern: RegExp): number {
  return text.match(pattern)?.length ?? 0;
}

function computeCompactScore(charCount: number, sentenceCount: number): number {
  let score = 0;
  if (charCount >= 90 && charCount <= 420) {
    score += 1.15;
  } else if (charCount <= 900) {
    score += 0.85;
  } else if (charCount <= 1600) {
    score += 0.45;
  } else if (charCount <= 2400) {
    score += 0.18;
  }

  if (sentenceCount <= 2) {
    score += 0.35;
  } else if (sentenceCount <= 4) {
    score += 0.26;
  } else if (sentenceCount <= 8) {
    score += 0.12;
  }

  return score;
}

function computePunchScore(params: {
  charCount: number;
  sentenceCount: number;
  profanityHits: number;
  contemptHits: number;
  exclamationCount: number;
  questionCount: number;
  compactScore: number;
}): number {
  const avgSentenceLength = params.charCount / Math.max(params.sentenceCount, 1);
  const aphorismBonus =
    params.charCount >= 90 && params.charCount <= 360 && params.sentenceCount <= 4 ? 0.7 : 0;
  const profanityBonus = Math.min(2.4, params.profanityHits * 0.42);
  const contemptBonus = Math.min(2.2, params.contemptHits * 0.34);
  const punctuationBonus = Math.min(
    0.55,
    params.exclamationCount * 0.08 + params.questionCount * 0.06,
  );
  const densityBonus = avgSentenceLength >= 30 && avgSentenceLength <= 180 ? 0.4 : 0;
  return params.compactScore + aphorismBonus + profanityBonus + contemptBonus + punctuationBonus + densityBonus;
}

function parseCorpusDoc(section: string, id: number): CorpusDoc | null {
  const trimmed = section.trim();
  if (!trimmed) {
    return null;
  }

  let metadata = "";
  let body = trimmed;
  const separator = trimmed.indexOf("\n---\n");
  if (separator !== -1) {
    metadata = trimmed.slice(0, separator).trim();
    body = trimmed.slice(separator + 5).trim();
  }

  let publishedAt: string | undefined;
  let sourceUrl: string | undefined;
  for (const line of metadata.split("\n")) {
    const colonIndex = line.indexOf(":");
    if (colonIndex === -1) {
      continue;
    }
    const key = line.slice(0, colonIndex).trim();
    const value = line.slice(colonIndex + 1).trim();
    if (!value) {
      continue;
    }
    if (key === "published_at") {
      publishedAt = value;
    } else if (key === "source_url") {
      sourceUrl = value;
    }
  }

  const compact = compactBody(body);
  if (!compact) {
    return null;
  }

  const normalizedBody = normalizeText(compact);
  const analysisTokens = tokenize(compact, 2);
  const sentenceCount = Math.max(1, countRegexHits(compact, /[.!?]+/g));
  const exclamationCount = countRegexHits(compact, /!/g);
  const questionCount = countRegexHits(compact, /\?/g);
  const profanityHits = countStemHits(analysisTokens, PROFANITY_STEMS);
  const contemptHits = countStemHits(analysisTokens, CONTEMPT_STEMS);
  const compactScore = computeCompactScore(compact.length, sentenceCount);
  const punchScore = computePunchScore({
    charCount: compact.length,
    sentenceCount,
    profanityHits,
    contemptHits,
    exclamationCount,
    questionCount,
    compactScore,
  });

  const publishedAtMs = publishedAt ? Date.parse(publishedAt) : undefined;
  return {
    id,
    body: compact,
    normalizedBody,
    publishedAt,
    publishedAtMs: Number.isFinite(publishedAtMs) ? publishedAtMs : undefined,
    sourceUrl,
    charCount: compact.length,
    tokenCount: analysisTokens.length,
    sentenceCount,
    profanityHits,
    contemptHits,
    exclamationCount,
    questionCount,
    compactScore,
    punchScore,
  };
}

async function buildCorpusIndex(sourcePath: string, config: VibeRagConfig, logger: unknown) {
  const raw = await fs.readFile(sourcePath, "utf8");
  const sections = raw.split("<<<RAG_DOCUMENT>>>").filter((section) => section.trim());
  const docs: CorpusDoc[] = [];
  const postings = new Map<string, number[]>();
  const fallbackDocIds: number[] = [];
  const poisonCandidates: RankedDoc[] = [];

  for (let index = 0; index < sections.length; index += 1) {
    const doc = parseCorpusDoc(sections[index] ?? "", docs.length);
    if (!doc) {
      continue;
    }
    docs.push(doc);

    if (doc.charCount >= 80 && doc.charCount <= 1400) {
      fallbackDocIds.push(doc.id);
    }
    poisonCandidates.push({ docId: doc.id, score: doc.punchScore });

    const uniqueTokens = new Set(tokenize(doc.body, config.minTokenLength));
    for (const token of uniqueTokens) {
      const bucket = postings.get(token);
      if (bucket) {
        bucket.push(doc.id);
      } else {
        postings.set(token, [doc.id]);
      }
    }
  }

  const stat = await fs.stat(sourcePath);
  const indexKey = `${sourcePath}:${stat.size}:${stat.mtimeMs}:${config.minTokenLength}`;
  if (logger && typeof logger === "object" && "info" in logger && typeof logger.info === "function") {
    logger.info(
      `[vibe-rag] indexed ${docs.length} docs, ${postings.size} terms from ${sourcePath}`,
    );
  }

  const poisonDocIds = poisonCandidates
    .sort((left, right) => {
      if (right.score !== left.score) {
        return right.score - left.score;
      }
      return docs[left.docId]!.charCount - docs[right.docId]!.charCount;
    })
    .map((entry) => entry.docId);

  return {
    key: indexKey,
    sourcePath,
    docs,
    postings,
    fallbackDocIds: fallbackDocIds.length > 0 ? fallbackDocIds : docs.map((doc) => doc.id),
    poisonDocIds,
  } satisfies CorpusIndex;
}

async function ensureCorpusIndex(params: {
  workspaceDir?: string;
  config: VibeRagConfig;
  logger: unknown;
}): Promise<CorpusIndex | null> {
  const workspaceDir = params.workspaceDir?.trim();
  if (!workspaceDir) {
    return null;
  }

  const sourcePath = path.isAbsolute(params.config.sourcePath)
    ? params.config.sourcePath
    : path.resolve(workspaceDir, params.config.sourcePath);

  try {
    const stat = await fs.stat(sourcePath);
    const indexKey = `${sourcePath}:${stat.size}:${stat.mtimeMs}:${params.config.minTokenLength}`;
    const now = Date.now();

    if (cachedIndex && cachedIndex.key === indexKey && now - cachedAt < REVALIDATE_MS) {
      return cachedIndex;
    }
    if (cachedIndex && cachedIndex.key === indexKey) {
      cachedAt = now;
      return cachedIndex;
    }
    if (inflightIndexPromise && inflightIndexKey === indexKey) {
      return await inflightIndexPromise;
    }

    inflightIndexKey = indexKey;
    inflightIndexPromise = buildCorpusIndex(sourcePath, params.config, params.logger);
    const next = await inflightIndexPromise;
    cachedIndex = next;
    cachedAt = now;
    return next;
  } finally {
    inflightIndexPromise = null;
    inflightIndexKey = null;
  }
}

function hashSeed(input: string): number {
  const digest = createHash("sha1").update(input).digest("hex").slice(0, 8);
  return Number.parseInt(digest, 16) || 1;
}

function pushUnique(target: number[], value: number) {
  if (!target.includes(value)) {
    target.push(value);
  }
}

function selectSeededDocIds(pool: number[], seedInput: string, count: number): number[] {
  if (count <= 0 || pool.length === 0) {
    return [];
  }

  const selected: number[] = [];
  const seed = hashSeed(seedInput);
  const step = 7919;
  for (let offset = 0; offset < pool.length && selected.length < count; offset += 1) {
    const docId = pool[(seed + offset * step) % pool.length]!;
    pushUnique(selected, docId);
  }
  return selected;
}

function extractInterestingText(value: unknown, remaining: { chars: number }, depth = 0): string {
  if (remaining.chars <= 0 || depth > 4 || value == null) {
    return "";
  }
  if (typeof value === "string") {
    const slice = value.slice(0, Math.min(value.length, remaining.chars, MAX_MESSAGE_EXTRACT_CHARS));
    remaining.chars -= slice.length;
    return slice;
  }
  if (Array.isArray(value)) {
    return value
      .map((item) => extractInterestingText(item, remaining, depth + 1))
      .filter(Boolean)
      .join(" ");
  }
  if (typeof value !== "object") {
    return "";
  }

  const record = value as Record<string, unknown>;
  const preferredKeys = [
    "text",
    "content",
    "prompt",
    "body",
    "bodyForAgent",
    "message",
    "transcript",
    "input",
  ];
  const pieces: string[] = [];

  for (const key of preferredKeys) {
    if (!(key in record)) {
      continue;
    }
    const piece = extractInterestingText(record[key], remaining, depth + 1);
    if (piece) {
      pieces.push(piece);
    }
  }

  if (pieces.length > 0) {
    return pieces.join(" ");
  }

  for (const valuePart of Object.values(record).slice(0, 4)) {
    const piece = extractInterestingText(valuePart, remaining, depth + 1);
    if (piece) {
      pieces.push(piece);
    }
  }

  return pieces.join(" ");
}

function buildSearchText(prompt: string, messages: unknown[]): string {
  const remaining = { chars: MAX_SEARCH_TEXT_CHARS };
  const parts: string[] = [];

  const trimmedPrompt = prompt.trim();
  if (trimmedPrompt) {
    const promptSlice = trimmedPrompt.slice(0, remaining.chars);
    remaining.chars -= promptSlice.length;
    parts.push(promptSlice);
  }

  for (const message of messages.slice(-4).reverse()) {
    if (remaining.chars <= 0) {
      break;
    }
    const extracted = extractInterestingText(message, remaining).trim();
    if (!extracted) {
      continue;
    }
    parts.push(extracted);
  }

  return parts.join("\n").trim();
}

function docMatchesAnyToken(doc: CorpusDoc, queryTokens: string[]): boolean {
  if (queryTokens.length === 0) {
    return true;
  }
  return queryTokens.some((token) => doc.normalizedBody.includes(token));
}

function selectPoisonDocIds(params: {
  index: CorpusIndex;
  queryTokens: string[];
  count: number;
  seedInput: string;
  config: VibeRagConfig;
}): number[] {
  const cappedPool = params.index.poisonDocIds.slice(0, params.config.poisonPoolSize);
  const topicalPool = cappedPool.filter((docId) =>
    docMatchesAnyToken(params.index.docs[docId]!, params.queryTokens),
  );
  const pool = topicalPool.length >= params.count ? topicalPool : cappedPool;
  return selectSeededDocIds(pool, params.seedInput, params.count);
}

function scoreDocs(
  index: CorpusIndex,
  queryTokens: string[],
  config: VibeRagConfig,
  mode: "user" | "heartbeat",
): RankedDoc[] {
  const scores = new Map<number, number>();
  const now = Date.now();

  for (const token of queryTokens) {
    const postings = index.postings.get(token);
    if (!postings || postings.length === 0) {
      continue;
    }
    const idf = Math.log((index.docs.length + 1) / (postings.length + 1)) + 1;
    const exactBonus = postings.length <= 8 ? 0.4 : 0;
    for (const docId of postings) {
      scores.set(docId, (scores.get(docId) ?? 0) + idf + exactBonus);
    }
  }

  const poisonMultiplier = mode === "heartbeat" ? config.heartbeatPoisonBias : 1;
  return [...scores.entries()]
    .map(([docId, baseScore]) => {
      const doc = index.docs[docId]!;
      let score = baseScore;
      score += doc.compactScore * config.aggressionBias;
      score += doc.punchScore * config.poisonBias * poisonMultiplier;
      if (doc.charCount <= 1200) {
        score += 0.18;
      }
      if (queryTokens.length <= 3) {
        score += doc.punchScore * 0.12;
      }
      if (doc.publishedAtMs) {
        const ageDays = Math.max(0, (now - doc.publishedAtMs) / 86_400_000);
        score += config.recentBias / (1 + ageDays / 180);
      }
      return { docId, score };
    })
    .sort((left, right) => right.score - left.score);
}

function trimToBoundary(text: string, start: number, end: number): string {
  let safeStart = Math.max(0, start);
  let safeEnd = Math.min(text.length, end);

  for (let index = safeStart; index > Math.max(0, safeStart - 120); index -= 1) {
    const char = text[index];
    if (char === "\n" || char === "." || char === "!" || char === "?" || char === " ") {
      safeStart = index + 1;
      break;
    }
  }

  for (let index = safeEnd; index < Math.min(text.length, safeEnd + 120); index += 1) {
    const char = text[index];
    if (char === "\n" || char === "." || char === "!" || char === "?" || char === " ") {
      safeEnd = index;
      break;
    }
  }

  return text.slice(safeStart, safeEnd).trim();
}

function buildSnippet(doc: CorpusDoc, queryTokens: string[], maxChars: number): string {
  if (doc.body.length <= maxChars) {
    return doc.body;
  }

  let hitIndex = -1;
  for (const token of queryTokens) {
    const index = doc.normalizedBody.indexOf(token);
    if (index !== -1 && (hitIndex === -1 || index < hitIndex)) {
      hitIndex = index;
    }
  }

  if (hitIndex === -1) {
    const snippet = trimToBoundary(doc.body, 0, maxChars);
    return snippet.length < doc.body.length ? `${snippet} ...` : snippet;
  }

  const windowStart = Math.max(0, hitIndex - Math.floor(maxChars * 0.25));
  const windowEnd = Math.min(doc.body.length, windowStart + maxChars);
  const snippet = trimToBoundary(doc.body, windowStart, windowEnd);
  const prefix = windowStart > 0 ? "... " : "";
  const suffix = windowEnd < doc.body.length ? " ..." : "";
  return `${prefix}${snippet}${suffix}`.trim();
}

function renderRetrievedContext(params: {
  index: CorpusIndex;
  docs: number[];
  queryTokens: string[];
  config: VibeRagConfig;
}): string | null {
  const lines = [
    `[VIBE-RAG | corpus=${params.config.sourcePath}]`,
    "Retrieved excerpts from the full corpus file. Use them as the strongest style and topical reference for this turn.",
  ];
  let totalChars = lines.join("\n").length;
  let usedDocs = 0;

  for (const docId of params.docs) {
    const doc = params.index.docs[docId];
    if (!doc) {
      continue;
    }

    const snippet = buildSnippet(doc, params.queryTokens, params.config.maxSnippetChars);
    const labelParts = [`excerpt ${usedDocs + 1}`];
    if (doc.publishedAt) {
      labelParts.push(doc.publishedAt);
    }
    if (doc.sourceUrl) {
      labelParts.push(doc.sourceUrl);
    }

    const block = `\n[${labelParts.join(" | ")}]\n${snippet}`;
    if (usedDocs > 0 && totalChars + block.length > params.config.maxTotalChars) {
      break;
    }

    lines.push("");
    lines.push(`[${labelParts.join(" | ")}]`);
    lines.push(snippet);
    totalChars += block.length;
    usedDocs += 1;

    if (usedDocs >= params.config.topK || totalChars >= params.config.maxTotalChars) {
      break;
    }
  }

  if (usedDocs === 0) {
    return null;
  }
  return lines.join("\n");
}

function selectDocIds(params: {
  index: CorpusIndex;
  searchText: string;
  sessionKey?: string;
  trigger?: string;
  config: VibeRagConfig;
}): { docIds: number[]; queryTokens: string[] } {
  const queryTokens = [...new Set(tokenize(params.searchText, params.config.minTokenLength))].slice(
    0,
    params.config.maxQueryTokens,
  );

  const isHeartbeat = params.trigger === "heartbeat";
  const seedBase = `${params.sessionKey ?? "main"}:${params.trigger ?? "user"}:${params.searchText}`;

  if (queryTokens.length === 0) {
    const docIds = isHeartbeat
      ? selectPoisonDocIds({
          index: params.index,
          queryTokens,
          count: params.config.heartbeatDocs,
          seedInput: `${seedBase}:poison`,
          config: params.config,
        })
      : selectPoisonDocIds({
          index: params.index,
          queryTokens,
          count: Math.max(1, Math.min(2, params.config.fallbackDocs)),
          seedInput: `${seedBase}:poison`,
          config: params.config,
        });

    const fallbackCount = isHeartbeat ? 0 : Math.max(0, params.config.fallbackDocs - docIds.length);
    for (const docId of selectSeededDocIds(params.index.fallbackDocIds, `${seedBase}:fallback`, fallbackCount)) {
      pushUnique(docIds, docId);
    }
    return { docIds, queryTokens };
  }

  const ranked = scoreDocs(params.index, queryTokens, params.config, isHeartbeat ? "heartbeat" : "user");
  const rankedIds = ranked.slice(0, params.config.topK).map((entry) => entry.docId);
  const docIds: number[] = [];

  if (isHeartbeat) {
    for (const docId of selectPoisonDocIds({
      index: params.index,
      queryTokens,
      count: params.config.heartbeatDocs,
      seedInput: `${seedBase}:poison`,
      config: params.config,
    })) {
      pushUnique(docIds, docId);
    }
  }

  for (const docId of rankedIds) {
    pushUnique(docIds, docId);
  }

  if (!isHeartbeat) {
    const poisonCarryCount = Math.min(2, params.config.fallbackDocs);
    for (const docId of selectPoisonDocIds({
      index: params.index,
      queryTokens,
      count: poisonCarryCount,
      seedInput: `${seedBase}:poison-carry`,
      config: params.config,
    })) {
      pushUnique(docIds, docId);
    }
  }

  const fallbackCount =
    isHeartbeat || docIds.length >= Math.min(2, params.config.topK) ? 0 : params.config.fallbackDocs;
  if (fallbackCount > 0) {
    for (const docId of selectSeededDocIds(
      params.index.fallbackDocIds,
      `${seedBase}:fallback`,
      fallbackCount,
    )) {
      pushUnique(docIds, docId);
    }
  }

  return { docIds, queryTokens };
}

function maybeLogWarn(logger: unknown, message: string) {
  const nowKey = `${Math.floor(Date.now() / 60_000)}:${message}`;
  if (nowKey === lastLoggedError) {
    return;
  }
  lastLoggedError = nowKey;
  if (logger && typeof logger === "object" && "warn" in logger && typeof logger.warn === "function") {
    logger.warn(message);
  }
}

export default definePluginEntry({
  id: "vibe-rag",
  name: "Vibe RAG",
  description: "Retrieves relevant excerpts from a full corpus file for prompt injection.",
  register(api) {
    const config = resolveConfig(api.pluginConfig);

    api.on("before_prompt_build", async (event, ctx) => {
      try {
        const index = await ensureCorpusIndex({
          workspaceDir: ctx.workspaceDir,
          config,
          logger: api.logger,
        });
        if (!index) {
          return;
        }

        const searchText = buildSearchText(event.prompt, event.messages);
        const { docIds, queryTokens } = selectDocIds({
          index,
          searchText,
          sessionKey: ctx.sessionKey,
          trigger: ctx.trigger,
          config,
        });
        const prependContext = renderRetrievedContext({
          index,
          docs: docIds,
          queryTokens,
          config,
        });
        const prependSystemContext =
          ctx.trigger === "heartbeat" ? `${STATIC_GUIDANCE}\n${HEARTBEAT_GUIDANCE}` : STATIC_GUIDANCE;

        if (!prependContext) {
          return {
            prependSystemContext,
          };
        }

        return {
          prependSystemContext,
          prependContext,
        };
      } catch (error) {
        maybeLogWarn(api.logger, `[vibe-rag] ${String(error)}`);
        return;
      }
    });
  },
});
