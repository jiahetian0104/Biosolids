import math
from dataclasses import dataclass

import numpy as np
import pandas as pd
import plotly.express as px
import streamlit as st


st.set_page_config(
    page_title="PFAS Soil–Crop–Cattle Exposure Model",
    page_icon="🐄",
    layout="wide",
)


@dataclass
class ModelParams:
    # Growth / intake parameters
    Cgr: float = 0.0115
    Cgrs: float = 0.27
    MW: float = 640.0
    Crs: float = 0.025
    Cq: float = 1.7
    Crc: float = 1.0
    Cbc: float = 1.5

    # Exposure parameters
    soil_conc: float = 98.57      # ng/g
    stover_conc: float = 12.30    # ng/g
    B_feed: float = 0.75
    B_soil: float = 0.20

    # TK parameters
    DT50: float = 74.1            # days
    Vd_coeff: float = 0.085       # L/kg, model simplification
    PM: float = 0.08              # muscle partition coefficient
    PL: float = 1.44              # liver partition coefficient
    PK: float = 0.50              # kidney partition coefficient

    # Simulation
    harvest_day: int = 730
    initial_body_burden: float = 0.0


@dataclass
class HumanExposureParams:
    child_bw: float = 15.0            # kg
    adult_bw: float = 80.0            # kg
    child_beef_g_day: float = 30.0    # g/day
    adult_beef_g_day: float = 50.0    # g/day
    reference_dose: float = 0.1       # ng/kg-bw/day
    background_exposure: float = 0.0  # ng/kg-bw/day


def simulate_model(params: ModelParams) -> pd.DataFrame:
    """Daily Euler implementation of the simplified one-compartment TK model.

    This follows the R model structure:
    dAC = Dose - AC * (log(2) / DT50i)
    Serum = AC / Vd
    Muscle = Serum * PM
    Liver = Serum * PL
    Kidney = Serum * PK
    """
    days = np.arange(0, params.harvest_day + 1, 1)
    ac = np.zeros_like(days, dtype=float)
    ac[0] = params.initial_body_burden

    rows = []
    for i, day in enumerate(days):
        # Time-dependent cattle growth and intake
        bw = params.MW - params.MW * 0.9 * math.exp(-(params.Cgr * day) / (params.MW ** params.Cgrs))
        z = bw / params.MW
        dmi = params.Crs * params.MW * z * (params.Cq - z) * (
            params.Crc * (params.Cbc - params.Crc) / (params.Cbc - 1)
        ) * 1000.0  # g/day
        soil_ingestion = 0.1 * dmi  # g/day, simplified assumption
        dt50_i = params.DT50 * (bw / params.MW) ** 0.25
        vd = params.Vd_coeff * bw
        dose = (
            dmi * params.stover_conc * params.B_feed
            + soil_ingestion * params.soil_conc * params.B_soil
        ) / 1000.0  # ng/day, following the original R scaling

        serum = ac[i] / vd if vd > 0 else np.nan
        muscle = serum * params.PM
        liver = serum * params.PL
        kidney = serum * params.PK
        elimination = ac[i] * (math.log(2) / dt50_i)

        rows.append(
            {
                "Day": day,
                "Body weight (kg)": bw,
                "DMI (g/day)": dmi,
                "Soil ingestion (g/day)": soil_ingestion,
                "Daily absorbed dose (ng/day)": dose,
                "Body burden AC (ng)": ac[i],
                "Serum (ng/g or ug/L approx.)": serum,
                "Muscle (ng/g)": muscle,
                "Liver (ng/g)": liver,
                "Kidney (ng/g)": kidney,
                "Elimination (ng/day)": elimination,
                "DT50 adjusted (days)": dt50_i,
            }
        )

        if i < len(days) - 1:
            d_ac = dose - elimination
            ac[i + 1] = max(ac[i] + d_ac, 0.0)

    return pd.DataFrame(rows)


def estimate_human_exposure(muscle_ng_g: float, hp: HumanExposureParams) -> pd.DataFrame:
    child_dose = muscle_ng_g * hp.child_beef_g_day / hp.child_bw + hp.background_exposure
    adult_dose = muscle_ng_g * hp.adult_beef_g_day / hp.adult_bw + hp.background_exposure
    return pd.DataFrame(
        {
            "Population": ["Child", "Adult"],
            "Body weight (kg)": [hp.child_bw, hp.adult_bw],
            "Beef intake (g/day)": [hp.child_beef_g_day, hp.adult_beef_g_day],
            "Estimated exposure (ng/kg-bw/day)": [child_dose, adult_dose],
            "Reference dose (ng/kg-bw/day)": [hp.reference_dose, hp.reference_dose],
            "Hazard quotient": [child_dose / hp.reference_dose if hp.reference_dose > 0 else np.nan,
                                  adult_dose / hp.reference_dose if hp.reference_dose > 0 else np.nan],
        }
    )


