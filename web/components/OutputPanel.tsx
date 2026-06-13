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
