"use client";

import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { INGEST_URL, WS_URL } from "@/lib/config";
import type { ConnectionState, LumisEvent, StepResult, WorkflowComplete } from "@/lib/types";
import {
  ArrowUpIcon,
  CheckIcon,
  ExternalIcon,
  FileTextIcon,
  GearIcon,
  GlobeIcon,
  ImageIcon,
  MailIcon,
  MusicIcon,
  PresentationIcon,
  ReceiptIcon,
  TableIcon,
} from "./icons";

type IconType = (p: React.SVGProps<SVGSVGElement>) => React.JSX.Element;

const TOOL_META: Record<string, { label: string; Icon: IconType }> = {
  "notes.create_from_image": { label: "Apple Notes", Icon: FileTextIcon },
  "numbers.create_spreadsheet": { label: "Apple Numbers", Icon: TableIcon },
  "numbers.add_expense": { label: "Apple Numbers", Icon: ReceiptIcon },
  "slides.create_presentation": { label: "Google Slides", Icon: PresentationIcon },
  "gmail.draft_email": { label: "Gmail", Icon: MailIcon },
  "browser.open_url": { label: "Chrome", Icon: GlobeIcon },
  "spotify.play_song": { label: "Spotify", Icon: MusicIcon },
};

const EXPENSE_HEADERS = ["Date", "Merchant", "Category", "Amount", "Notes"];

function meta(tool: string) {
  return TOOL_META[tool] ?? { label: tool, Icon: GearIcon };
}

type Step = {
  tool: string;
  args?: Record<string, unknown>;
  status?: "executed" | "error" | "running";
  message?: string;
  title?: string;
  detail?: string;
  url?: string;
};

type Workflow = {
  id: number;
  steps: Step[];
  voice?: string;
  imageName?: string;
  done: boolean;
  at: number;
};

function timeAgo(at: number): string {
  const s = Math.floor((Date.now() - at) / 1000);
  if (s < 8) return "Just now";
  if (s < 60) return `${s}s ago`;
  const m = Math.floor(s / 60);
  if (m < 60) return `${m}m ago`;
  const h = Math.floor(m / 60);
  if (h < 24) return `${h}h ago`;
  return `${Math.floor(h / 24)}d ago`;
}

function asArray(v: unknown): unknown[] {
  return Array.isArray(v) ? v : [];
}