def run_scenario_table(base_params: ModelParams, hp: HumanExposureParams, stover_values: list[float]) -> pd.DataFrame:
    out = []
    for value in stover_values:
        scenario_params = ModelParams(**{**base_params.__dict__, "stover_conc": value})
        df = simulate_model(scenario_params)
        harvest = df.loc[df["Day"] == scenario_params.harvest_day].iloc[0]
        human = estimate_human_exposure(harvest["Muscle (ng/g)"], hp)
        out.append(
            {
                "Stover PFOS (ng/g)": value,
                "Harvest muscle PFOS (ng/g)": harvest["Muscle (ng/g)"],
                "Child exposure (ng/kg-bw/day)": human.loc[human["Population"] == "Child", "Estimated exposure (ng/kg-bw/day)"].iloc[0],
                "Adult exposure (ng/kg-bw/day)": human.loc[human["Population"] == "Adult", "Estimated exposure (ng/kg-bw/day)"].iloc[0],
                "Child HQ": human.loc[human["Population"] == "Child", "Hazard quotient"].iloc[0],
                "Adult HQ": human.loc[human["Population"] == "Adult", "Hazard quotient"].iloc[0],
            }
        )
    return pd.DataFrame(out)


st.title("PFAS Soil–Crop–Cattle–Human Exposure Model")
st.caption(
    "Interactive screening-level model based on the simplified cattle PFOS toxicokinetic framework. "
    "Default values are literature/model defaults and can be changed by the user."
)

with st.sidebar:
    st.header("Scenario Inputs")

    st.subheader("Environmental concentrations")
    soil_conc = st.number_input("Soil PFOS concentration (ng/g)", min_value=0.0, value=98.57, step=1.0)
    stover_conc = st.number_input("Corn stover PFOS concentration (ng/g)", min_value=0.0, value=12.30, step=0.5)

    st.subheader("Bioavailability")
    B_feed = st.slider("Feed bioavailability", 0.0, 1.0, 0.75, 0.05)
    B_soil = st.slider("Soil bioavailability", 0.0, 1.0, 0.20, 0.05)

    st.subheader("Cattle TK parameters")
    harvest_day = st.slider("Harvest age / simulation duration (days)", 30, 1095, 730, 1)
    DT50 = st.number_input("PFOS half-life DT50 (days)", min_value=1.0, value=74.1, step=1.0)
    PM = st.number_input("Muscle partition coefficient", min_value=0.0, value=0.08, step=0.01)
    initial_body_burden = st.number_input("Initial body burden AC (ng)", min_value=0.0, value=0.0, step=10.0)

    with st.expander("Advanced cattle growth/intake parameters"):
        MW = st.number_input("Mature body weight MW (kg)", min_value=100.0, value=640.0, step=10.0)
        Cgr = st.number_input("Growth rate constant Cgr", min_value=0.0001, value=0.0115, step=0.0005, format="%.4f")
        Crs = st.number_input("Relative size scalar Crs", min_value=0.001, value=0.025, step=0.001, format="%.3f")
        soil_ingestion_note = "Soil ingestion is fixed at 10% of DMI in this simplified version."
        st.info(soil_ingestion_note)

    st.subheader("Human exposure assumptions")
    child_bw = st.number_input("Child body weight (kg)", min_value=1.0, value=15.0, step=1.0)
    adult_bw = st.number_input("Adult body weight (kg)", min_value=20.0, value=80.0, step=1.0)
    child_beef = st.number_input("Child beef intake (g/day)", min_value=0.0, value=30.0, step=5.0)
    adult_beef = st.number_input("Adult beef intake (g/day)", min_value=0.0, value=50.0, step=5.0)
    reference_dose = st.number_input("Reference dose / target level (ng/kg-bw/day)", min_value=0.0001, value=0.1, step=0.01, format="%.4f")
    background_exposure = st.number_input("Background PFOS exposure (ng/kg-bw/day)", min_value=0.0, value=0.0, step=0.01)

params = ModelParams(
    soil_conc=soil_conc,
    stover_conc=stover_conc,
    B_feed=B_feed,
    B_soil=B_soil,
    DT50=DT50,
    PM=PM,
    MW=MW,
    Cgr=Cgr,
    Crs=Crs,
    harvest_day=harvest_day,
    initial_body_burden=initial_body_burden,
)

human_params = HumanExposureParams(
    child_bw=child_bw,
    adult_bw=adult_bw,
    child_beef_g_day=child_beef,
    adult_beef_g_day=adult_beef,
    reference_dose=reference_dose,
    background_exposure=background_exposure,
)

