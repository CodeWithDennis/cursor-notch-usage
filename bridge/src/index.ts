import { DatabaseSync } from "node:sqlite";
import { existsSync, readFileSync } from "node:fs";
import { createServer, type IncomingMessage, type ServerResponse } from "node:http";
import { dirname, join, resolve } from "node:path";
import { homedir } from "node:os";
import { fileURLToPath } from "node:url";

const API_VERSION = 1;
const PORT = Number(process.env.BRIDGE_PORT ?? 4318);
const USAGE_TTL_MS = 60_000;
const USAGE_POLL_MS = 60_000;
const CURSOR_STATE_DB = join(homedir(), "Library/Application Support/Cursor/User/globalStorage/state.vscdb");
const USAGE_API =
  "https://api2.cursor.sh/aiserver.v1.DashboardService/GetCurrentPeriodUsage";

type UsageDTO = {
  membership: string;
  totalPercentUsed: number;
  autoPercentUsed: number;
  apiPercentUsed: number;
  includedSpendCents: number;
  limitCents: number;
  remainingCents: number;
  cycleRemainingLabel: string;
  label: string;
};

let cachedUsage: UsageDTO | null = null;
let usageFetchedAt = 0;
let lastSnapshotEncoded = "";
const sseClients = new Set<ServerResponse>();

const here = dirname(fileURLToPath(import.meta.url));
for (const candidate of [
  resolve(here, "../../.env"),
  resolve(here, "../.env"),
  resolve(process.cwd(), ".env"),
  resolve(process.cwd(), "../.env"),
]) {
  if (!existsSync(candidate)) continue;
  for (const line of readFileSync(candidate, "utf8").split("\n")) {
    const trimmed = line.trim();
    if (!trimmed || trimmed.startsWith("#")) continue;
    const eq = trimmed.indexOf("=");
    if (eq <= 0) continue;
    const key = trimmed.slice(0, eq).trim();
    let value = trimmed.slice(eq + 1).trim();
    if (
      (value.startsWith('"') && value.endsWith('"')) ||
      (value.startsWith("'") && value.endsWith("'"))
    ) {
      value = value.slice(1, -1);
    }
    if (!(key in process.env)) process.env[key] = value;
  }
  break;
}

function readCursorStateValue(key: string): string | null {
  if (!existsSync(CURSOR_STATE_DB)) return null;
  let db: DatabaseSync | undefined;
  try {
    db = new DatabaseSync(CURSOR_STATE_DB, { readOnly: true });
    const row = db.prepare("SELECT value FROM ItemTable WHERE key = ?").get(key) as
      | { value?: unknown }
      | undefined;
    if (typeof row?.value === "string" && row.value.trim()) return row.value.trim();
    return null;
  } catch {
    return null;
  } finally {
    try {
      db?.close();
    } catch {
      // ignore
    }
  }
}

function formatDurationCompact(ms: number): string {
  if (!Number.isFinite(ms) || ms <= 0) return "";
  const totalMinutes = Math.floor(ms / 60_000);
  const days = Math.floor(totalMinutes / (60 * 24));
  const hours = Math.floor((totalMinutes % (60 * 24)) / 60);
  const minutes = totalMinutes % 60;
  if (days >= 2) return `${days}d`;
  if (days === 1) return hours > 0 ? `1d${hours}h` : "1d";
  if (hours > 0) return minutes > 0 ? `${hours}h${minutes}m` : `${hours}h`;
  return `${Math.max(1, minutes)}m`;
}

function formatUsageLabel(usage: Omit<UsageDTO, "label">): string {
  const auto = Math.round(usage.autoPercentUsed);
  const api = Math.round(usage.apiPercentUsed);
  const cycle = usage.cycleRemainingLabel ? ` ${usage.cycleRemainingLabel}` : "";
  return `Auto ${auto}% | API ${api}%${cycle}`;
}

async function withTimeout<T>(promise: Promise<T>, ms: number, fallback: T): Promise<T> {
  let timer: ReturnType<typeof setTimeout> | undefined;
  try {
    return await Promise.race([
      promise,
      new Promise<T>((resolve) => {
        timer = setTimeout(() => resolve(fallback), ms);
      }),
    ]);
  } finally {
    if (timer) clearTimeout(timer);
  }
}