export default function Dashboard() {
  const [status, setStatus] = useState<ConnectionState>("connecting");
  const [workflows, setWorkflows] = useState<Workflow[]>([]);
  const [selectedId, setSelectedId] = useState<number | null>(null);
  const [, forceTick] = useState(0);

  // Voice/image captured locally on send (the WS payload doesn't carry them).
  const pending = useRef<{ voice?: string; imageName?: string } | null>(null);
  const wfSeq = useRef(0);

  // Re-render once a minute so relative timestamps stay fresh.
  useEffect(() => {
    const t = setInterval(() => forceTick((n) => n + 1), 30_000);
    return () => clearInterval(t);
  }, []);

  useEffect(() => {
    let closedByUs = false;
    let ws: WebSocket | null = null;
    let reconnectTimer: ReturnType<typeof setTimeout> | null = null;

    const onMessage = (msg: MessageEvent) => {
      let evt: LumisEvent;
      try {
        evt = JSON.parse(msg.data as string) as LumisEvent;
      } catch {
        return;
      }

      if (evt.event === "workflow_complete") {
        const data = evt.data as WorkflowComplete;
        setWorkflows((prev) => {
          // Replayed to a fresh client on connect — synthesize the workflow.
          if (prev.length === 0) {
            const wf: Workflow = {
              id: ++wfSeq.current,
              steps: data.steps.map((s) => ({ ...s })),
              done: true,
              at: Date.now(),
            };
            setSelectedId(wf.id);
            return [wf];
          }
          // Preserve args captured from live step_executed events — the
          // workflow_complete payload omits them.
          const [head, ...rest] = prev;
          const merged = data.steps.map((s, i) => ({
            ...s,
            args: s.args ?? head.steps[i]?.args,
          }));
          return [{ ...head, steps: merged, done: true }, ...rest];
        });
        return;
      }

      const data = evt.data as StepResult;
      if (typeof data.index !== "number") return;

      const step: Step = {
        tool: data.tool,
        args: data.args,
        status: evt.event === "step_started" ? "running" : data.status,
        message: data.message,
        title: data.title,
        detail: data.detail,
        url: data.url,
      };

      setWorkflows((prev) => {
        // A new workflow begins at index 0 of a step_started event.
        if (data.index === 0 && evt.event === "step_started") {
          const wf: Workflow = {
            id: ++wfSeq.current,
            steps: [step],
            voice: pending.current?.voice,
            imageName: pending.current?.imageName,
            done: false,
            at: Date.now(),
          };
          pending.current = null;
          setSelectedId(wf.id);
          return [wf, ...prev].slice(0, 25);
        }
        if (prev.length === 0) {
          // Missed the start (e.g. triggered from another client) — synthesize.
          const wf: Workflow = {
            id: ++wfSeq.current,
            steps: [step],
            done: evt.event === "step_executed" && data.index >= data.total - 1,
            at: Date.now(),
          };
          setSelectedId(wf.id);
          return [wf];
        }
        const [head, ...rest] = prev;
        const steps = [...head.steps];
        steps[data.index] = step;
        return [{ ...head, steps }, ...rest];
      });
    };

    const connect = () => {
      if (closedByUs) return;
      setStatus("connecting");
      ws = new WebSocket(WS_URL);

      ws.onopen = () => setStatus("connected");
      ws.onclose = () => {
        if (!closedByUs) {
          setStatus("disconnected");
          reconnectTimer = setTimeout(connect, 2000);
        }
      };
      ws.onerror = () => setStatus("disconnected");
      ws.onmessage = onMessage;
    };

    connect();

    return () => {
      closedByUs = true;
      if (reconnectTimer) clearTimeout(reconnectTimer);
      ws?.close();
    };
  }, []);

  const selected = useMemo(() => {
    if (selectedId == null) return workflows[0] ?? null;
    return workflows.find((w) => w.id === selectedId) ?? workflows[0] ?? null;
  }, [workflows, selectedId]);

  return (
    <div className="mx-auto grid min-h-dvh w-full max-w-[1400px] grid-cols-1 lg:grid-cols-[300px_1fr]">
      <Sidebar
        status={status}
        workflows={workflows}
        selectedId={selected?.id ?? null}
        onSelect={setSelectedId}
      />
      <MainPanel status={status} workflow={selected} onSent={(p) => (pending.current = p)} />
    </div>
  );
}

/* ----------------------------------- Sidebar ---------------------------------- */

function Sidebar({
  status,
  workflows,
  selectedId,
  onSelect,
}: {
  status: ConnectionState;
  workflows: Workflow[];
  selectedId: number | null;
  onSelect: (id: number) => void;
}) {
  return (
    <aside className="flex flex-col gap-6 border-b border-zinc-200 px-5 py-6 lg:border-b-0 lg:border-r lg:px-6">
      <div className="flex items-center justify-between">
        <div className="flex items-center gap-2.5">
          <span className="grid h-7 w-7 place-items-center rounded-lg bg-zinc-900 text-[13px] font-bold text-white">
            1
          </span>
          <span className="text-[15px] font-semibold tracking-tight text-zinc-900">Lumis</span>
        </div>
        <span className="lg:hidden">
          <ConnPill status={status} />
        </span>
      </div>

      <div>
        <h1 className="text-2xl font-bold tracking-tight text-zinc-900">Today</h1>
        <p className="mt-1 text-sm text-zinc-500">
          {workflows.length === 0
            ? "Waiting for your first capture"
            : `${workflows.length} capture${workflows.length === 1 ? "" : "s"} from your phone`}
        </p>
      </div>

      <nav className="flex flex-1 flex-col gap-1.5">
        {workflows.map((wf, i) => {
          const primary = wf.steps[0];
          const m = meta(primary?.tool ?? "");
          const active = wf.id === selectedId;
          return (
            <button
              key={wf.id}
              type="button"
              onClick={() => onSelect(wf.id)}
              aria-current={active ? "true" : undefined}
              className={`group cursor-pointer rounded-xl px-3.5 py-3 text-left transition-colors duration-200 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-zinc-900 focus-visible:ring-offset-2 ${
                active
                  ? "bg-zinc-900 text-white shadow-sm"
                  : "text-zinc-900 hover:bg-zinc-200/60"
              }`}
            >
              <div className="flex items-center justify-between gap-2">
                <span
                  className={`truncate text-sm font-medium ${active ? "text-white" : "text-zinc-900"}`}
                >
                  {primary?.title || m.label}
                </span>
                <span className={`shrink-0 text-[11px] ${active ? "text-zinc-400" : "text-zinc-400"}`}>
                  {wf.done || wf.steps.some((s) => s.status === "executed")
                    ? timeAgo(wf.at)
                    : "…"}
                </span>
              </div>
              <div className="mt-0.5 flex items-center gap-2">
                <span className={`text-xs ${active ? "text-zinc-400" : "text-zinc-500"}`}>
                  {m.label}
                </span>
                {i === 0 && (
                  <span
                    className={`rounded px-1.5 py-0.5 text-[9px] font-semibold uppercase tracking-wider ${
                      active ? "bg-white/15 text-white" : "bg-zinc-200 text-zinc-600"
                    }`}
                  >
                    Latest
                  </span>
                )}
              </div>
            </button>
          );
        })}
      </nav>

      <div className="hidden items-center gap-2.5 border-t border-zinc-200 pt-4 lg:flex">
        <span className="grid h-8 w-8 place-items-center rounded-full bg-zinc-900 text-xs font-semibold text-white">
          N
        </span>
        <span className="text-sm text-zinc-500">Local session</span>
      </div>
    </aside>
  );
}

