// Neon Function: every morning, text what spoils by tomorrow (Photon Spectrum, iMessage).
//
// Runs inside Neon next to the database, on a schedule trigger, so the alert goes out
// even when the Reviri server (and the laptop) is off. Neon injects DATABASE_URL.
// Deploy and schedule: see deploy.py in this folder.
//
// Environment (set at deploy time): SPECTRUM_PROJECT_ID, SPECTRUM_PROJECT_SECRET,
// ALERT_TOKEN (needed for manual calls; the schedule trigger doesn't need it),
// ALERT_TIMEZONE (default America/New_York).
import pg from "pg";
import { Spectrum } from "spectrum-ts";
import { imessage } from "spectrum-ts/providers/imessage";

const TIMEZONE = process.env.ALERT_TIMEZONE || "America/New_York";

/** Same format as the app: 680 g, 233 ml, 12 pcs. */
function qtyText(qty, unit) {
  const rounded = qty >= 10 ? Math.round(qty) : Math.round(qty * 10) / 10;
  return unit === "count" ? `${rounded} pcs` : `${rounded} ${unit}`;
}

function json(body, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: { "content-type": "application/json" } });
}

async function sendIMessage(to, text) {
  const app = await Spectrum({
    projectId: process.env.SPECTRUM_PROJECT_ID,
    projectSecret: process.env.SPECTRUM_PROJECT_SECRET,
    providers: [imessage.config()],
  });
  try {
    const space = await imessage(app).space.create(to);
    await space.send(text);
  } finally {
    await app.stop().catch(() => {});
  }
}

export default {
  async fetch(request) {
    const url = new URL(request.url);
    const fromSchedule = request.headers.has("x-neon-trigger-invocation-id");
    // The function URL is public: anything but Neon's own trigger needs the token.
    if (!fromSchedule && (!process.env.ALERT_TOKEN || url.searchParams.get("token") !== process.env.ALERT_TOKEN)) {
      return json({ sent: false, reason: "forbidden" }, 403);
    }
    const force = url.searchParams.get("force") === "1";       // manual test: send even if already sent today
    const dryRun = url.searchParams.get("dry") === "1";        // build the text, don't send

    const db = new pg.Client({ connectionString: process.env.DATABASE_URL });
    await db.connect();
    try {
      const { rows: [state] } = await db.query(
        "select alert_phone, alerts_enabled, last_alert_day::text as last_alert_day, " +
        "(now() at time zone $1)::date::text as today from app_state where id = 1", [TIMEZONE]);
      if (!state) return json({ sent: false, reason: "Reviri hasn't saved anything to this database yet" });
      if (!state.alert_phone || (!state.alerts_enabled && !force)) {
        return json({ sent: false, reason: "daily alert is off or no phone number in Settings" });
      }
      if (state.last_alert_day === state.today && !force) {
        return json({ sent: false, reason: "already sent today" });
      }

      // Days left = shelf life minus days since purchase, in the user's time zone. 0 = today, 1 = tomorrow.
      const { rows: soon } = await db.query(
        "select display_name, sum(qty_base) as qty, unit_base, " +
        "  min(purchased_on + shelf_life_days - (now() at time zone $1)::date) as days_left " +
        "from inventory_lots where qty_base > 0 " +
        "group by display_name, unit_base " +
        "having min(purchased_on + shelf_life_days - (now() at time zone $1)::date) between 0 and 1 " +
        "order by days_left, display_name", [TIMEZONE]);
      if (soon.length === 0 && !force) return json({ sent: false, reason: "nothing spoils by tomorrow" });

      const lines = soon.length
        ? ["Reviri: use these by tomorrow",
           ...soon.map((r) => `- ${r.display_name}, ${qtyText(Number(r.qty), r.unit_base)} (spoils ${r.days_left === 0 ? "today" : "tomorrow"})`),
           "Open Next Up in Reviri for recipes that use them."]
        : ["Reviri: nothing in your pantry spoils by tomorrow. Nice work."];
      const text = lines.join("\n");
      if (dryRun) return json({ sent: false, dry_run: true, to: state.alert_phone, text });

      await sendIMessage(state.alert_phone, text);
      await db.query("update app_state set last_alert_day = $1::date where id = 1", [state.today]);
      return json({ sent: true, to: state.alert_phone, text, via: fromSchedule ? "schedule" : "manual" });
    } catch (err) {
      const message = String(err?.message ?? err);
      return json({ sent: false, reason: message.includes("Target not allowed")
        ? "Photon's free plan only texts numbers added as Users of your Photon project"
        : message }, 500);
    } finally {
      await db.end().catch(() => {});
    }
  },
};