results = simulate_model(params)
harvest_row = results.loc[results["Day"] == harvest_day].iloc[0]
human_exposure = estimate_human_exposure(harvest_row["Muscle (ng/g)"], human_params)

col1, col2, col3, col4 = st.columns(4)
col1.metric("Harvest muscle PFOS", f"{harvest_row['Muscle (ng/g)']:.3f} ng/g")
col2.metric("Harvest serum PFOS", f"{harvest_row['Serum (ng/g or ug/L approx.)']:.1f}")
col3.metric("Child exposure", f"{human_exposure.loc[0, 'Estimated exposure (ng/kg-bw/day)']:.3f}")
col4.metric("Adult exposure", f"{human_exposure.loc[1, 'Estimated exposure (ng/kg-bw/day)']:.3f}")

st.divider()

left, right = st.columns([2, 1])
with left:
    st.subheader("Predicted PFOS concentrations over time")
    plot_df = results.melt(
        id_vars="Day",
        value_vars=["Serum (ng/g or ug/L approx.)", "Muscle (ng/g)", "Liver (ng/g)", "Kidney (ng/g)"],
        var_name="Matrix",
        value_name="Concentration",
    )
    fig = px.line(plot_df, x="Day", y="Concentration", color="Matrix", log_y=True)
    fig.update_layout(height=500, yaxis_title="PFOS concentration, log scale")
    st.plotly_chart(fig, use_container_width=True)

with right:
    st.subheader("Human dietary exposure")
    fig2 = px.bar(
        human_exposure,
        x="Population",
        y="Estimated exposure (ng/kg-bw/day)",
        text="Estimated exposure (ng/kg-bw/day)",
    )
    fig2.add_hline(
    y=reference_dose,
    line_dash="dash",
    annotation_text=f"Reference dose: {reference_dose:.3f} ng/kg-bw/day",
    annotation_position="top left"
    )
    fig2.update_traces(texttemplate="%{text:.3f}", textposition="outside")
    fig2.update_layout(height=500)
    st.plotly_chart(fig2, use_container_width=True)

st.subheader("Exposure and risk summary")
st.dataframe(human_exposure, use_container_width=True)

st.subheader("Scenario analysis: stover concentration range")
default_values = "0.6254, 10.2513, 16.2794, 31.8578, 50.7431, 60.8177"
stover_text = st.text_input("Enter stover PFOS concentrations separated by commas", default_values)
try:
    stover_values = [float(x.strip()) for x in stover_text.split(",") if x.strip()]
except ValueError:
    st.error("Please enter numeric values separated by commas.")
    stover_values = []

if stover_values:
    scenario_df = run_scenario_table(params, human_params, stover_values)
    st.dataframe(scenario_df, use_container_width=True)
    fig3 = px.line(
        scenario_df,
        x="Stover PFOS (ng/g)",
        y=["Child exposure (ng/kg-bw/day)", "Adult exposure (ng/kg-bw/day)"],
        markers=True,
    )
    fig3.add_hline(
    y=reference_dose,
    line_dash="dash",
    annotation_text=f"Reference dose = {reference_dose:.3f} ng/kg-bw/day",
    annotation_position="top left"
    )
    fig3.update_layout(yaxis_title="Exposure (ng/kg-bw/day)", height=450)
    st.plotly_chart(fig3, use_container_width=True)

st.subheader("Download model output")
col_a, col_b = st.columns(2)
with col_a:
    st.download_button(
        "Download daily cattle TK results as CSV",
        data=results.to_csv(index=False),
        file_name="daily_cattle_tk_results.csv",
        mime="text/csv",
    )
with col_b:
    st.download_button(
        "Download human exposure summary as CSV",
        data=human_exposure.to_csv(index=False),
        file_name="human_exposure_summary.csv",
        mime="text/csv",
    )

with st.expander("Model equations and assumptions"):
    st.markdown(
        """
        **Cattle growth**  
        `BW = MW - MW × 0.9 × exp(-(Cgr × Day) / MW^Cgrs)`

        **Dry matter intake**  
        `DMI = Crs × MW × Z × (Cq - Z) × body condition term × 1000`, where `Z = BW / MW`.

        **Soil ingestion**  
        `SI = 0.1 × DMI`

        **Daily absorbed dose**  
        `Dose = (DMI × stover concentration × feed bioavailability + SI × soil concentration × soil bioavailability) / 1000`

        **One-compartment TK model**  
        `dAC = Dose - AC × log(2) / DT50_adjusted`

        **Tissue concentrations**  
        `Serum = AC / Vd`; `Muscle = Serum × PM`; `Liver = Serum × PL`; `Kidney = Serum × PK`.

        This is a screening-level implementation of the simplified model. It does not include drinking water exposure, milk intake, maternal transfer, stochastic population variability, or multi-compartment tissue kinetics.
        """
    )
