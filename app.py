import json
from datetime import timedelta

import pandas as pd
import plotly.express as px
import streamlit as st

# ─── Constants ────────────────────────────────────────────────────────────────
SUPPORT_AGENTS = {
    5217337: "Héloise",
    5391224: "Justine",
    5440474: "Patrick",
    5300290: "Raphael",
}
SLA_SEC = 300  # 5 minutes


# ─── Data loading ─────────────────────────────────────────────────────────────
@st.cache_data(show_spinner="Chargement des données…")
def load_data() -> pd.DataFrame:
    conv = pd.read_csv(
        "CONVERSATIONS.csv",
        usecols=["ID", "CREATED_AT", "STATE", "OPEN", "PRIORITY", "ASSIGNEE", "CONVERSATION_RATING"],
    )

    def _assignee(x):
        try:
            return int(json.loads(x)["id"])
        except Exception:
            return None

    def _csat(x):
        try:
            r = json.loads(x).get("rating")
            return float(r) if r is not None else None
        except Exception:
            return None

    conv["assignee_id"]     = conv["ASSIGNEE"].apply(_assignee)
    conv["csat_rating"]     = conv["CONVERSATION_RATING"].apply(_csat)
    conv["created_at"]      = pd.to_datetime(conv["CREATED_AT"], utc=True)
    # IDs are read as floats (e.g. 53815801337475.0) — normalize to int string
    conv["conversation_id"] = pd.to_numeric(conv["ID"], errors="coerce").astype("Int64").astype(str)

    dow = conv["created_at"].dt.dayofweek  # 0 = Monday
    conv["week_start"]  = conv["created_at"].dt.normalize() - pd.to_timedelta(dow, unit="D")
    conv["day_of_week"] = dow
    conv["hour_of_day"] = conv["created_at"].dt.hour
    conv["is_support"]  = conv["assignee_id"].isin(SUPPORT_AGENTS)
    conv["agent_name"]  = conv["assignee_id"].map(SUPPORT_AGENTS)

    parts = pd.read_csv(
        "CONVERSATION_PARTS.csv",
        usecols=["CONVERSATION_ID", "PART_GROUP", "AUTHOR", "CREATED_AT"],
    )

    def _author_type(x):
        try:
            return json.loads(x).get("type", "")
        except Exception:
            return ""

    parts["author_type"]     = parts["AUTHOR"].apply(_author_type)
    parts["created_at"]      = pd.to_datetime(parts["CREATED_AT"], utc=True)
    parts["conversation_id"] = parts["CONVERSATION_ID"].astype(str)

    first_resp = (
        parts.loc[(parts["PART_GROUP"] == "Message") & (parts["author_type"] == "admin")]
        .groupby("conversation_id")["created_at"]
        .min()
        .rename("first_response_at")
        .reset_index()
    )

    df = conv.merge(first_resp, on="conversation_id", how="left")
    df["first_response_sec"] = (df["first_response_at"] - df["created_at"]).dt.total_seconds()
    df["first_response_min"] = df["first_response_sec"] / 60
    df["has_reply"] = df["first_response_at"].notna()
    df["sla_met"]   = df["first_response_sec"].le(SLA_SEC)  # NaN → False
    df["has_csat"]  = df["csat_rating"].notna()

    return df.dropna(subset=["created_at"])


# ─── Helpers ──────────────────────────────────────────────────────────────────
def week_kpis(data: pd.DataFrame) -> dict:
    answered = int(data["has_reply"].sum())
    return dict(
        total    = len(data),
        csat     = data["csat_rating"].mean(),
        sla_pct  = 100 * data["sla_met"].sum() / answered if answered else float("nan"),
        med_resp = data["first_response_min"].median(),
    )


def pct_delta(curr, prev) -> str | None:
    try:
        if pd.isna(curr) or pd.isna(prev) or prev == 0:
            return None
        d = 100 * (curr - prev) / abs(prev)
        return f"{'+' if d >= 0 else ''}{d:.1f} %"
    except Exception:
        return None


# ─── App layout ───────────────────────────────────────────────────────────────
st.set_page_config(page_title="Support Skello", layout="wide", page_icon="📊")
st.title("📊 Support Skello — Reporting hebdomadaire")

df      = load_data()
support = df[df["is_support"]].copy()

# ── Week selector ─────────────────────────────────────────────────────────────
week_dates = sorted(support["week_start"].dt.date.unique(), reverse=True)
selected   = st.selectbox(
    "Semaine",
    week_dates,
    format_func=lambda d: (
        f"Semaine du {d.strftime('%d %b %Y')} "
        f"au {(d + timedelta(days=6)).strftime('%d %b %Y')}"
    ),
)
prev_week = selected - timedelta(weeks=1)

curr_df = support[support["week_start"].dt.date == selected]
prev_df = support[support["week_start"].dt.date == prev_week]
kpi_c   = week_kpis(curr_df)
kpi_p   = week_kpis(prev_df)

