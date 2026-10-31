```dataviewjs
(async () => {
  const paths = {
    globalIndex: "90-archive/task-system-legacy/Task-Registry/global-index.yaml",
    currentSession: "03-AI-Context/Active-Context/current-session.md",
  };

  const escapeHtml = (value) => String(value ?? "")
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/\"/g, "&quot;");

  const stripQuotes = (value) => {
    const trimmed = String(value ?? "").trim();
    if (
      (trimmed.startsWith("\"") && trimmed.endsWith("\"")) ||
      (trimmed.startsWith("'") && trimmed.endsWith("'"))
    ) {
      return trimmed.slice(1, -1);
    }
    return trimmed;
  };

  const slugify = (value) => stripQuotes(value)
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-|-$/g, "") || "unknown";

  const parseYamlListSection = (text, sectionName) => {
    const lines = text.split(/\r?\n/);
    const start = lines.findIndex((line) => line.trim() === `${sectionName}:`);
    if (start === -1) {
      return [];
    }

    const items = [];
    let current = null;

    for (let index = start + 1; index < lines.length; index += 1) {
      const line = lines[index];
      if (!line.trim()) {
        continue;
      }
      if (!line.startsWith("  ")) {
        break;
      }

      const itemMatch = line.match(/^  -\s+([A-Za-z0-9_]+):\s*(.*)$/);
      if (itemMatch) {
        if (current) {
          items.push(current);
        }
        current = {
          [itemMatch[1]]: stripQuotes(itemMatch[2]),
        };
        continue;
      }

      const fieldMatch = line.match(/^    ([A-Za-z0-9_]+):\s*(.*)$/);
      if (fieldMatch && current) {
        current[fieldMatch[1]] = stripQuotes(fieldMatch[2]);
      }
    }

    if (current) {
      items.push(current);
    }

    return items;
  };

  const extractTableValue = (markdown, label) => {
    const escapedLabel = label.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
    const match = markdown.match(new RegExp(`\\|\\s*${escapedLabel}\\s*\\|\\s*(.*?)\\s*\\|`));
    return match ? match[1].replace(/`/g, "").trim() : "unknown";
  };

  const extractBulletSection = (markdown, heading) => {
    const escapedHeading = heading.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
    const sectionMatch = markdown.match(new RegExp(`##\\s+${escapedHeading}\\n([\\s\\S]*?)(?=\\n##\\s+|$)`));
    if (!sectionMatch) {
      return [];
    }
    return Array.from(sectionMatch[1].matchAll(/^- (.*)$/gm), (match) => match[1].trim());
  };

  const priorityRank = (priority) => {
    const match = String(priority ?? "").match(/^Sev-(\d+)$/i);
    return match ? Number(match[1]) : Number.MAX_SAFE_INTEGER;
  };

  const statusBadge = (value) => {
    const text = stripQuotes(value) || "unknown";
    return `<span class="sot-badge sot-status sot-status-${slugify(text)}">${escapeHtml(text)}</span>`;
  };

  const priorityBadge = (value) => {
    const text = stripQuotes(value) || "unknown";
    return `<span class="sot-badge sot-priority sot-priority-${slugify(text)}">${escapeHtml(text)}</span>`;
  };

  const acceptanceBadge = (task) => {
    if (task.acceptance_result) {
      return statusBadge(task.acceptance_result);
    }
    if (task.acceptance_waiver === "true") {
      return statusBadge("waived");
    }
    return statusBadge("unknown");
  };

  const renderList = (items, emptyLabel) => {
    if (!items.length) {
      return `<li class="sot-empty">${escapeHtml(emptyLabel)}</li>`;
    }
    return items.map((item) => `<li>${escapeHtml(item)}</li>`).join("");
  };

  const readFile = async (path) => app.vault.adapter.read(path);

  const [globalIndexText, currentSessionText] = await Promise.all([
    readFile(paths.globalIndex),
    readFile(paths.currentSession),
  ]);

  const phases = parseYamlListSection(globalIndexText, "phases");
  const activePhase = phases.find((p) => String(p.status).toLowerCase() === "active") ?? phases[phases.length - 1];
  const phaseRegistryPath = activePhase?.registry_file || "90-archive/task-system-legacy/Task-Registry/phase-2-registry.yaml";
  const phaseRegistryText = await readFile(phaseRegistryPath);
  const issues = parseYamlListSection(globalIndexText, "issue_index")
    .sort((left, right) => {
      const priorityDelta = priorityRank(left.priority) - priorityRank(right.priority);
      if (priorityDelta !== 0) {
        return priorityDelta;
      }
      return String(left.issue_id).localeCompare(String(right.issue_id));
    });
  const milestones = parseYamlListSection(phaseRegistryText, "milestones");
  const completedTasks = parseYamlListSection(phaseRegistryText, "completed_ids")
    .sort((left, right) => String(right.closed_at ?? "").localeCompare(String(left.closed_at ?? "")));

  const currentPhaseId = extractTableValue(currentSessionText, "Current Phase");
  const currentPhase = phases.find((phase) => phase.phase_id === currentPhaseId) ?? {};
  const activeTasksRaw = extractTableValue(currentSessionText, "Active Task IDs");
  const blockedRaw = extractTableValue(currentSessionText, "Blocked IDs");
  const activeTasks = activeTasksRaw === "none" ? [] : activeTasksRaw.split(",").map((item) => item.trim()).filter(Boolean);
  const blockers = blockedRaw === "none" ? [] : blockedRaw.split(",").map((item) => item.trim()).filter(Boolean);
  const openItems = extractBulletSection(currentSessionText, "Open Items");

  const closedMilestones = milestones.filter((item) => ["closed", "completed"].includes(String(item.status).toLowerCase())).length;
  const totalMilestones = milestones.length;
  const milestonePercent = totalMilestones ? Math.round((closedMilestones / totalMilestones) * 100) : 0;

  const issueSummary = issues.reduce((summary, issue) => {
    const priority = issue.priority || "unknown";
    if (!summary[priority]) {
      summary[priority] = { total: 0, open: 0, resolved: 0, archived: 0, other: 0 };
    }
    summary[priority].total += 1;
    const status = String(issue.status ?? "").toLowerCase();
    if (status === "resolved") {
      summary[priority].resolved += 1;
    } else if (status === "archived") {
      summary[priority].archived += 1;
    } else if (status === "drafted" || status === "open" || status === "active") {
      summary[priority].open += 1;
    } else {
      summary[priority].other += 1;
    }
    return summary;
  }, {});

  const root = dv.container;
  const style = document.createElement("style");
  style.textContent = `
    .sot-dashboard {
      display: grid;
      gap: 1rem;
      margin-top: 0.5rem;
    }
    .sot-grid {
      display: grid;
      gap: 0.75rem;
      grid-template-columns: repeat(auto-fit, minmax(220px, 1fr));
    }
    .sot-card {
      border: 1px solid var(--background-modifier-border);
      border-radius: 12px;
      background: var(--background-secondary);
      padding: 0.9rem 1rem;
      box-shadow: 0 1px 2px rgba(0, 0, 0, 0.08);
    }
    .sot-card h3,
    .sot-card h4 {
      margin: 0 0 0.4rem 0;
    }
    .sot-metric {
      font-size: 1.8rem;
      font-weight: 700;
      margin: 0;
    }
    .sot-subtle {
      color: var(--text-muted);
      font-size: 0.9rem;
      margin-top: 0.2rem;
    }
    .sot-progress {
      width: 100%;
      height: 10px;
      border-radius: 999px;
      overflow: hidden;
      background: var(--background-modifier-border);
      margin: 0.75rem 0 0.35rem;
    }
    .sot-progress > span {
      display: block;
      height: 100%;
      background: linear-gradient(90deg, var(--interactive-accent), color-mix(in srgb, var(--interactive-accent) 60%, white));
    }
    .sot-list {
      display: grid;
      gap: 0.5rem;
      margin-top: 0.85rem;
    }
    .sot-row {
      display: flex;
      justify-content: space-between;
      gap: 0.75rem;
      align-items: center;
      border-bottom: 1px solid var(--background-modifier-border-hover);
      padding-bottom: 0.45rem;
    }
    .sot-row:last-child {
      border-bottom: 0;
      padding-bottom: 0;
    }
    .sot-title {
      font-weight: 600;
    }
    .sot-meta {
      display: flex;
      gap: 0.4rem;
      flex-wrap: wrap;
      justify-content: flex-end;
    }
    .sot-badge {
      display: inline-flex;
      align-items: center;
      border-radius: 999px;
      padding: 0.18rem 0.5rem;
      font-size: 0.8rem;
      line-height: 1.2;
      border: 1px solid var(--background-modifier-border);
      background: var(--background-primary-alt);
    }
    .sot-priority-sev-0 { color: #ff6b6b; border-color: #ff6b6b55; }
    .sot-priority-sev-1 { color: #ffa94d; border-color: #ffa94d55; }
    .sot-priority-sev-2 { color: #4dabf7; border-color: #4dabf755; }
    .sot-priority-sev-3 { color: #94d82d; border-color: #94d82d55; }
    .sot-status-closed,
    .sot-status-completed,
    .sot-status-resolved,
    .sot-status-pass,
    .sot-status-passed,
    .sot-status-verified,
    .sot-status-synced {
      color: #2f9e44;
      border-color: #2f9e4455;
    }
    .sot-status-in-progress,
    .sot-status-active,
    .sot-status-pending {
      color: #e67700;
      border-color: #e6770055;
    }
    .sot-status-drafted,
    .sot-status-archived {
      color: var(--text-muted);
    }
    .sot-status-waived {
      color: #868e96;
      border-color: #868e9655;
      font-style: italic;
    }
    .sot-inline-list {
      margin: 0.45rem 0 0;
      padding-left: 1.1rem;
    }
    .sot-empty {
      color: var(--text-muted);
    }
    .sot-table {
      width: 100%;
      border-collapse: collapse;
      margin-top: 0.75rem;
    }
    .sot-table th,
    .sot-table td {
      text-align: left;
      padding: 0.55rem 0.4rem;
      border-bottom: 1px solid var(--background-modifier-border-hover);
      vertical-align: top;
    }
    .sot-table th {
      color: var(--text-muted);
      font-weight: 600;
    }
  `;
  root.appendChild(style);

  const issueCards = Object.keys(issueSummary)
    .sort((left, right) => priorityRank(left) - priorityRank(right))
    .map((priority) => {
      const counts = issueSummary[priority];
      return `
        <div class="sot-card">
          <h4>${priorityBadge(priority)} <span class="sot-title">${escapeHtml(priority)} issues</span></h4>
          <div class="sot-subtle">
            total ${counts.total} · open ${counts.open} · resolved ${counts.resolved} · archived ${counts.archived}${counts.other ? ` · other ${counts.other}` : ""}
          </div>
        </div>
      `;
    })
    .join("");

  root.insertAdjacentHTML("beforeend", `
    <div class="sot-dashboard">
      <div class="sot-grid">
        <div class="sot-card">
          <h3>Phase Progress</h3>
          <p class="sot-metric">${closedMilestones}/${totalMilestones}</p>
          <div class="sot-subtle">completed milestones in ${escapeHtml(currentPhaseId)}</div>
          <div class="sot-progress"><span style="width: ${milestonePercent}%"></span></div>
          <div class="sot-subtle">${milestonePercent}% complete</div>
        </div>
        <div class="sot-card">
          <h3>Current Session</h3>
          <p class="sot-metric">${escapeHtml(currentPhaseId)}</p>
          <div class="sot-subtle">${escapeHtml(currentPhase.title || "Unknown phase")} · ${statusBadge(currentPhase.status || "unknown")}</div>
          <ul class="sot-inline-list">
            <li>Active tasks: ${escapeHtml(activeTasks.length ? activeTasks.join(", ") : "none")}</li>
            <li>Blockers: ${escapeHtml(blockers.length ? blockers.join(", ") : "none")}</li>
          </ul>
        </div>
      </div>

      <div class="sot-card">
        <h3>Milestone Status</h3>
        <div class="sot-list">
          ${milestones.map((milestone) => `
            <div class="sot-row">
              <div>
                <div class="sot-title">${escapeHtml(milestone.id)} · ${escapeHtml(milestone.title)}</div>
                <div class="sot-subtle">${escapeHtml(milestone.notes || "No notes")}</div>
              </div>
              <div class="sot-meta">
                ${statusBadge(milestone.status)}
                ${statusBadge(milestone.verification_state)}
                ${statusBadge(milestone.docs_state)}
              </div>
            </div>
          `).join("")}
        </div>
      </div>

      <div class="sot-card">
        <h3>Recent Completed Tasks</h3>
        <table class="sot-table">
          <thead>
            <tr>
              <th>Task</th>
              <th>Status</th>
              <th>Acceptance</th>
              <th>Closed</th>
            </tr>
          </thead>
          <tbody>
            ${completedTasks.map((task) => `
              <tr>
                <td>${escapeHtml(task.task_id || "unknown")}</td>
                <td>${statusBadge(task.status)}</td>
                <td>${acceptanceBadge(task)}</td>
                <td>${escapeHtml(task.closed_at || "unknown")}</td>
              </tr>
            `).join("")}
          </tbody>
        </table>
      </div>

      <div class="sot-grid">
        ${issueCards}
      </div>

      <div class="sot-card">
        <h3>Issue Index</h3>
        <div class="sot-list">
          ${issues.map((issue) => `
            <div class="sot-row">
              <div>
                <div class="sot-title">${escapeHtml(issue.issue_id)}</div>
                <div class="sot-subtle">${escapeHtml(issue.path || "")}</div>
              </div>
              <div class="sot-meta">
                ${priorityBadge(issue.priority)}
                ${statusBadge(issue.status)}
              </div>
            </div>
          `).join("")}
        </div>
      </div>

      <div class="sot-card">
        <h3>Open Items</h3>
        <ul class="sot-inline-list">
          ${renderList(openItems, "No open items")}
        </ul>
      </div>
    </div>
  `);
})();
```
