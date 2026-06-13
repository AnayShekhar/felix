"use client";

import { useEffect, useRef, useState } from "react";
import { WS_URL } from "@/lib/config";
import type { ConnectionState, FelixEvent } from "@/lib/types";
import ConnectionStatus from "./ConnectionStatus";

function Field({ label, value }: { label: string; value: string }) {
  return (
    <div>
      <dt className="text-xs font-semibold uppercase tracking-wider text-slate-500">
        {label}
      </dt>
      <dd className="mt-0.5 text-sm text-slate-200">{value}</dd>
    </div>
  );
}

export default function OutputPanel() {
  const [status, setStatus] = useState<ConnectionState>("connecting");
  const [latest, setLatest] = useState<FelixEvent | null>(null);
  const wsRef = useRef<WebSocket | null>(null);

  useEffect(() => {
    let closedByUs = false;
    setStatus("connecting");
    const ws = new WebSocket(WS_URL);
    wsRef.current = ws;

    ws.onopen = () => setStatus("connected");
    ws.onclose = () => {
      if (!closedByUs) setStatus("disconnected");
    };
    ws.onerror = () => setStatus("disconnected");
    ws.onmessage = (msg) => {
      try {
        const parsed = JSON.parse(msg.data) as FelixEvent;
        setLatest(parsed);
      } catch {
        // ignore malformed frames
      }
    };

    return () => {
      closedByUs = true;
      ws.close();
    };
  }, []);

  const data = latest?.data ?? null;

  return (
    <section className="flex flex-col gap-5 rounded-2xl border border-white/10 bg-white/[0.03] p-6">
      <header className="flex items-center justify-between gap-3">
        <div>
          <h2 className="text-lg font-semibold text-white">Live Output</h2>
          <p className="mt-1 text-sm text-slate-400">
            Streaming results from the backend WebSocket.
          </p>
        </div>
        <ConnectionStatus state={status} />
      </header>

      {!latest ? (
        <div className="rounded-xl border border-dashed border-white/10 bg-black/20 p-8 text-center text-sm text-slate-400">
          Waiting for an event… Send a test input to see results here.
        </div>
      ) : (
        <div className="flex flex-col gap-5">
          {/* 1. Input received */}
          <div className="rounded-xl border border-white/10 bg-black/20 p-4">
            <h3 className="mb-3 flex items-center gap-2 text-sm font-semibold text-white">
              <svg
                className="h-4 w-4 text-indigo-400"
                viewBox="0 0 24 24"
                fill="none"
                stroke="currentColor"
                strokeWidth="2"
                strokeLinecap="round"
                strokeLinejoin="round"
                aria-hidden
              >
                <path d="M4 4h16v12H4z" />
                <path d="m4 16 5-5 4 4 3-3 4 4" />
              </svg>
              Input received
            </h3>
            <dl className="flex flex-col gap-3">
              <Field label="Session" value={latest.session_id} />
              <Field label="Event" value={latest.event} />
            </dl>
          </div>

          {/* 2. AI interpretation */}
          {data && (
            <div className="rounded-xl border border-white/10 bg-black/20 p-4">
              <h3 className="mb-3 flex items-center gap-2 text-sm font-semibold text-white">
                <svg
                  className="h-4 w-4 text-indigo-400"
                  viewBox="0 0 24 24"
                  fill="none"
                  stroke="currentColor"
                  strokeWidth="2"
                  strokeLinecap="round"
                  strokeLinejoin="round"
                  aria-hidden
                >
                  <path d="M12 3a4 4 0 0 0-4 4 4 4 0 0 0 0 8 4 4 0 0 0 8 0 4 4 0 0 0 0-8 4 4 0 0 0-4-4Z" />
                  <path d="M12 7v12" />
                </svg>
                AI interpretation
              </h3>
              <p className="text-base font-semibold text-white">{data.title}</p>
              <div className="mt-3 flex flex-wrap gap-2">
                <span className="rounded-full bg-indigo-500/15 px-2.5 py-1 text-xs font-medium text-indigo-300">
                  action: {data.action}
                </span>
                <span className="rounded-full bg-sky-500/15 px-2.5 py-1 text-xs font-medium text-sky-300">
                  target: {data.target}
                </span>
              </div>
              <p className="mt-3 whitespace-pre-wrap text-sm leading-relaxed text-slate-300">
                {data.content}
              </p>
            </div>
          )}

          {/* 2.5. Active Automation Workspace */}
          {data && (
            <div className="rounded-xl border border-white/10 bg-black/20 p-4">
              <h3 className="mb-3 flex items-center gap-2 text-sm font-semibold text-white">
                <svg
                  className="h-4 w-4 text-indigo-400"
                  viewBox="0 0 24 24"
                  fill="none"
                  stroke="currentColor"
                  strokeWidth="2"
                  strokeLinecap="round"
                  strokeLinejoin="round"
                  aria-hidden
                >
                  <path d="M21 16V8a2 2 0 0 0-1-1.73l-7-4a2 2 0 0 0-2 0l-7 4A2 2 0 0 0 3 8v8a2 2 0 0 0 1 1.73l7 4a2 2 0 0 0 2 0l7-4A2 2 0 0 0 21 16z" />
                  <polyline points="3.27 6.96 12 12.01 20.73 6.96" />
                  <line x1="12" y1="22.08" x2="12" y2="12" />
                </svg>
                Active Automation Workspace
              </h3>

              {data.action === "create_notes" && (
                <NotionSimulator title={data.title} content={data.content} />
              )}
              {data.action === "open_url" && (
                <BrowserSimulator title={data.title} content={data.content} />
              )}
              {data.action === "open_app" && (
                <TerminalSimulator title={data.title} content={data.content} />
              )}
              {data.action === "create_task" && (
                <KanbanSimulator title={data.title} content={data.content} />
              )}
              {!["create_notes", "open_url", "open_app", "create_task"].includes(data.action) && (
                <div className="rounded-xl border border-dashed border-white/10 bg-slate-900/40 p-6 text-center text-sm text-slate-400">
                  Custom action type <code className="text-indigo-300 font-mono text-xs">{data.action}</code> received. Executed automation successfully!
                </div>
              )}
            </div>
          )}

          {/* 3. Formatted JSON output */}
          <div className="rounded-xl border border-white/10 bg-black/20 p-4">
            <h3 className="mb-3 flex items-center gap-2 text-sm font-semibold text-white">
              <svg
                className="h-4 w-4 text-indigo-400"
                viewBox="0 0 24 24"
                fill="none"
                stroke="currentColor"
                strokeWidth="2"
                strokeLinecap="round"
                strokeLinejoin="round"
                aria-hidden
              >
                <path d="m8 6-6 6 6 6" />
                <path d="m16 6 6 6-6 6" />
              </svg>
              Formatted JSON output
            </h3>
            <pre className="overflow-x-auto rounded-lg bg-black/40 p-4 font-mono text-xs leading-relaxed text-slate-300">
              {JSON.stringify(data, null, 2)}
            </pre>
          </div>
        </div>
      )}
    </section>
  );
}

