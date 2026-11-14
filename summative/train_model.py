"""Recreate API/best_model.pkl and API/training_data.csv (same model as multivariate.ipynb).

Run from the summative/ folder:  uv run python train_model.py
"""
import os

import joblib
import pandas as pd
from sklearn.compose import ColumnTransformer
from sklearn.ensemble import RandomForestRegressor
from sklearn.metrics import mean_squared_error
from sklearn.model_selection import train_test_split
from sklearn.pipeline import Pipeline
from sklearn.preprocessing import OneHotEncoder, StandardScaler

SEED = 42
RENAME = {
    "Course": "course",
    "Daytime/evening attendance": "daytime_attendance",
    "Gender": "gender",
    "Scholarship holder": "scholarship_holder",
    "Debtor": "debtor",
    "Tuition fees up to date": "tuition_fees_up_to_date",
    "Displaced": "displaced",
    "Age at enrollment": "age_at_enrollment",
    "Curricular units 1st sem (enrolled)": "sem1_units_enrolled",
    "Curricular units 1st sem (evaluations)": "sem1_units_evaluations",
    "Curricular units 1st sem (approved)": "sem1_units_approved",
    "Curricular units 1st sem (grade)": "sem1_grade",
    "Curricular units 2nd sem (enrolled)": "sem2_units_enrolled",
    "Curricular units 2nd sem (grade)": "sem2_grade",
}
CATEGORICAL = ["course"]
BINARY = ["daytime_attendance", "gender", "scholarship_holder", "debtor", "tuition_fees_up_to_date", "displaced"]
NUMERIC = ["age_at_enrollment", "sem1_units_enrolled", "sem1_units_evaluations",
           "sem1_units_approved", "sem1_grade", "sem2_units_enrolled"]
FEATURES = CATEGORICAL + BINARY + NUMERIC
TARGET = "sem2_grade"

df = pd.read_csv("linear_regression/dataset.csv").rename(columns=RENAME)
df = df[df["sem2_units_enrolled"] > 0].reset_index(drop=True)  # no semester-2 units = no real grade

X_train, X_test, y_train, y_test = train_test_split(df[FEATURES], df[TARGET], test_size=0.2, random_state=SEED)

# Step names "preprocess" and "model" are looked up by the API's /retrain endpoint.
model = Pipeline([
    ("preprocess", ColumnTransformer([
        ("course", OneHotEncoder(handle_unknown="ignore", sparse_output=False), CATEGORICAL),
        ("scale", StandardScaler(), BINARY + NUMERIC),
    ])),
    ("model", RandomForestRegressor(n_estimators=300, min_samples_leaf=5, random_state=SEED, n_jobs=-1)),
])
model.fit(X_train, y_train)
print(f"test MSE: {mean_squared_error(y_test, model.predict(X_test)):.3f}")

os.makedirs("API", exist_ok=True)
joblib.dump(model, "API/best_model.pkl")
df[FEATURES + [TARGET]].to_csv("API/training_data.csv", index=False)
print("saved API/best_model.pkl and API/training_data.csv")