/* ---------------------------------- Main panel -------------------------------- */

function MainPanel({
  status,
  workflow,
  onSent,
}: {
  status: ConnectionState;
  workflow: Workflow | null;
  onSent: (p: { voice?: string; imageName?: string }) => void;
}) {
  return (
    <main className="flex flex-col gap-5 px-5 py-6 lg:px-10 lg:py-8">
      <div className="hidden items-center justify-end lg:flex">
        <ConnPill status={status} />
      </div>

      {workflow ? (
        <WorkflowView workflow={workflow} />
      ) : (
        <div className="grid flex-1 place-items-center rounded-3xl border border-dashed border-zinc-300 bg-white/60 p-12 text-center">
          <div>
            <p className="text-lg font-semibold text-zinc-900">No captures yet</p>
            <p className="mt-1 max-w-sm text-sm text-zinc-500">
              Send a command below (or from the iOS app) and Lumis will run a real
              action on this Mac.
            </p>
          </div>
        </div>
      )}

      <Composer onSent={onSent} />
    </main>
  );
}

function WorkflowView({ workflow }: { workflow: Workflow }) {
  const primary = workflow.steps[0];
  const m = meta(primary?.tool ?? "");
  const failed = primary?.status === "error";
  const running = !workflow.done && workflow.steps.some((s) => s.status === "running");
  const openUrl = workflow.steps.find((s) => s.url)?.url;

  return (
    <div className="flex flex-col gap-4">
      {/* Headline result card */}
      <section className="rounded-3xl border border-zinc-200 bg-white p-6 shadow-sm lg:p-8">
        <div className="flex flex-col gap-5 sm:flex-row sm:items-start sm:justify-between">
          <div className="flex items-start gap-4">
            <span
              className={`grid h-12 w-12 shrink-0 place-items-center rounded-2xl ${
                failed ? "bg-red-600" : "bg-zinc-900"
              } text-white`}
            >
              {failed ? (
                <span className="text-lg font-bold">!</span>
              ) : running ? (
                <Spinner />
              ) : (
                <CheckIcon className="h-6 w-6" />
              )}
            </span>
            <div>
              <p className="text-xs font-medium uppercase tracking-wider text-zinc-500">
                {failed
                  ? "Could not complete"
                  : running
                    ? "Working on it"
                    : statusLabel(primary?.tool ?? "")}
              </p>
              <h2 className="mt-1 text-2xl font-bold tracking-tight text-zinc-900 lg:text-3xl">
                {primary?.title || m.label}
              </h2>
              <p className="mt-1.5 text-sm text-zinc-500">
                {running ? "Executing on your Mac…" : `Ready in ${m.label}`}
              </p>
            </div>
          </div>

          {openUrl && !running && (
            <a
              href={openUrl}
              target="_blank"
              rel="noreferrer"
              className="inline-flex shrink-0 cursor-pointer items-center gap-2 rounded-xl bg-zinc-900 px-5 py-3 text-sm font-semibold text-white transition-colors duration-200 hover:bg-zinc-700 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-zinc-900 focus-visible:ring-offset-2"
            >
              Open in {m.label.split(" ")[0]}
              <ExternalIcon className="h-4 w-4" />
            </a>
          )}
        </div>

        {/* From your phone */}
        {(workflow.voice || workflow.imageName) && (
          <div className="mt-7 border-t border-zinc-100 pt-6">
            <p className="text-[11px] font-semibold uppercase tracking-wider text-zinc-400">
              From your phone
            </p>
            <div className="mt-3 flex items-center gap-3">
              <span className="grid h-11 w-11 place-items-center rounded-xl bg-zinc-100 text-zinc-400">
                <ImageIcon className="h-5 w-5" />
              </span>
              <div>
                <p className="text-sm font-medium text-zinc-900">
                  {workflow.imageName || "Capture"}
                </p>
                <p className="text-xs text-zinc-500">Captured just now</p>
              </div>
            </div>
            {workflow.voice && (
              <p className="mt-4 text-[15px] italic text-zinc-700">“{workflow.voice}”</p>
            )}
          </div>
        )}

        {/* Progress */}
        <ProgressTrack done={workflow.done} running={running} failed={failed} />
      </section>

      {/* What Lumis made */}
      <section className="rounded-3xl border border-zinc-200 bg-white p-6 shadow-sm lg:p-8">
        <p className="mb-4 text-[11px] font-semibold uppercase tracking-wider text-zinc-400">
          What Lumis made
        </p>
        <div className="flex flex-col gap-4">
          {workflow.steps.map((s, i) => (
            <StepResultCard key={i} step={s} />
          ))}
        </div>
      </section>
    </div>
  );
}

