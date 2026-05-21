import base64
import json
from datetime import timedelta
from pathlib import Path

import pandas as pd
import streamlit as st

SUPPORT_AGENTS = {
    5217337: "Héloise",
    5391224: "Justine",
    5440474: "Patrick",
    5300290: "Raphael",
}
SLA_SEC = 300
FR_MONTHS = {1:"jan",2:"fév",3:"mar",4:"avr",5:"mai",6:"jun",7:"jul",8:"aoû",9:"sep",10:"oct",11:"nov",12:"déc"}


def fmt_week(d):
    end = d + timedelta(days=6)
    if d.month == end.month:
        return f"{d.day} – {end.day} {FR_MONTHS[end.month]} {end.year}"
    return f"{d.day} {FR_MONTHS[d.month]} – {end.day} {FR_MONTHS[end.month]} {end.year}"


def s(v, decimals=None):
    """Python scalar safe for JSON: NaN → 0."""
    if v is None or (isinstance(v, float) and (v != v)):  # NaN check
        return 0
    try:
        import math
        if math.isnan(float(v)):
            return 0
    except Exception:
        pass
    if decimals is not None:
        return round(float(v), decimals)
    try:
        iv = int(float(v))
        if iv == float(v):
            return iv
    except Exception:
        pass
    return float(v)


