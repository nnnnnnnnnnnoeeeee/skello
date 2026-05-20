import json
from datetime import timedelta

import pandas as pd
import plotly.express as px
import plotly.graph_objects as go
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

    conv["assignee_id"]      = conv["ASSIGNEE"].apply(_assignee)
    conv["csat_rating"]      = conv["CONVERSATION_RATING"].apply(_csat)
    conv["created_at"]       = pd.to_datetime(conv["CREATED_AT"], utc=True)
    # IDs loaded as floats (53815801337475.0) — strip decimal before joining
    conv["conversation_id"]  = pd.to_numeric(conv["ID"], errors="coerce").astype("Int64").astype(str)

    dow = conv["created_at"].dt.dayofweek  # 0 = Monday
    conv["week_start"]       = conv["created_at"].dt.normalize() - pd.to_timedelta(dow, unit="D")
    conv["day_of_week"]      = dow
    conv["hour_of_day"]      = conv["created_at"].dt.hour
    conv["is_support"]       = conv["assignee_id"].isin(SUPPORT_AGENTS)
    conv["agent_name"]       = conv["assignee_id"].map(SUPPORT_AGENTS)
    # CSAT positif = note >= 4 (Intercom : 4=Good, 5=Amazing)
    conv["is_csat_positive"] = conv["csat_rating"].ge(4)
    conv["has_csat"]         = conv["csat_rating"].notna()

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

    msgs = parts[parts["PART_GROUP"] == "Message"]

    # FRT = 1er message client → 1ère réponse admin (bots exclus)
    first_user = (
        msgs[msgs["author_type"] == "user"]
        .groupby("conversation_id")["created_at"]
        .min().rename("first_user_at").reset_index()
    )
    first_admin = (
        msgs[msgs["author_type"] == "admin"]
        .groupby("conversation_id")["created_at"]
        .min().rename("first_admin_at").reset_index()
    )

    df = conv.merge(first_user, on="conversation_id", how="left")
    df = df.merge(first_admin, on="conversation_id", how="left")

    raw_frt          = (df["first_admin_at"] - df["first_user_at"]).dt.total_seconds()
    df["frt_seconds"] = raw_frt.where(raw_frt > 0)   # guard against data anomalies
    df["frt_minutes"] = df["frt_seconds"] / 60
    df["has_reply"]   = df["first_admin_at"].notna()
    df["sla_met"]     = df["frt_seconds"].le(SLA_SEC)  # NaN → False

    return df.dropna(subset=["created_at"])


# ─── Helpers ──────────────────────────────────────────────────────────────────
def week_kpis(data: pd.DataFrame) -> dict:
    answered  = int(data["has_reply"].sum())
    has_csat  = int(data["has_csat"].sum())
    csat_pos  = int(data["is_csat_positive"].sum()) if has_csat else 0
    return dict(
        total        = len(data),
        csat         = data["csat_rating"].mean(),
        csat_count   = has_csat,
        csat_pos_pct = 100 * csat_pos / has_csat if has_csat else float("nan"),
        sla_pct      = 100 * data["sla_met"].sum() / answered if answered else float("nan"),
        sla_strict   = 100 * data["sla_met"].sum() / len(data) if len(data) else float("nan"),
        med_frt      = data["frt_minutes"].median(),
        answered     = answered,
    )


def pct_delta(curr, prev) -> str | None:
    try:
        if pd.isna(curr) or pd.isna(prev) or prev == 0:
            return None
        d = 100 * (curr - prev) / abs(prev)
        return f"{'+' if d >= 0 else ''}{d:.1f} %"
    except Exception:
        return None


def abs_delta(curr, prev, fmt=".1f") -> str:
    try:
        if curr is None or prev is None or pd.isna(curr) or pd.isna(prev):
            return "—"
        d = curr - prev
        arrow = "↑" if d > 0 else ("↓" if d < 0 else "=")
        return f"{arrow} {abs(d):{fmt}}"
    except Exception:
        return "—"


# ─── Page setup ───────────────────────────────────────────────────────────────
st.set_page_config(page_title="Support Skello", layout="wide", page_icon="📊")
st.title("📊 Support Skello — Reporting hebdomadaire")
st.caption("Héloise · Justine · Patrick · Raphael — FRT mesuré du 1er message client → 1ère réponse admin (bots exclus)")

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

# ── Section 1 : KPI cards ─────────────────────────────────────────────────────
c1, c2, c3, c4 = st.columns(4)