function statusLabel(tool: string): string {
  if (tool.startsWith("numbers")) return "Added to your spreadsheet";
  if (tool.startsWith("slides")) return "Created your presentation";
  if (tool.startsWith("notes")) return "Saved to your notes";
  if (tool.startsWith("gmail")) return "Drafted your email";
  if (tool.startsWith("spotify")) return "Now playing";
  return "Done";
}

function ProgressTrack({
  done,
  running,
  failed,
}: {
  done: boolean;
  running: boolean;
  failed: boolean;
}) {
  // Point + Speak happened at capture; Done reflects execution.
  const steps = [
    { label: "Point", state: "done" as const },
    { label: "Speak", state: "done" as const },
    {
      label: "Done",
      state: failed ? ("error" as const) : done ? ("done" as const) : ("active" as const),
    },
  ];
  void running;

  return (
    <div className="mt-7 flex items-center gap-3">
      {steps.map((s, i) => (
        <div key={s.label} className="flex items-center gap-3">
          <div className="flex items-center gap-2">
            <span
              className={`grid h-6 w-6 place-items-center rounded-full text-[11px] font-semibold transition-colors duration-200 ${
                s.state === "done"
                  ? "bg-zinc-900 text-white"
                  : s.state === "error"
                    ? "bg-red-600 text-white"
                    : "border-2 border-zinc-300 bg-white text-zinc-400"
              } ${s.state === "active" ? "animate-pulse" : ""}`}
            >
              {s.state === "done" ? <CheckIcon className="h-3.5 w-3.5" /> : i + 1}
            </span>
            <span
              className={`text-sm ${s.state === "done" || s.state === "error" ? "font-medium text-zinc-900" : "text-zinc-400"}`}
            >
              {s.label}
            </span>
          </div>
          {i < steps.length - 1 && <span className="h-px w-8 bg-zinc-200" />}
        </div>
      ))}
    </div>
  );
}

function StepResultCard({ step }: { step: Step }) {
  const m = meta(step.tool);
  const { Icon } = m;
  return (
    <div className="overflow-hidden rounded-2xl border border-zinc-200">
      <div className="flex items-center gap-2.5 border-b border-zinc-100 bg-zinc-50 px-4 py-2.5">
        <Icon className="h-4 w-4 text-zinc-500" />
        <span className="text-sm font-medium text-zinc-700">{m.label}</span>
        {step.status === "error" && (
          <span className="ml-auto rounded-full bg-red-100 px-2 py-0.5 text-[11px] font-medium text-red-600">
            failed
          </span>
        )}
      </div>
      <div className="p-4">
        <ResultBody step={step} />
      </div>
    </div>
  );
}