@st.cache_data(show_spinner="Chargement des données…")
def build_data():
    import json as _j

    # ── Conversations ──────────────────────────────────────────────────────
    conv = pd.read_csv(
        "CONVERSATIONS.csv",
        usecols=["ID", "CREATED_AT", "PRIORITY", "ASSIGNEE", "CONVERSATION_RATING", "TAGS"],
    )

    def _assignee(x):
        try: return int(_j.loads(x)["id"])
        except: return None

    def _csat(x):
        try:
            r = _j.loads(x).get("rating")
            return float(r) if r is not None else None
        except: return None

    def _tags(x):
        try:
            lst = _j.loads(x)
            return [t["name"] for t in lst if isinstance(t, dict) and t.get("name")]
        except: return []

    conv["assignee_id"]      = conv["ASSIGNEE"].apply(_assignee)
    conv["csat_rating"]      = conv["CONVERSATION_RATING"].apply(_csat)
    conv["created_at"]       = pd.to_datetime(conv["CREATED_AT"], utc=True)
    conv["conversation_id"]  = pd.to_numeric(conv["ID"], errors="coerce").astype("Int64").astype(str)
    dow                      = conv["created_at"].dt.dayofweek
    conv["week_start"]       = conv["created_at"].dt.normalize() - pd.to_timedelta(dow, unit="D")
    conv["day_of_week"]      = dow
    conv["hour_of_day"]      = conv["created_at"].dt.hour
    conv["is_support"]       = conv["assignee_id"].isin(SUPPORT_AGENTS)
    conv["has_csat"]         = conv["csat_rating"].notna()
    conv["is_csat_positive"] = conv["csat_rating"].ge(4)
    conv["is_priority"]      = conv["PRIORITY"] == "priority"
    conv["tag_list"]         = conv["TAGS"].apply(_tags)

    # ── Parts → FRT ───────────────────────────────────────────────────────
    parts = pd.read_csv(
        "CONVERSATION_PARTS.csv",
        usecols=["CONVERSATION_ID", "PART_GROUP", "AUTHOR", "CREATED_AT"],
    )

    def _author_type(x):
        try: return _j.loads(x).get("type", "")
        except: return ""

    parts["author_type"]     = parts["AUTHOR"].apply(_author_type)
    parts["created_at"]      = pd.to_datetime(parts["CREATED_AT"], utc=True)
    parts["conversation_id"] = parts["CONVERSATION_ID"].astype(str)

    msgs = parts[parts["PART_GROUP"] == "Message"]
    first_user = (
        msgs[msgs["author_type"] == "user"]
        .groupby("conversation_id")["created_at"].min()
        .rename("first_user_at").reset_index()
    )
    first_admin = (
        msgs[msgs["author_type"] == "admin"]
        .groupby("conversation_id")["created_at"].min()
        .rename("first_admin_at").reset_index()
    )

    df = conv.merge(first_user, on="conversation_id", how="left")
    df = df.merge(first_admin, on="conversation_id", how="left")
    raw_frt           = (df["first_admin_at"] - df["first_user_at"]).dt.total_seconds()
    df["frt_seconds"] = raw_frt.where(raw_frt > 0)
    df["frt_minutes"] = df["frt_seconds"] / 60
    df["has_reply"]   = df["first_admin_at"].notna()
    df["sla_met"]     = df["frt_seconds"].le(SLA_SEC)

    support     = df[df["is_support"]].copy()
    week_dates  = sorted(support["week_start"].dt.date.unique())
    week_labels = [fmt_week(w) for w in week_dates]

    # ── Team weekly ────────────────────────────────────────────────────────
    team_data = []
    for wd in week_dates:
        w        = support[support["week_start"].dt.date == wd]
        answered = int(w["has_reply"].sum())
        hc       = int(w["has_csat"].sum())
        cp       = int(w["is_csat_positive"].sum()) if hc else 0
        team_data.append({
            "conv":    int(len(w)),
            "csatPos": s(round(100 * cp / hc)) if hc else 0,
            "avgScore":s(w["csat_rating"].mean(), 1),
            "frtPct":  s(round(100 * w["sla_met"].sum() / answered)) if answered else 0,
            "medFrt":  s(w["frt_minutes"].median(), 1),
            "rated":   hc,
            "prio":    int(w["is_priority"].sum()),
        })

    # ── CSAT distribution per week ─────────────────────────────────────────
    csat_data = []
    for wd in week_dates:
        w    = support[support["week_start"].dt.date == wd]
        rated = w[w["has_csat"]]
        csat_data.append([
            int((rated["csat_rating"] == star).sum()) for star in [1, 2, 3, 4, 5]
        ])

    # ── Agents per week ────────────────────────────────────────────────────
    agents_data = []
    agent_list  = list(SUPPORT_AGENTS.items())
    for wd in week_dates:
        w = support[support["week_start"].dt.date == wd]
        row = []
        for agent_id, name in agent_list:
            a        = w[w["assignee_id"] == agent_id]
            answered = int(a["has_reply"].sum())
            hc       = int(a["has_csat"].sum())
            cp       = int(a["is_csat_positive"].sum()) if hc else 0
            no_data  = len(a) == 0
            row.append({
                "name":   name,
                "conv":   int(len(a)),
                # None → null en JSON → affiché "—" dans le dashboard
                "csat":   None if no_data else (s(round(100 * cp / hc)) if hc else None),
                "score":  None if no_data else s(a["csat_rating"].mean(), 1),
                "frtPct": None if no_data else (s(round(100 * a["sla_met"].sum() / answered)) if answered else None),
                "frtMed": None if no_data else s(a["frt_minutes"].median(), 1),
            })
        agents_data.append(row)

    # ── Tags per week ──────────────────────────────────────────────────────
    tag_rows = (
        conv[conv["is_support"]][["conversation_id", "week_start", "tag_list"]]
        .explode("tag_list")
        .dropna(subset=["tag_list"])
        .rename(columns={"tag_list": "tag_name"})
    )
    tag_rows = tag_rows[tag_rows["tag_name"].str.strip() != ""]

    tags_data = []
    if not tag_rows.empty:
        tag_counts = (
            tag_rows.groupby(["tag_name", tag_rows["week_start"].dt.date])
            .size().reset_index(name="count")
            .rename(columns={"week_start": "wd"})
        )
        top5 = tag_counts.groupby("tag_name")["count"].sum().nlargest(5).index
        for tag in top5:
            tc = tag_counts[tag_counts["tag_name"] == tag].set_index("wd")["count"]
            tags_data.append({
                "name":   tag,
                "counts": [int(tc.get(wd, 0)) for wd in week_dates],
            })

    # fallback if no tags in data
    if not tags_data:
        for tag, pct in [("Badgeuse", .20), ("Équipes", .08), ("Postes", .07), ("Absences", .06), ("Contrats", .05)]:
            tags_data.append({
                "name":   tag,
                "counts": [int(t["conv"] * pct) for t in team_data],
            })

    # ── Heatmap (all weeks aggregated) ─────────────────────────────────────
    hours = list(range(7, 19))
    days  = ["Lun","Mar","Mer","Jeu","Ven","Sam","Dim"]
    heat_vals = [
        [int(support[(support["day_of_week"] == d) & (support["hour_of_day"] == h)].shape[0])
         for h in hours]
        for d in range(7)
    ]

    return {
        "weeks":   week_labels,
        "team":    team_data,
        "csat":    csat_data,
        "agents":  agents_data,
        "tags":    tags_data,
        "heatmap": {"days": days, "hours": hours, "vals": heat_vals},
    }


