# PFAS Soil–Crop–Cattle–Human Exposure Model

This is a Streamlit web app converted from the simplified R model `Mikkonnen Model 0204.R`.

## What the app does

The app estimates PFOS transfer through a simplified soil–crop–cattle–human pathway:

1. Soil and corn stover PFOS concentrations are entered by the user.
2. Cattle dry matter intake and soil ingestion are estimated from body weight growth.
3. A one-compartment toxicokinetic model predicts PFOS in serum, muscle, liver, and kidney.
4. Harvest muscle PFOS is combined with child and adult beef consumption rates to estimate dietary exposure.
5. Exposure is compared with a user-defined reference dose.

## Local preview

```bash
pip install -r requirements.txt
streamlit run streamlit_app.py
```

## Streamlit Community Cloud deployment

1. Create a GitHub repository.
2. Upload `streamlit_app.py`, `requirements.txt`, and this `README.md`.
3. Go to Streamlit Community Cloud.
4. Select the repository and set the main file path to:

```text
streamlit_app.py
```

5. Deploy.

## Important simplifications

This app follows the simplified model structure. It does not include:

- Drinking water exposure
- Milk exposure or lactation
- Maternal/placental transfer
- Stochastic population variability
- Multi-compartment tissue kinetics
- Multiple PFAS mixture modeling

These features can be added later if needed.