function ResultBody({ step }: { step: Step }) {
  if (step.status === "error") {
    return <p className="text-sm text-red-600">{step.message || step.detail}</p>;
  }

  const args = step.args ?? {};

  // Apple Numbers — render a real table from args (live) or detail (replay).
  if (step.tool.startsWith("numbers")) {
    const rawRows = asArray(args.rows);
    if (rawRows.length > 0) {
      const headers =
        asArray(args.headers).map(String).length > 0
          ? asArray(args.headers).map(String)
          : EXPENSE_HEADERS;
      const rows = rawRows.map((r) => (Array.isArray(r) ? r.map(String) : [String(r)]));
      return <DataTable headers={headers} rows={rows} />;
    }
    // Fallback: parse the comma-joined rows from the result detail.
    const lines = (step.detail ?? "").split("\n").filter(Boolean).map((l) => l.split(", "));
    if (lines.length > 0) {
      const isCreate = step.tool === "numbers.create_spreadsheet";
      const headers = isCreate ? lines[0] : EXPENSE_HEADERS;
      const rows = isCreate ? lines.slice(1) : lines;
      if (rows.length > 0) return <DataTable headers={headers} rows={rows} />;
    }
  }

  // Google Slides — list slide titles.
  if (step.tool.startsWith("slides")) {
    const slides = asArray(args.slides) as Array<Record<string, unknown>>;
    if (slides.length > 0) {
      return (
        <ol className="flex flex-col gap-2">
          {slides.map((s, i) => (
            <li key={i} className="flex items-start gap-3 text-sm">
              <span className="mt-0.5 grid h-5 w-5 shrink-0 place-items-center rounded bg-zinc-100 text-[11px] font-semibold text-zinc-500 tabular-nums">
                {i + 1}
              </span>
              <span className="font-medium text-zinc-900">{String(s.title ?? "Slide")}</span>
            </li>
          ))}
        </ol>
      );
    }
  }

  // Gmail — show the draft fields.
  if (step.tool === "gmail.draft_email") {
    return (
      <dl className="flex flex-col gap-1.5 text-sm">
        <Row k="To" v={String(args.to || "—")} />
        <Row k="Subject" v={String(args.subject || "—")} />
        <Row k="Body" v={String(args.body || "—")} />
      </dl>
    );
  }

  // Notes — show the content.
  if (step.tool === "notes.create_from_image") {
    return (
      <p className="whitespace-pre-wrap text-sm leading-relaxed text-zinc-700">
        {String(args.content || step.detail || step.message || "")}
      </p>
    );
  }

  // Fallback — message + detail.
  return (
    <div className="text-sm text-zinc-700">
      <p>{step.message}</p>
      {step.detail && step.detail !== step.message && (
        <p className="mt-1 break-all text-zinc-500">{step.detail}</p>
      )}
    </div>
  );
}

function Row({ k, v }: { k: string; v: string }) {
  return (
    <div className="flex gap-3">
      <dt className="w-16 shrink-0 text-zinc-400">{k}</dt>
      <dd className="whitespace-pre-wrap text-zinc-800">{v}</dd>
    </div>
  );
}