def patch_agent_table(html: str) -> str:
    """Redesign agent table: collapse 4 separate Δ columns into inline stacked deltas."""

    # 1. Inject CSS for stacked metric cells
    css = (
        "\n  .agt-tbl th.th-metric { text-align: center; }"
        "\n  .agt-tbl td.td-metric { text-align: center; }"
        "\n  .mv { font-size: 13px; font-weight: 600; line-height: 1.3; }"
        "\n  .md { font-size: 9.5px; line-height: 1; margin-top: 2px; display: block; }"
    )
    html = html.replace("  /* ── Agent table ── */", css + "\n  /* ── Agent table ── */", 1)

    # 2. Replace thead (10 cols → 6 cols)
    old_head = (
        "          <tr>\n"
        "            <th>Agent</th>\n"
        "            <th>Conv.</th>\n"
        "            <th>Δ</th>\n"
        "            <th>CSAT pos.</th>\n"
        "            <th>Δ</th>\n"
        "            <th>Score</th>\n"
        "            <th>Δ</th>\n"
        "            <th>FRT &lt;5min</th>\n"
        "            <th>Δ</th>\n"
        "            <th>FRT méd.</th>\n"
        "          </tr>"
    )
    new_head = (
        "          <tr>\n"
        "            <th>Agent</th>\n"
        "            <th class=\"th-metric\">Conv.</th>\n"
        "            <th class=\"th-metric\">CSAT pos.</th>\n"
        "            <th class=\"th-metric\">Note moy.</th>\n"
        "            <th class=\"th-metric\">FRT &lt;5min</th>\n"
        "            <th class=\"th-metric\">FRT méd.</th>\n"
        "          </tr>"
    )
    html = html.replace(old_head, new_head, 1)

    # 3. Replace tbody rendering in renderAgents()
    old_rows = (
        "    $('agentTbody').innerHTML = agents.map((a, i) => {\n"
        "      const p = prev?.[i];\n"
        "      const noData = a.conv === 0;\n"
        "      return `<tr${noData ? ' style=\"opacity:.45;\"' : ''}>\n"
        "      <td style=\"font-weight:600;\">${a.name}</td>\n"
        "      <td>${a.conv}</td>\n"
        "      <td>${noData ? nd : deltaHtml(a.conv, p?.conv, true)}</td>\n"
        "      <td>${a.csat === null ? nd : badgeFor(a.csat, 75, 65, '%')}</td>\n"
        "      <td>${a.csat === null ? nd : deltaHtml(a.csat, p?.csat, true)}</td>\n"
        "      <td>${a.score === null ? nd : stars(a.score) + ' <span style=\"font-size:10px;color:var(--color-text-secondary);\">' + a.score.toFixed(1) + '</span>'}</td>\n"
        "      <td>${a.score === null ? nd : deltaHtml(a.score, p?.score, true)}</td>\n"
        "      <td>${a.frtPct === null ? nd : badgeFor(a.frtPct, 45, 35, '%')}</td>\n"
        "      <td>${a.frtPct === null ? nd : deltaHtml(a.frtPct, p?.frtPct, true)}</td>\n"
        "      <td style=\"color:var(--color-text-secondary);\">${a.frtMed === null ? nd : a.frtMed + ' min'}</td>\n"
        "    </tr>`;\n"
        "    }).join('');"
    )
    new_rows = (
        "    $('agentTbody').innerHTML = agents.map((a, i) => {\n"
        "      const p = prev?.[i];\n"
        "      const noData = a.conv === 0;\n"
        "      const frtCol = a.frtMed === null ? '' : a.frtMed <= 5 ? 'color:var(--skello-teal)' : a.frtMed <= 8 ? 'color:#BA7517' : 'color:var(--skello-coral)';\n"
        "      return `<tr${noData ? ' style=\"opacity:.45;\"' : ''}>\n"
        "      <td style=\"font-weight:600;font-size:13px;\">${a.name}</td>\n"
        "      <td class=\"td-metric\"><div class=\"mv\">${a.conv}</div><span class=\"md\">${noData ? '' : deltaHtml(a.conv, p?.conv, true)}</span></td>\n"
        "      <td class=\"td-metric\">${a.csat === null ? nd : '<div>' + badgeFor(a.csat, 75, 65, '%') + '</div><span class=\"md\">' + deltaHtml(a.csat, p?.csat, true) + '</span>'}</td>\n"
        "      <td class=\"td-metric\">${a.score === null ? nd : '<div>' + stars(a.score) + ' <span style=\"font-size:10px;color:var(--color-text-secondary);\">' + a.score.toFixed(1) + '</span></div><span class=\"md\">' + deltaHtml(a.score, p?.score, true) + '</span>'}</td>\n"
        "      <td class=\"td-metric\">${a.frtPct === null ? nd : '<div>' + badgeFor(a.frtPct, 45, 35, '%') + '</div><span class=\"md\">' + deltaHtml(a.frtPct, p?.frtPct, true) + '</span>'}</td>\n"
        "      <td class=\"td-metric\">${a.frtMed === null ? nd : '<div class=\"mv\" style=\"' + frtCol + '\">' + a.frtMed + ' min</div><span class=\"md\">' + deltaHtml(a.frtMed, p?.frtMed, false) + '</span>'}</td>\n"
        "    </tr>`;\n"
        "    }).join('');"
    )
    html = html.replace(old_rows, new_rows, 1)

    # 4. Simplify legend
    html = html.replace(
        "Δ = variation vs semaine précédente · 🟢\n      amélioration · 🔴 dégradation",
        "variation vs S‑1 · <span style=\"color:var(--skello-teal);font-weight:600;\">▲ amélioration</span> · <span style=\"color:var(--skello-coral);font-weight:600;\">▼ dégradation</span>",
        1,
    )

    return html


