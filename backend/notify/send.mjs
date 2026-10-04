// Sends one iMessage through Photon Spectrum. Called by the Python server (notify.py).
//
// Usage:  echo '{"to": "+15551234567", "text": "hello"}' | node send.mjs
//         node send.mjs --check        (start Spectrum and stop, without sending)
//
// Mode is picked from the environment:
// - SPECTRUM_PROJECT_ID + SPECTRUM_PROJECT_SECRET set: Spectrum cloud (Photon's number).
// - otherwise: Spectrum local mode (this Mac's Messages app, no account needed).
// Prints one JSON line: {"ok": true, "mode": "..."} or {"ok": false, "error": "..."}.
import { Spectrum } from "spectrum-ts";

const projectId = process.env.SPECTRUM_PROJECT_ID;
const projectSecret = process.env.SPECTRUM_PROJECT_SECRET;
const mode = projectId && projectSecret ? "cloud" : "local";

async function readStdin() {
  let data = "";
  for await (const chunk of process.stdin) data += chunk;
  return data;
}

async function start() {
  if (mode === "cloud") {
    const { imessage } = await import("spectrum-ts/providers/imessage");
    const app = await Spectrum({ projectId, projectSecret, providers: [imessage.config()] });
    return { app, platform: imessage(app) };
  }
  const { localIMessage } = await import("@spectrum-ts/imessage-local");
  const app = await Spectrum({ providers: [localIMessage.config()] });
  return { app, platform: localIMessage(app) };
}

let app;
try {
  const check = process.argv.includes("--check");
  const job = check ? null : JSON.parse(await readStdin());
  if (!check && (!job?.to || !job?.text)) throw new Error("need {to, text} on stdin");
  const started = await start();
  app = started.app;
  if (!check) {
    const space = await started.platform.space.create(job.to);
    await space.send(job.text);
  }
  console.log(JSON.stringify({ ok: true, mode }));
} catch (err) {
  console.log(JSON.stringify({ ok: false, mode, error: String(err?.message ?? err) }));
  process.exitCode = 1;
} finally {
  await app?.stop().catch(() => {});
  // Spectrum may keep watchers open; this is a one-shot script.
  setTimeout(() => process.exit(), 100);
}
