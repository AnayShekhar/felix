// Felix data contracts (mirrors backend payloads).

export interface IngestPayload {
  session_id: string;
  image: string;
  voice_text: string;
}

export interface StepResult {
  index: number;
  total: number;
  tool: string;
  args: Record<string, unknown>;
  status?: "executed" | "error";
  message?: string;
  title?: string;
  detail?: string;
  url?: string;
}

export interface WorkflowComplete {
  total: number;
  steps: Array<Omit<StepResult, "index" | "total" | "args"> & {
    tool: string;
    args?: Record<string, unknown>;
  }>;
}

// Server emits: step_started, step_executed (StepResult) and
// workflow_complete (WorkflowComplete).
export interface FelixEvent {
  session_id: string;
  event: "step_started" | "step_executed" | "workflow_complete" | string;
  data: StepResult | WorkflowComplete;
}

export type ConnectionState = "connecting" | "connected" | "disconnected";