def inject_data(html: str, data: dict) -> str:
    """Replace the const DATA = {...}; block in the HTML with real data."""
    marker = "const DATA = {"
    start  = html.find(marker)
    if start == -1:
        return html  # nothing to replace

    # Count braces (skipping content inside JS strings) to find the closing };
    i, depth, in_str, str_ch = start + len("const DATA = "), 0, False, ""
    while i < len(html):
        c = html[i]
        if in_str:
            if c == "\\" :
                i += 2; continue
            if c == str_ch:
                in_str = False
        else:
            if c in ('"', "'", "`"):
                in_str, str_ch = True, c
            elif c == "{":
                depth += 1
            elif c == "}":
                depth -= 1
                if depth == 0:
                    end = i + 2 if html[i+1:i+2] == ";" else i + 1
                    break
        i += 1

    data_json = json.dumps(data, ensure_ascii=False)
    return html[:start] + f"const DATA = {data_json};" + html[end:]


# ── Streamlit app ──────────────────────────────────────────────────────────────
st.set_page_config(page_title="Support Skello", layout="wide", page_icon="📊")

# Strip all Streamlit chrome so only the HTML shows
st.markdown("""
<style>
#MainMenu, header, footer, [data-testid="stToolbar"] { visibility: hidden; height: 0; }
.block-container { padding: 0 !important; max-width: 100% !important; }
iframe { border: none; }
</style>
""", unsafe_allow_html=True)

real_data    = build_data()
html_raw     = Path("skello_support_dashboard_lorette.html").read_text()
html_final   = inject_data(html_raw, real_data)
html_final   = patch_agent_table(html_final)

b64 = base64.b64encode(html_final.encode("utf-8")).decode()
st.iframe(f"data:text/html;charset=utf-8;base64,{b64}", height=1400)