c1.metric(
    "Conversations", kpi_c["total"],
    delta=pct_delta(kpi_c["total"], kpi_p["total"]),
)
c2.metric(
    "CSAT moyen",
    f"{kpi_c['csat']:.2f} / 5" if not pd.isna(kpi_c["csat"]) else "—",
    delta=pct_delta(kpi_c["csat"], kpi_p["csat"]),
    help="Note moyenne sur 5. CSAT positif = note ≥ 4.",
)
c3.metric(
    "SLA < 5 min",
    f"{kpi_c['sla_pct']:.1f} %" if not pd.isna(kpi_c["sla_pct"]) else "—",
    delta=pct_delta(kpi_c["sla_pct"], kpi_p["sla_pct"]),
    help=(
        f"% conversations avec FRT ≤ 5 min parmi celles ayant reçu une réponse ({kpi_c['answered']}).\n"
        f"SLA strict (toutes conv.) : {kpi_c['sla_strict']:.1f} %"
    ),
)
c4.metric(
    "FRT médian",
    f"{kpi_c['med_frt']:.1f} min" if not pd.isna(kpi_c["med_frt"]) else "—",
    delta=pct_delta(kpi_c["med_frt"], kpi_p["med_frt"]),
    delta_color="inverse",
    help="Médiane du First Response Time. Médiane choisie vs moyenne : robuste aux conversations ouvertes la nuit/week-end.",
)

# CSAT context line
if kpi_c["csat_count"] > 0:
    csat_rate = 100 * kpi_c["csat_count"] / kpi_c["total"]
    st.caption(
        f"💬 CSAT : **{kpi_c['csat_count']}** évaluations reçues "
        f"(taux de réponse : **{csat_rate:.0f}%**) — "
        f"**{kpi_c['csat_pos_pct']:.0f}%** positives (note ≥ 4)"
    )

st.divider()

# ── Section 2 : Heatmap + Agent table ────────────────────────────────────────
left, right = st.columns([3, 2])

with left:
    st.subheader("📅 Volume horaire — 4 dernières semaines")
    cutoff   = selected - timedelta(weeks=3)
    heat_src = support[support["week_start"].dt.date >= cutoff]
    pivot = (
        heat_src.groupby(["day_of_week", "hour_of_day"])
        .size().reset_index(name="n")
        .pivot(index="day_of_week", columns="hour_of_day", values="n")
        .fillna(0).reindex(range(7))
    )
    pivot.index = ["Lundi", "Mardi", "Mercredi", "Jeudi", "Vendredi", "Samedi", "Dimanche"]
    fig_heat = px.imshow(
        pivot, color_continuous_scale="Blues",
        labels={"x": "Heure", "y": "", "color": "Conv."},
        aspect="auto",
    )
    fig_heat.update_layout(height=300, margin=dict(l=0, r=0, t=0, b=0))
    st.plotly_chart(fig_heat, use_container_width=True)

with right:
    st.subheader("👤 Performance par agent vs S-1")
    rows = []
    for agent_id, name in SUPPORT_AGENTS.items():
        a_c = curr_df[curr_df["assignee_id"] == agent_id]
        a_p = prev_df[prev_df["assignee_id"] == agent_id]
        if a_c.empty:
            continue
        ans_c = int(a_c["has_reply"].sum())
        ans_p = int(a_p["has_reply"].sum()) if not a_p.empty else 0

        csat_c = round(float(a_c["csat_rating"].mean()), 1) if a_c["has_csat"].any() else None
        csat_p = round(float(a_p["csat_rating"].mean()), 1) if (not a_p.empty and a_p["has_csat"].any()) else None
        sla_c  = round(100 * float(a_c["sla_met"].sum()) / ans_c, 0) if ans_c else None
        sla_p  = round(100 * float(a_p["sla_met"].sum()) / ans_p, 0) if ans_p else None
        frt_c  = round(float(a_c["frt_minutes"].median()), 1) if ans_c else None

        rows.append({
            "Agent":     name,
            "Conv.":     len(a_c),
            "CSAT":      csat_c,
            "Δ CSAT":    abs_delta(csat_c, csat_p),
            "SLA %":     sla_c,
            "Δ SLA":     abs_delta(sla_c, sla_p, fmt=".0f"),
            "FRT (min)": frt_c,
        })

    if rows:
        st.dataframe(pd.DataFrame(rows), hide_index=True, use_container_width=True)
    else:
        st.info("Aucune donnée pour cette semaine.")

st.divider()

# ── Section 3 : CSAT distribution ────────────────────────────────────────────
st.subheader("⭐ Distribution des notes CSAT — semaine sélectionnée")
csat_l, csat_r = st.columns([2, 3])