// ==========================================
// SIMULATOR WORKSPACES FOR AUTOMATION
// ==========================================

function NotionSimulator({ title, content }: { title: string; content: string }) {
  const [typedContent, setTypedContent] = useState("");
  const [status, setStatus] = useState<"typing" | "syncing" | "done">("typing");

  useEffect(() => {
    setTypedContent("");
    setStatus("typing");
    let i = 0;
    const interval = setInterval(() => {
      if (i < content.length) {
        setTypedContent((prev) => prev + content.substring(i, i + 5));
        i += 5;
      } else {
        setTypedContent(content);
        clearInterval(interval);
        setStatus("syncing");
        setTimeout(() => {
          setStatus("done");
        }, 1000);
      }
    }, 25);
    return () => clearInterval(interval);
  }, [content]);

  return (
    <div className="rounded-xl border border-white/10 bg-slate-900/60 p-5 shadow-2xl backdrop-blur-md">
      <div className="flex items-center justify-between border-b border-white/5 pb-3">
        <div className="flex items-center gap-2">
          <span className="text-xl">📓</span>
          <span className="text-xs font-semibold uppercase tracking-wider text-slate-400">Notion Workspace</span>
        </div>
        <div className="flex items-center gap-1.5">
          <span className={`h-2 w-2 rounded-full ${status === "typing" ? "bg-amber-400 animate-pulse" : status === "syncing" ? "bg-sky-400 animate-pulse" : "bg-green-400"}`} />
          <span className="text-xs text-slate-300">
            {status === "typing" ? "Writing page..." : status === "syncing" ? "Syncing..." : "Synced to Workspace"}
          </span>
        </div>
      </div>
      <div className="mt-4 font-sans text-slate-100">
        <h3 className="text-xl font-bold tracking-tight text-white mb-2">{title}</h3>
        <h4 className="text-xs text-slate-400 mb-2">Workspace Page Link: https://notion.so/felix/{title.toLowerCase().replace(/[^a-z0-9]/g, "-")}</h4>
        <hr className="border-white/5 mb-3" />
        <div className="prose prose-invert max-w-none text-sm leading-relaxed text-slate-300 whitespace-pre-wrap font-sans bg-black/10 p-3 rounded border border-white/5">
          {typedContent}
          {status === "typing" && <span className="inline-block h-4 w-1.5 ml-0.5 bg-indigo-400 animate-pulse align-middle" />}
        </div>
      </div>
    </div>
  );
}

