// Felix data contracts (mirrors backend payloads).

export interface IngestPayload {
  session_id: string;
  image: string;
  voice_text: string;
}

export interface IntentOutput {
  action: string;
  title: string;
  content: string;
  target: string;
}

export interface FelixEvent {
  session_id: string;
  event: string; // e.g. "intent_processed"
  data: IntentOutput;
}

export type ConnectionState = "connecting" | "connected" | "disconnected";