async function fetchCursorUsage(force = false): Promise<UsageDTO | null> {
  if (!force && cachedUsage && Date.now() - usageFetchedAt < USAGE_TTL_MS) {
    return cachedUsage;
  }

  const token = readCursorStateValue("cursorAuth/accessToken");
  if (!token) return cachedUsage;

  try {
    const res = await withTimeout(
      fetch(USAGE_API, {
        method: "POST",
        headers: {
          Authorization: `Bearer ${token}`,
          "Content-Type": "application/json",
          "Connect-Protocol-Version": "1",
        },
        body: "{}",
        signal: AbortSignal.timeout(2500),
      }),
      3000,
      null
    );
    if (!res || !res.ok) return cachedUsage;

    const data = (await withTimeout(
      res.json() as Promise<{
        billingCycleEnd?: string | number;
        planUsage?: {
          totalSpend?: number;
          includedSpend?: number;
          bonusSpend?: number;
          limit?: number;
          remaining?: number;
          autoPercentUsed?: number;
          apiPercentUsed?: number;
          totalPercentUsed?: number;
        };
      }>,
      2000,
      null
    )) as {
      billingCycleEnd?: string | number;
      planUsage?: {
        totalSpend?: number;
        includedSpend?: number;
        bonusSpend?: number;
        limit?: number;
        remaining?: number;
        autoPercentUsed?: number;
        apiPercentUsed?: number;
        totalPercentUsed?: number;
      };
    } | null;
    if (!data?.planUsage) return cachedUsage;

    const plan = data.planUsage;
    const limitCents = Number(plan.limit ?? 0);
    const includedSpendCents = Number(plan.includedSpend ?? plan.totalSpend ?? 0);
    const remainingCents =
      typeof plan.remaining === "number"
        ? Math.max(0, plan.remaining)
        : Math.max(0, limitCents - includedSpendCents);
    const membership = readCursorStateValue("cursorAuth/stripeMembershipType") || "cursor";
    const cycleEndMs = Number(data.billingCycleEnd ?? 0);
    const cycleRemainingLabel =
      cycleEndMs > Date.now() ? formatDurationCompact(cycleEndMs - Date.now()) : "";
    const next: UsageDTO = {
      membership,
      totalPercentUsed: Number(plan.totalPercentUsed ?? 0),
      autoPercentUsed: Number(plan.autoPercentUsed ?? 0),
      apiPercentUsed: Number(plan.apiPercentUsed ?? 0),
      includedSpendCents,
      limitCents,
      remainingCents,
      cycleRemainingLabel,
      label: "",
    };
    next.label = formatUsageLabel(next);
    cachedUsage = next;
    usageFetchedAt = Date.now();
    publishSnapshot(cachedUsage);
    return cachedUsage;
  } catch {
    return cachedUsage;
  }
}

function snapshotEncoded(usage: UsageDTO | null): string {
  return JSON.stringify({ usage });
}

function publishSnapshot(usage: UsageDTO | null): void {
  const encoded = snapshotEncoded(usage);
  if (encoded === lastSnapshotEncoded) return;
  lastSnapshotEncoded = encoded;
  const payload = `data: ${encoded}\n\n`;
  for (const client of [...sseClients]) {
    try {
      client.write(payload);
    } catch {
      sseClients.delete(client);
    }
  }
}

function sendJson(res: ServerResponse, status: number, body: unknown): void {
  const payload = JSON.stringify(body);
  res.writeHead(status, {
    "Content-Type": "application/json",
    "Cache-Control": "no-store",
  });
  res.end(payload);
}

const server = createServer(async (req: IncomingMessage, res: ServerResponse) => {
  const url = new URL(req.url ?? "/", `http://127.0.0.1:${PORT}`);

  if (req.method === "GET" && url.pathname === "/health") {
    sendJson(res, 200, { ok: true, apiVersion: API_VERSION });
    return;
  }

  if (req.method === "GET" && url.pathname === "/usage") {
    const usage = cachedUsage ?? (await fetchCursorUsage());
    sendJson(res, 200, { usage });
    return;
  }

  if (req.method === "GET" && url.pathname === "/events") {
    res.writeHead(200, {
      "Content-Type": "text/event-stream",
      "Cache-Control": "no-cache",
      Connection: "keep-alive",
    });
    res.write(`data: ${snapshotEncoded(cachedUsage)}\n\n`);
    sseClients.add(res);
    req.on("close", () => {
      sseClients.delete(res);
    });
    return;
  }

  sendJson(res, 404, { error: "not found" });
});

server.listen(PORT, "127.0.0.1", () => {
  console.log(`[cursor-notch-usage] bridge on :${PORT}`);
  void fetchCursorUsage(true);
  setInterval(() => {
    void fetchCursorUsage(true);
  }, USAGE_POLL_MS);
});