function DataTable({ headers, rows }: { headers: string[]; rows: string[][] }) {
  const cols = Math.max(headers.length, ...rows.map((r) => r.length));
  return (
    <div className="overflow-x-auto">
      <table className="w-full border-collapse text-sm">
        <thead>
          <tr className="border-b border-zinc-200 text-left">
            {Array.from({ length: cols }).map((_, i) => (
              <th
                key={i}
                className="px-3 py-2 text-[11px] font-semibold uppercase tracking-wider text-zinc-400"
              >
                {headers[i] ?? ""}
              </th>
            ))}
          </tr>
        </thead>
        <tbody>
          {rows.map((r, ri) => (
            <tr key={ri} className="border-b border-zinc-100 last:border-0">
              {Array.from({ length: cols }).map((_, ci) => (
                <td key={ci} className="px-3 py-2.5 text-zinc-800 tabular-nums">
                  {r[ci] ?? ""}
                </td>
              ))}
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}

/* ---------------------------------- Composer ---------------------------------- */

function Composer({ onSent }: { onSent: (p: { voice?: string; imageName?: string }) => void }) {
  const [text, setText] = useState("");
  const [image, setImage] = useState<{ name: string; dataUrl: string } | null>(null);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const fileRef = useRef<HTMLInputElement>(null);

  const onPickFile = useCallback((file?: File) => {
    if (!file) return;
    const reader = new FileReader();
    reader.onload = () => setImage({ name: file.name, dataUrl: String(reader.result) });
    reader.readAsDataURL(file);
  }, []);

  async function send() {
    const voice = text.trim();
    if (!voice && !image) return;
    setLoading(true);
    setError(null);
    onSent({ voice: voice || undefined, imageName: image?.name });
    try {
      const res = await fetch(INGEST_URL, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          session_id: "web",
          image: image?.dataUrl ?? "",
          voice_text: voice,
        }),
      });
      if (!res.ok) throw new Error(`Backend responded ${res.status}`);
      setText("");
      setImage(null);
      if (fileRef.current) fileRef.current.value = "";
    } catch (e) {
      setError(e instanceof Error ? e.message : "Failed to reach backend");
    } finally {
      setLoading(false);
    }
  }

  return (
    <div className="mt-auto">
      <div className="rounded-2xl border border-zinc-200 bg-white p-3 shadow-sm">
        <div className="flex items-end gap-2">
          <textarea
            value={text}
            onChange={(e) => setText(e.target.value)}
            onKeyDown={(e) => {
              if (e.key === "Enter" && (e.metaKey || e.ctrlKey)) {
                e.preventDefault();
                void send();
              }
            }}
            rows={1}
            placeholder="Tell Lumis what to do… e.g. “add this to my expense spreadsheet”"
            className="max-h-32 min-h-[40px] flex-1 resize-none bg-transparent px-2 py-2 text-sm text-zinc-900 placeholder:text-zinc-400 focus:outline-none"
          />
          <input
            ref={fileRef}
            type="file"
            accept="image/*"
            className="hidden"
            onChange={(e) => onPickFile(e.target.files?.[0])}
          />
          <button
            type="button"
            onClick={() => fileRef.current?.click()}
            aria-label="Attach an image"
            className="grid h-10 w-10 shrink-0 cursor-pointer place-items-center rounded-xl border border-zinc-200 text-zinc-500 transition-colors duration-200 hover:bg-zinc-100 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-zinc-900 focus-visible:ring-offset-2"
          >
            <ImageIcon className="h-5 w-5" />
          </button>
          <button
            type="button"
            onClick={() => void send()}
            disabled={loading || (!text.trim() && !image)}
            aria-label="Send to Lumis"
            className="grid h-10 w-10 shrink-0 cursor-pointer place-items-center rounded-xl bg-zinc-900 text-white transition-colors duration-200 hover:bg-zinc-700 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-zinc-900 focus-visible:ring-offset-2 disabled:cursor-not-allowed disabled:opacity-40"
          >
            {loading ? <Spinner /> : <ArrowUpIcon className="h-5 w-5" />}
          </button>
        </div>
        {(image || error) && (
          <div className="flex items-center justify-between px-2 pt-2">
            {image ? (
              <span className="inline-flex items-center gap-1.5 text-xs text-zinc-500">
                <ImageIcon className="h-3.5 w-3.5" /> {image.name}
                <button
                  type="button"
                  onClick={() => {
                    setImage(null);
                    if (fileRef.current) fileRef.current.value = "";
                  }}
                  className="cursor-pointer text-zinc-400 underline-offset-2 hover:underline"
                >
                  remove
                </button>
              </span>
            ) : (
              <span />
            )}
            {error && (
              <span className="text-xs text-red-600" role="alert">
                {error}
              </span>
            )}
          </div>
        )}
      </div>
      <p className="mt-2 px-1 text-center text-[11px] text-zinc-400">
        Press ⌘↵ to send · attach a receipt or whiteboard photo for best results
      </p>
    </div>
  );
}

/* ----------------------------------- Shared ----------------------------------- */

function ConnPill({ status }: { status: ConnectionState }) {
  const map: Record<ConnectionState, { dot: string; label: string }> = {
    connected: { dot: "bg-emerald-500", label: "iPhone connected" },
    connecting: { dot: "bg-amber-400 animate-pulse", label: "Connecting" },
    disconnected: { dot: "bg-zinc-300", label: "Disconnected" },
  };
  const s = map[status];
  return (
    <span
      className="inline-flex items-center gap-2 rounded-full border border-zinc-200 bg-white px-3 py-1.5 text-xs font-medium text-zinc-600"
      role="status"
      aria-live="polite"
    >
      <span className={`h-2 w-2 rounded-full ${s.dot}`} aria-hidden />
      {s.label}
    </span>
  );
}

function Spinner() {
  return (
    <svg className="h-5 w-5 animate-spin" viewBox="0 0 24 24" fill="none" aria-hidden>
      <circle className="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" strokeWidth="4" />
      <path className="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8v4a4 4 0 00-4 4H4z" />
    </svg>
  );
}