function TerminalSimulator({ title, content }: { title: string; content: string }) {
  const [logs, setLogs] = useState<string[]>([]);
  const [complete, setComplete] = useState(false);

  useEffect(() => {
    setLogs([]);
    setComplete(false);
    
    const lines = [
      `felix@macbook ~ % open -a "${content}"`,
      `[system] validating application package...`,
      `[system] resolved bundle name for "${title}"`,
      `[system] launching process...`,
      `[system] SUCCESS: process opened on host Mac!`,
    ];

    let i = 0;
    const interval = setInterval(() => {
      if (i < lines.length) {
        setLogs((prev) => [...prev, lines[i]]);
        i++;
      } else {
        setComplete(true);
        clearInterval(interval);
      }
    }, 600);
    return () => clearInterval(interval);
  }, [content, title]);

  return (
    <div className="rounded-xl border border-white/10 bg-black/80 font-mono text-xs shadow-2xl overflow-hidden">
      <div className="flex items-center justify-between bg-zinc-900 px-4 py-2 border-b border-white/5">
        <div className="flex gap-1.5">
          <span className="h-2.5 w-2.5 rounded-full bg-red-500/80" />
          <span className="h-2.5 w-2.5 rounded-full bg-yellow-500/80" />
          <span className="h-2.5 w-2.5 rounded-full bg-green-500/80" />
        </div>
        <span className="text-[10px] text-zinc-500 font-semibold uppercase">macOS Automation</span>
        <div className="w-10" />
      </div>
      <div className="p-4 flex flex-col gap-1.5 text-zinc-300 min-h-[145px]">
        {logs.map((log, index) => (
          <div key={index} className={log.startsWith("felix") ? "text-slate-100" : log.includes("SUCCESS") ? "text-emerald-400 font-semibold" : "text-zinc-400"}>
            {log}
          </div>
        ))}
        {!complete && (
          <span className="inline-block h-3 w-1.5 bg-zinc-400 animate-pulse" />
        )}
      </div>
    </div>
  );
}

