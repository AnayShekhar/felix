import type { ConnectionState } from "@/lib/types";

const STYLES: Record<
  ConnectionState,
  { label: string; dot: string; text: string }
> = {
  connected: {
    label: "Connected",
    dot: "bg-emerald-400",
    text: "text-emerald-300",
  },
  connecting: {
    label: "Connecting",
    dot: "bg-amber-400 animate-pulse",
    text: "text-amber-300",
  },
  disconnected: {
    label: "Disconnected",
    dot: "bg-rose-400",
    text: "text-rose-300",
  },
};

export default function ConnectionStatus({
  state,
}: {
  state: ConnectionState;
}) {
  const s = STYLES[state];
  return (
    <div
      className="inline-flex items-center gap-2 rounded-full border border-white/10 bg-white/5 px-3 py-1.5 text-sm font-medium"
      role="status"
      aria-live="polite"
    >
      <span className={`h-2.5 w-2.5 rounded-full ${s.dot}`} aria-hidden />
      <span className={s.text}>{s.label}</span>
    </div>
  );
}
