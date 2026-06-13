// Felix frontend config. Override via NEXT_PUBLIC_* env vars.
export const API_BASE_URL =
  process.env.NEXT_PUBLIC_API_BASE_URL ?? "http://localhost:8000";

export const WS_URL =
  process.env.NEXT_PUBLIC_WS_URL ?? "ws://localhost:8000/ws";

export const INGEST_URL = `${API_BASE_URL}/ingest`;
