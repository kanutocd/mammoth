const escapeHTML = (value) =>
  String(value ?? "").replace(
    /[&<>"']/g,
    (character) =>
      ({
        "&": "&amp;",
        "<": "&lt;",
        ">": "&gt;",
        '"': "&quot;",
        "'": "&#39;",
      })[character],
  );

function eventName(payload) {
  return (
    payload.type ||
    payload.event_type ||
    payload.kind ||
    payload.name ||
    "database.change"
  );
}

function summarize(payload) {
  const events =
    payload.events || payload.changes || payload.transaction?.events || [];
  const first = Array.isArray(events) ? events[0] : null;
  const source = first || payload;

  return {
    table:
      source.entity ||
      source.table ||
      source.table_name ||
      source.relation ||
      "—",
    operation: source.operation || source.action || source.op || "—",
    count:
      payload.event_count ||
      (Array.isArray(events) && events.length ? events.length : 1),
  };
}

function groupByDelivery(events) {
  const groups = new Map();

  for (const event of events) {
    const attempts = groups.get(event.delivery_key) || [];
    attempts.push(event);
    groups.set(event.delivery_key, attempts);
  }

  return [...groups.values()]
    .map((attempts) =>
      attempts.sort(
        (left, right) =>
          Date.parse(right.received_at) - Date.parse(left.received_at),
      ),
    )
    .sort(
      (left, right) =>
        Date.parse(right[0].received_at) - Date.parse(left[0].received_at),
    );
}

function expandedDeliveries(root) {
  return new Set(
    [...root.querySelectorAll("article[data-delivery-key] details[open]")].map(
      (details) => details.closest("article").dataset.deliveryKey,
    ),
  );
}

function attemptTimeline(attempts) {
  return attempts
    .map(
      (attempt) => `
        <li>
          <span class="${attempt.response_status === 200 ? "success" : "failure"}">
            HTTP ${attempt.response_status}
          </span>
          <span>Attempt ${attempt.attempt}</span>
          <time>${escapeHTML(new Date(attempt.received_at).toLocaleTimeString())}</time>
        </li>
      `,
    )
    .join("");
}

function eventArticle(attempts, expanded) {
  const event = attempts[0];
  const summary = summarize(event.payload);
  const article = document.createElement("article");
  article.dataset.deliveryKey = event.delivery_key;
  article.innerHTML = `
    <div class="event-head">
      <div>
        <span class="event-type">${escapeHTML(eventName(event.payload))}</span>
        <h2>${escapeHTML(summary.operation)} ${escapeHTML(summary.table)}</h2>
      </div>
      <span class="verified">✓ HMAC verified</span>
    </div>
    <div class="meta">
      <span>${escapeHTML(summary.count)} change${summary.count === 1 ? "" : "s"}</span>
      <span>Delivery ${escapeHTML(event.delivery_key.slice(0, 12))}</span>
      <span>${attempts.length} attempt${attempts.length === 1 ? "" : "s"}</span>
    </div>
    <ol class="timeline">${attemptTimeline(attempts)}</ol>
    <details>
      <summary>Inspect JSON payload</summary>
      <pre>${escapeHTML(JSON.stringify(event.payload, null, 2))}</pre>
    </details>
  `;

  if (expanded.has(event.delivery_key)) {
    article.querySelector("details").open = true;
  }

  return article;
}

async function refresh() {
  const response = await fetch("/api/events");
  const data = await response.json();
  const root = document.querySelector("#events");
  const expanded = expandedDeliveries(root);
  const groups = groupByDelivery(data.events);

  document.querySelector("#failure-toggle").checked = data.failures_enabled;
  document.querySelector("#count").textContent =
    `${data.events.length} requests · ${groups.length} deliveries`;
  root.replaceChildren();

  if (!data.events.length) {
    root.append(document.querySelector("#empty").content.cloneNode(true));
  }

  for (const attempts of groups) {
    root.append(eventArticle(attempts, expanded));
  }

  document.querySelector("#connection").textContent =
    `Updated ${new Date().toLocaleTimeString()}`;
}

document
  .querySelector("#failure-toggle")
  .addEventListener("change", async (event) => {
    await fetch("/api/failures", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ enabled: event.target.checked }),
    });
    await refresh();
  });

document.querySelector("#clear").addEventListener("click", async () => {
  await fetch("/api/events/clear", { method: "POST" });
  await refresh();
});

refresh();
setInterval(refresh, 1500);