function BrowserSimulator({ title, content }: { title: string; content: string }) {
  const [progress, setProgress] = useState(0);
  const [status, setStatus] = useState<"connecting" | "redirecting" | "opened">("connecting");

  useEffect(() => {
    setProgress(0);
    setStatus("connecting");
    
    const interval = setInterval(() => {
      setProgress((prev) => {
        if (prev < 100) {
          const next = prev + Math.floor(Math.random() * 20) + 5;
          return next > 100 ? 100 : next;
        } else {
          clearInterval(interval);
          return 100;
        }
      });
    }, 150);

    return () => clearInterval(interval);
  }, [content]);

  useEffect(() => {
    if (progress === 100) {
      setStatus("opened");
    } else if (progress > 40) {
      setStatus("redirecting");
    }
  }, [progress]);

  return (
    <div className="rounded-xl border border-white/10 bg-slate-950 p-5 shadow-2xl backdrop-blur-md">
      <div className="flex items-center gap-2.5 border-b border-white/5 pb-3">
        <span className="text-xl">🌐</span>
        <span className="text-xs font-semibold uppercase tracking-wider text-slate-400">Browser Redirector</span>
      </div>
      <div className="mt-4">
        <h4 className="text-sm font-semibold text-white">Opening target URL:</h4>
        <p className="mt-1 font-mono text-xs text-indigo-300 bg-black/40 p-2.5 rounded border border-white/5 break-all">
          {content}
        </p>

        <div className="mt-4 flex items-center justify-between text-xs text-slate-400 mb-1.5">
          <span>
            {status === "connecting" && "Resolving host..."}
            {status === "redirecting" && `Redirecting to ${title}...`}
            {status === "opened" && "Successfully launched on Mac!"}
          </span>
          <span className="font-mono">{progress}%</span>
        </div>

        <div className="w-full bg-white/5 rounded-full h-1.5 overflow-hidden">
          <div 
            className="bg-indigo-500 h-1.5 rounded-full transition-all duration-150"
            style={{ width: `${progress}%` }}
          />
        </div>
      </div>
    </div>
  );
}

interface TaskItem {
  id: string;
  title: string;
  content: string;
  column: "todo" | "progress" | "done";
}

function KanbanSimulator({ title, content }: { title: string; content: string }) {
  const [task, setTask] = useState<TaskItem | null>(null);

  useEffect(() => {
    setTask({
      id: "ai-task",
      title,
      content,
      column: "todo",
    });

    const t1 = setTimeout(() => {
      setTask((prev) => prev ? { ...prev, column: "progress" } : null);
    }, 1800);

    const t2 = setTimeout(() => {
      setTask((prev) => prev ? { ...prev, column: "done" } : null);
    }, 3600);

    return () => {
      clearTimeout(t1);
      clearTimeout(t2);
    };
  }, [title, content]);

  const columns = [
    { id: "todo" as const, name: "To Do", bg: "bg-slate-900/40" },
    { id: "progress" as const, name: "In Progress", bg: "bg-slate-900/40" },
    { id: "done" as const, name: "Done", bg: "bg-slate-900/40" },
  ];

  return (
    <div className="rounded-xl border border-white/10 bg-slate-950/40 p-4 shadow-2xl backdrop-blur-md">
      <div className="flex items-center gap-2 border-b border-white/5 pb-3 mb-4">
        <span className="text-xl">📋</span>
        <span className="text-xs font-semibold uppercase tracking-wider text-slate-400">Smart Kanban Board</span>
      </div>

      <div className="grid grid-cols-3 gap-3">
        {columns.map((col) => (
          <div key={col.id} className={`rounded-lg p-2.5 min-h-[140px] flex flex-col gap-2 ${col.bg}`}>
            <h4 className="text-[10px] font-bold uppercase tracking-wider text-slate-500 border-b border-white/5 pb-1 mb-1">
              {col.name}
            </h4>
            
            {task && task.column === col.id && (
              <div className="rounded-md border border-white/10 bg-slate-800/80 p-2.5 shadow-md transition-all duration-300 transform scale-100 hover:scale-102">
                <h5 className="text-xs font-bold text-white leading-tight">{task.title}</h5>
                <p className="text-[10px] text-slate-300 mt-1 leading-normal line-clamp-3">
                  {task.content}
                </p>
                <div className="mt-2 flex items-center justify-between text-[8px] text-slate-500">
                  <span>ID: task-felix</span>
                  <span className={`font-semibold uppercase ${task.column === "todo" ? "text-amber-400" : task.column === "progress" ? "text-sky-400" : "text-emerald-400"}`}>
                    {task.column}
                  </span>
                </div>
              </div>
            )}
          </div>
        ))}
      </div>
    </div>
  );
}