with csat_l:
    csat_data = curr_df[curr_df["has_csat"]].copy()
    if not csat_data.empty:
        dist = (
            csat_data.groupby("csat_rating").size()
            .reindex([1, 2, 3, 4, 5], fill_value=0)
            .reset_index(name="count")
        )
        dist["pct"]   = (100 * dist["count"] / dist["count"].sum()).round(1)
        dist["label"] = dist["csat_rating"].astype(int).astype(str)
        COLOR_MAP     = {1: "#d32f2f", 2: "#f57c00", 3: "#fbc02d", 4: "#7cb342", 5: "#2e7d32"}
        fig_dist = px.bar(
            dist, x="label", y="count",
            text=dist["pct"].apply(lambda x: f"{x:.0f}%"),
            color="label",
            color_discrete_map={str(k): v for k, v in COLOR_MAP.items()},
            labels={"label": "Note", "count": "Conversations"},
        )
        fig_dist.update_traces(textposition="outside")
        fig_dist.update_layout(
            height=280, margin=dict(l=0, r=0, t=10, b=0),
            showlegend=False, xaxis_title="Note CSAT", yaxis_title="",
        )
        st.plotly_chart(fig_dist, use_container_width=True)
    else:
        st.info("Aucune évaluation CSAT cette semaine.")

with csat_r:
    st.markdown("**Interprétation CSAT**")
    if not pd.isna(kpi_c["csat"]) and kpi_c["csat_count"] > 0:
        st.markdown(f"""
| Indicateur | Cette semaine | S-1 |
|---|---|---|
| Note moyenne | **{kpi_c['csat']:.2f} / 5** | {kpi_p['csat']:.2f} / 5 |
| % positives (≥ 4) | **{kpi_c['csat_pos_pct']:.0f}%** | {kpi_p['csat_pos_pct']:.0f}% |
| Nb évaluations | **{kpi_c['csat_count']}** | {kpi_p['csat_count']} |
| Taux de réponse | **{100*kpi_c['csat_count']/kpi_c['total']:.0f}%** | {100*kpi_p['csat_count']/kpi_p['total']:.0f}% |
""")
        st.info(
            "⚠️ **Taux de réponse CSAT faible (~35%)** : interpréter avec prudence. "
            "Les clients mécontents sont sur-représentés parmi ceux qui évaluent."
        )

st.divider()

# ── Section 4 : Tendances sur 8 semaines ──────────────────────────────────────
st.subheader("📈 Évolution sur 8 semaines")

last8  = sorted(support["week_start"].dt.date.unique())[-8:]
trend  = support[support["week_start"].dt.date.isin(last8)]

weekly = trend.groupby("week_start").agg(
    Conversations     = ("conversation_id", "count"),
    avg_csat          = ("csat_rating", "mean"),
    csat_pos          = ("is_csat_positive", "sum"),
    csat_count        = ("has_csat", "sum"),
    sla_sum           = ("sla_met", "sum"),
    reply_sum         = ("has_reply", "sum"),
    med_frt           = ("frt_minutes", "median"),
).reset_index()

weekly["CSAT"]              = weekly["avg_csat"].round(2)
weekly["CSAT positif %"]    = (100 * weekly["csat_pos"] / weekly["csat_count"].clip(lower=1)).round(1)
weekly["SLA %"]             = (100 * weekly["sla_sum"] / weekly["reply_sum"].clip(lower=1)).round(1)
weekly["FRT méd. (min)"]    = weekly["med_frt"].round(1)
weekly["Semaine"]           = weekly["week_start"].dt.strftime("%d/%m")

t1, t2, t3, t4 = st.columns(4)
charts = [
    (t1, "Conversations",   False, None),
    (t2, "CSAT",            False, [1, 5]),
    (t3, "SLA %",           False, [0, 100]),
    (t4, "FRT méd. (min)",  True,  None),
]
for col, metric, invert, yrange in charts:
    fig = px.line(weekly, x="Semaine", y=metric, markers=True, title=metric)
    fig.update_layout(
        height=220, margin=dict(l=0, r=0, t=30, b=0),
        xaxis_title="", yaxis_title="",
    )
    if yrange:
        fig.update_yaxes(range=yrange)
    if invert:
        fig.update_yaxes(autorange="reversed")
    col.plotly_chart(fig, use_container_width=True)

st.caption("⚠️ Timestamps en UTC — à convertir en Europe/Paris pour les heures locales dans le heatmap.")