# ── KPI cards ─────────────────────────────────────────────────────────────────
c1, c2, c3, c4 = st.columns(4)

c1.metric(
    "Conversations", kpi_c["total"],
    delta=pct_delta(kpi_c["total"], kpi_p["total"]),
)
c2.metric(
    "CSAT",
    f"{kpi_c['csat']:.2f} / 5" if not pd.isna(kpi_c["csat"]) else "—",
    delta=pct_delta(kpi_c["csat"], kpi_p["csat"]),
)
c3.metric(
    "SLA < 5 min",
    f"{kpi_c['sla_pct']:.1f} %" if not pd.isna(kpi_c["sla_pct"]) else "—",
    delta=pct_delta(kpi_c["sla_pct"], kpi_p["sla_pct"]),
)
c4.metric(
    "1ère réponse (médiane)",
    f"{kpi_c['med_resp']:.1f} min" if not pd.isna(kpi_c["med_resp"]) else "—",
    delta=pct_delta(kpi_c["med_resp"], kpi_p["med_resp"]),
    delta_color="inverse",
)

st.caption(
    f"Périmètre : {kpi_c['total']} conversations assignées à l'équipe Support "
    f"({len(curr_df[curr_df['has_csat']]):d} évaluées CSAT, "
    f"{int(curr_df['has_reply'].sum()):d} avec réponse admin)"
)

st.divider()

# ── Heatmap + Agent table ─────────────────────────────────────────────────────
left, right = st.columns([3, 2])

with left:
    st.subheader("Volume — 4 dernières semaines")
    cutoff   = selected - timedelta(weeks=3)
    heat_src = support[support["week_start"].dt.date >= cutoff]
    pivot = (
        heat_src.groupby(["day_of_week", "hour_of_day"])
        .size()
        .reset_index(name="n")
        .pivot(index="day_of_week", columns="hour_of_day", values="n")
        .fillna(0)
        .reindex(range(7))
    )
    pivot.index = ["Lundi", "Mardi", "Mercredi", "Jeudi", "Vendredi", "Samedi", "Dimanche"]
    fig_heat = px.imshow(
        pivot,
        color_continuous_scale="Blues",
        labels={"x": "Heure", "y": "", "color": "Conv."},
        aspect="auto",
    )
    fig_heat.update_layout(height=300, margin=dict(l=0, r=0, t=0, b=0))
    st.plotly_chart(fig_heat, use_container_width=True)

with right:
    st.subheader("Performance par agent — semaine sélectionnée")
    rows = []
    for agent_id, name in SUPPORT_AGENTS.items():
        a = curr_df[curr_df["assignee_id"] == agent_id]
        if a.empty:
            continue
        answered = int(a["has_reply"].sum())
        rows.append({
            "Agent":          name,
            "Conv.":          len(a),
            "CSAT":           round(float(a["csat_rating"].mean()), 1) if a["has_csat"].any() else None,
            "SLA %":          round(100 * float(a["sla_met"].sum()) / answered, 0) if answered else None,
            "Tps méd. (min)": round(float(a["first_response_min"].median()), 1) if answered else None,
        })
    if rows:
        agent_df = pd.DataFrame(rows)
        st.dataframe(agent_df, hide_index=True, use_container_width=True)
    else:
        st.info("Aucune donnée pour cette semaine.")

st.divider()

# ── 8-week trend ──────────────────────────────────────────────────────────────
st.subheader("Évolution sur 8 semaines")

last8 = sorted(support["week_start"].dt.date.unique())[-8:]
trend = support[support["week_start"].dt.date.isin(last8)]

weekly = trend.groupby("week_start").agg(
    Conversations = ("conversation_id", "count"),
    avg_csat      = ("csat_rating", "mean"),
    sla_sum       = ("sla_met", "sum"),
    reply_sum     = ("has_reply", "sum"),
    med_resp      = ("first_response_min", "median"),
).reset_index()

weekly["CSAT"]               = weekly["avg_csat"].round(2)
weekly["SLA %"]              = (100 * weekly["sla_sum"] / weekly["reply_sum"].clip(lower=1)).round(1)
weekly["Réponse méd. (min)"] = weekly["med_resp"].round(1)
weekly["Semaine"]            = weekly["week_start"].dt.strftime("S du %d/%m")

t1, t2, t3, t4 = st.columns(4)
charts = [
    (t1, "Conversations", False),
    (t2, "CSAT",          False),
    (t3, "SLA %",         False),
    (t4, "Réponse méd. (min)", True),
]
for col, metric, invert in charts:
    fig = px.line(weekly, x="Semaine", y=metric, markers=True, title=metric)
    fig.update_layout(
        height=230, margin=dict(l=0, r=0, t=30, b=0),
        xaxis_title="", yaxis_title="",
    )
    if invert:
        fig.update_yaxes(autorange="reversed")
    col.plotly_chart(fig, use_container_width=True)

st.caption("⚠️ Timestamps en UTC — ajouter CONVERT_TIMEZONE('Europe/Paris') pour les heures locales.")
