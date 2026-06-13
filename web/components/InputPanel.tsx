"use client";

import { useState } from "react";
import { INGEST_URL } from "@/lib/config";
import type { IngestPayload } from "@/lib/types";

const TEST_PAYLOAD: IngestPayload = {
  session_id: "test",
  image: "mock.jpg",
  voice_text: "turn this into study notes",
};

export default function InputPanel() {
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [sentAt, setSentAt] = useState<string | null>(null);

  async function sendTestInput() {
    setLoading(true);
    setError(null);
    try {
      const res = await fetch(INGEST_URL, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(TEST_PAYLOAD),
      });
      if (!res.ok) {
        throw new Error(`Backend responded ${res.status}`);
      }
      setSentAt(new Date().toLocaleTimeString());
    } catch (e) {
      setError(
        e instanceof Error ? e.message : "Failed to reach backend"
      );
    } finally {
      setLoading(false);
    }
  }

  return (
    <section className="flex flex-col gap-5 rounded-2xl border border-white/10 bg-white/[0.03] p-6">
      <header>
        <h2 className="text-lg font-semibold text-white">Input</h2>
        <p className="mt-1 text-sm text-slate-400">
          Send a mock capture to the Felix backend.
        </p>
      </header>

      <button
        type="button"
        onClick={sendTestInput}
        disabled={loading}
        className="inline-flex items-center justify-center gap-2 rounded-xl bg-indigo-500 px-4 py-2.5 text-sm font-semibold text-white transition-colors hover:bg-indigo-400 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-indigo-300 disabled:cursor-not-allowed disabled:opacity-60"
      >
        {loading ? (
          <>
            <svg
              className="h-4 w-4 animate-spin"
              viewBox="0 0 24 24"
              fill="none"
              aria-hidden
            >
              <circle
                className="opacity-25"
                cx="12"
                cy="12"
                r="10"
                stroke="currentColor"
                strokeWidth="4"
              />
              <path
                className="opacity-75"
                fill="currentColor"
                d="M4 12a8 8 0 018-8v4a4 4 0 00-4 4H4z"
              />
            </svg>
            Sending…
          </>
        ) : (
          <>
            <svg
              className="h-4 w-4"
              viewBox="0 0 24 24"
              fill="none"
              stroke="currentColor"
              strokeWidth="2"
              strokeLinecap="round"
              strokeLinejoin="round"
              aria-hidden
            >
              <path d="M22 2 11 13" />
              <path d="M22 2 15 22l-4-9-9-4 20-7z" />
            </svg>
            Send Test Input
          </>
        )}
      </button>

      {sentAt && !error && (
        <p className="text-sm text-emerald-300">
          Request sent at {sentAt}. Watch the live output panel.
        </p>
      )}
      {error && (
        <p className="text-sm text-rose-300" role="alert">
          {error}
        </p>
      )}

      <div>
        <h3 className="mb-2 text-xs font-semibold uppercase tracking-wider text-slate-500">
          Payload
        </h3>
        <pre className="overflow-x-auto rounded-xl border border-white/10 bg-black/40 p-4 font-mono text-xs leading-relaxed text-slate-300">
          {JSON.stringify(TEST_PAYLOAD, null, 2)}
        </pre>
      </div>
    </section>
  );
}
