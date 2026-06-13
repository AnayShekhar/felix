import InputPanel from "@/components/InputPanel";
import OutputPanel from "@/components/OutputPanel";

export default function Home() {
  return (
    <main className="mx-auto flex w-full max-w-6xl flex-1 flex-col gap-8 px-6 py-10">
      <header className="flex flex-col gap-1">
        <div className="flex items-center gap-2.5">
          <span className="grid h-9 w-9 place-items-center rounded-xl bg-indigo-500 text-white">
            <svg
              className="h-5 w-5"
              viewBox="0 0 24 24"
              fill="none"
              stroke="currentColor"
              strokeWidth="2"
              strokeLinecap="round"
              strokeLinejoin="round"
              aria-hidden
            >
              <path d="m13 2-3 7h5l-3 13" />
            </svg>
          </span>
          <h1 className="text-2xl font-bold tracking-tight text-white">
            Felix
          </h1>
        </div>
        <p className="text-sm text-slate-400">
          Live session dashboard — capture real-world context, see structured
          actions in real time.
        </p>
      </header>

      <div className="grid flex-1 grid-cols-1 gap-6 lg:grid-cols-2">
        <InputPanel />
        <OutputPanel />
      </div>
    </main>
  );
}
