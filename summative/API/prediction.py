"""FastAPI service that predicts a student's second-semester average grade (0-20).

Run locally with: uvicorn prediction:app --reload
"""

import io
import os
import threading
from contextlib import asynccontextmanager
from pathlib import Path

import joblib
import numpy as np
import pandas as pd
from fastapi import FastAPI, File, HTTPException, UploadFile
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import RedirectResponse
from pydantic import BaseModel, ConfigDict, Field, ValidationError, model_validator
from sklearn.base import clone
from sklearn.linear_model import SGDRegressor
from sklearn.metrics import mean_squared_error

BASE_DIR = Path(__file__).resolve().parent
MODEL_PATH = BASE_DIR / "best_model.pkl"
DATA_PATH = BASE_DIR / "training_data.csv"

FEATURES = [
    "course", "daytime_attendance", "gender", "scholarship_holder", "debtor",
    "tuition_fees_up_to_date", "displaced", "age_at_enrollment",
    "sem1_units_enrolled", "sem1_units_evaluations", "sem1_units_approved",
    "sem1_grade", "sem2_units_enrolled",
]
TARGET = "sem2_grade"

# /retrain also accepts CSVs that use the original UCI/Kaggle column names.
ORIGINAL_COLUMN_NAMES = {
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

EXAMPLE_STUDENT = {
    "course": 14, "daytime_attendance": 1, "gender": 0, "scholarship_holder": 0,
    "debtor": 0, "tuition_fees_up_to_date": 1, "displaced": 1, "age_at_enrollment": 20,
    "sem1_units_enrolled": 6, "sem1_units_evaluations": 9, "sem1_units_approved": 6,
    "sem1_grade": 13.29, "sem2_units_enrolled": 6,
}

SGD_RETRAIN_EPOCHS = 20
MAX_REPORTED_ERRORS = 10


# --- Schemas ---------------------------------------------------------------

class StudentInput(BaseModel):
    """A student's record at the end of semester 1."""

    # strict: "12" is not silently accepted as 12; forbid: unknown fields are rejected.
    model_config = ConfigDict(strict=True, extra="forbid", json_schema_extra={"example": EXAMPLE_STUDENT})

    course: int = Field(ge=1, le=17, description="Degree programme code, 1-17")
    daytime_attendance: int = Field(ge=0, le=1, description="1 = daytime classes, 0 = evening classes")
    gender: int = Field(ge=0, le=1, description="1 = male, 0 = female")
    scholarship_holder: int = Field(ge=0, le=1, description="1 = has a scholarship, 0 = no")
    debtor: int = Field(ge=0, le=1, description="1 = owes the university money, 0 = no")
    tuition_fees_up_to_date: int = Field(ge=0, le=1, description="1 = fees paid up to date, 0 = no")
    displaced: int = Field(ge=0, le=1, description="1 = studying away from home, 0 = no")
    age_at_enrollment: int = Field(ge=15, le=80, description="Age when the student enrolled (years)")
    sem1_units_enrolled: int = Field(ge=0, le=30, description="Units enrolled in semester 1")
    sem1_units_evaluations: int = Field(ge=0, le=50, description="Number of assessments taken in semester 1")
    sem1_units_approved: int = Field(ge=0, le=30, description="Units passed in semester 1")
    sem1_grade: float = Field(ge=0, le=20, description="Average semester-1 grade, 0-20 (0 if no unit was passed)")
    sem2_units_enrolled: int = Field(ge=1, le=30, description="Units enrolled in semester 2 (at least 1)")

    @model_validator(mode="after")
    def check_consistency(self) -> "StudentInput":
        if self.sem1_units_approved > self.sem1_units_enrolled:
            raise ValueError("sem1_units_approved cannot be greater than sem1_units_enrolled")
        if self.sem1_units_approved == 0 and self.sem1_grade != 0:
            raise ValueError("sem1_grade must be 0 when no semester-1 unit was approved")
        if self.sem1_units_approved > 0 and self.sem1_grade < 10:
            raise ValueError("sem1_grade must be between 10 and 20 when at least one unit was approved (pass mark is 10)")
        return self


class PredictionOutput(BaseModel):
    predicted_sem2_grade: float = Field(description="Predicted 2nd-semester average grade (0-20)")
    risk_level: str = Field(description="High, Medium or Low risk of failing the 2nd semester")
    message: str


class RetrainOutput(BaseModel):
    message: str
    method: str
    rows_received: int
    rows_used: int
    total_training_rows: int
    mse_on_new_rows_before: float
    mse_on_new_rows_after: float


# --- Model store -----------------------------------------------------------

class ModelStore:
    """Keeps the current model and its training data in memory."""

    def __init__(self, model_path: Path, data_path: Path):
        self.model_path = model_path
        self.data_path = data_path
        self.model = None
        self.data = None
        self._lock = threading.Lock()

    def load(self) -> None:
        self.model = joblib.load(self.model_path)
        self.data = pd.read_csv(self.data_path)

    def predict_one(self, student: StudentInput) -> float:
        row = pd.DataFrame([student.model_dump()])[FEATURES]
        with self._lock:
            return float(self.model.predict(row)[0])

    def retrain(self, new_rows: pd.DataFrame) -> tuple[str, float, float, int]:
        """Update the model with new rows. Returns (method, mse_before, mse_after, total_rows)."""
        X_new, y_new = new_rows[FEATURES], new_rows[TARGET]

        with self._lock:
            mse_before = mean_squared_error(y_new, self.model.predict(X_new))
            combined = pd.concat([self.data, new_rows], ignore_index=True)

            if isinstance(self.model.named_steps["model"], SGDRegressor):
                updated = self._continue_training(X_new, y_new)
                method = "SGDRegressor: continued training on the new rows with partial_fit"
            else:
                updated = clone(self.model).fit(combined[FEATURES], combined[TARGET])
                method = f"{type(self.model.named_steps['model']).__name__}: refit on original data + new rows"

            mse_after = mean_squared_error(y_new, updated.predict(X_new))
            self.model, self.data = updated, combined
            self._save()

        return method, mse_before, mse_after, len(combined)

    def _continue_training(self, X: pd.DataFrame, y: pd.Series):
        X_transformed = self.model.named_steps["preprocess"].transform(X)
        for _ in range(SGD_RETRAIN_EPOCHS):
            self.model.named_steps["model"].partial_fit(X_transformed, y)
        return self.model

    def _save(self) -> None:
        try:
            joblib.dump(self.model, self.model_path)
            self.data.to_csv(self.data_path, index=False)
        except OSError:
            pass  # On a read-only disk the in-memory model is still updated.


store = ModelStore(MODEL_PATH, DATA_PATH)


# --- Helpers ---------------------------------------------------------------

def risk_level(grade: float) -> tuple[str, str]:
    if grade < 8:
        return "High", "Likely to fail most 2nd-semester units. Recommend immediate academic and financial support."
    if grade < 11:
        return "Medium", "Close to the pass mark (10). Recommend tutoring or mentoring check-ins."
    return "Low", "On track to pass the 2nd semester."


def to_python_number(value):
    """Convert numpy numbers to Python numbers; whole floats from a CSV (e.g. 6.0) become int."""
    if isinstance(value, np.integer):
        return int(value)
    if isinstance(value, (float, np.floating)):
        return int(value) if float(value).is_integer() else float(value)
    return value


def read_csv_upload(content: bytes) -> pd.DataFrame:
    try:
        return pd.read_csv(io.BytesIO(content))
    except Exception:
        raise HTTPException(status_code=400, detail="Could not read the file as CSV.")


def clean_training_rows(df: pd.DataFrame) -> pd.DataFrame:
    """Rename columns, check they are all present and apply the same cleaning as the notebook."""
    df = df.rename(columns=ORIGINAL_COLUMN_NAMES)
    missing = [col for col in FEATURES + [TARGET] if col not in df.columns]
    if missing:
        raise HTTPException(status_code=422, detail=f"CSV is missing required columns: {missing}")

    df = df[FEATURES + [TARGET]].dropna()
    return df[df["sem2_units_enrolled"] > 0]


def find_invalid_rows(df: pd.DataFrame) -> list[str]:
    """Check every row with the same rules as /predict. Line numbers match the CSV file."""
    errors = []
    for line, record in zip(df.index + 2, df.to_dict("records")):
        try:
            StudentInput.model_validate({col: to_python_number(record[col]) for col in FEATURES}, strict=False)
        except ValidationError as exc:
            err = exc.errors()[0]
            field = ".".join(str(part) for part in err["loc"]) or "row"
            errors.append(f"line {line}: {field}: {err['msg']}")
            continue
        if not 0 <= record[TARGET] <= 20:
            errors.append(f"line {line}: sem2_grade must be between 0 and 20")
    return errors


# --- App -------------------------------------------------------------------

@asynccontextmanager
async def lifespan(app: FastAPI):
    store.load()
    yield


app = FastAPI(
    title="Student Second-Semester Grade Predictor",
    description=(
        "Predicts a university student's 2nd-semester average grade (0-20) from information known at the end "
        "of semester 1, so student-support teams can step in early. Model: random forest trained on the "
        "'Predict Students' Dropout and Academic Success' dataset (UCI, CC BY 4.0)."
    ),
    version="1.0.0",
    lifespan=lifespan,
)

# CORS: only the deployed site (for Swagger UI) and local Flutter web debugging may call the API
# from a browser. No wildcard, so other websites cannot use the model or upload files to /retrain.
# Only GET/POST and the Content-Type/Accept headers are needed, and there are no cookies or logins,
# so credentials are disabled. More origins can be added with the ALLOWED_ORIGINS env variable.
# The mobile app is not a browser, so CORS does not affect it.
DEFAULT_ORIGINS = [
    "https://student-grade-predictor.onrender.com",
    "http://localhost:5000",
    "http://127.0.0.1:5000",
]
extra_origins = [origin.strip() for origin in os.getenv("ALLOWED_ORIGINS", "").split(",") if origin.strip()]

app.add_middleware(
    CORSMiddleware,
    allow_origins=DEFAULT_ORIGINS + extra_origins,
    allow_methods=["GET", "POST"],
    allow_headers=["Content-Type", "Accept"],
    allow_credentials=False,
)


@app.get("/", include_in_schema=False)
def root():
    return RedirectResponse(url="/docs")


@app.post("/predict", response_model=PredictionOutput)
def predict(student: StudentInput):
    grade = round(min(max(store.predict_one(student), 0.0), 20.0), 2)
    level, message = risk_level(grade)
    return PredictionOutput(predicted_sem2_grade=grade, risk_level=level, message=message)


@app.post("/retrain", response_model=RetrainOutput)
async def retrain(
    file: UploadFile = File(
        description="CSV with the 13 features + sem2_grade. Original dataset column names are also accepted."
    ),
):
    if not (file.filename or "").lower().endswith(".csv"):
        raise HTTPException(status_code=400, detail="Please upload a .csv file.")

    raw = read_csv_upload(await file.read())
    rows = clean_training_rows(raw)

    errors = find_invalid_rows(rows)
    if errors:
        raise HTTPException(
            status_code=422,
            detail={"message": f"{len(errors)} invalid row(s)", "errors": errors[:MAX_REPORTED_ERRORS]},
        )
    if rows.empty:
        raise HTTPException(status_code=422, detail="No usable rows in the CSV.")

    method, mse_before, mse_after, total_rows = store.retrain(rows)

    return RetrainOutput(
        message="Model retrained. /predict now uses the updated model.",
        method=method,
        rows_received=len(raw),
        rows_used=len(rows),
        total_training_rows=total_rows,
        mse_on_new_rows_before=round(mse_before, 4),
        mse_on_new_rows_after=round(mse_after, 4),
    )
