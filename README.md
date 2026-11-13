# Student Grade Predictor (Linear Regression Summative)

## 1. Mission and problem

**Mission:** to develop and implement innovative educational technologies that bridge the gap in access to quality education for young people in South Sudan and beyond.
**Problem:** students who struggle are often noticed only after they fail or drop out. This project predicts a university student's **second-semester average grade (0-20)** from information known at the end of semester 1, so advisors, student-support teams and scholarship officers can help at-risk students early.

## 2. Dataset

**Predict Students' Dropout and Academic Success** (Realinho et al., 2021/2022), UCI Machine Learning Repository, licence CC BY 4.0.

- Source: <https://archive.ics.uci.edu/dataset/697>
- Kaggle copy: <https://www.kaggle.com/datasets/thedevastator/higher-education-predictors-of-student-retention>
- 4,424 students from a higher-education institution, 34 features (demographic, socio-economic, financial and semester 1/2 academic records) and a `Target` label (Dropout / Enrolled / Graduate). There are no missing values and no duplicates.
- The original task is classification. I reframed it as **regression** on `Curricular units 2nd sem (grade)`, using 13 features known at the end of semester 1. The 180 students not enrolled in semester 2 were removed, which left 4,244 rows.

## 3. API (Swagger UI)

Public endpoint documentation: **<https://student-grade-predictor.onrender.com/docs>**

| Method | Route      | Purpose                                                        |
| ------ | ---------- | -------------------------------------------------------------- |
| POST   | `/predict` | Predicted semester 2 grade, risk level (High / Medium / Low) and a message |
| POST   | `/retrain` | Upload a CSV of new students to update the model               |

> The free Render plan sleeps after 15 minutes without traffic, so the first request can take up to a minute.

## 4. Video demo

YouTube: **<https://youtu.be/REPLACE_WITH_YOUR_VIDEO_ID>**

## 5. How to run the mobile app

1. Install [Flutter](https://docs.flutter.dev/get-started/install) and Android Studio, then create and start an Android emulator (or connect an Android phone with USB debugging on).
2. Clone this repository:
   ```bash
   git clone https://github.com/solomon-211/Liner_regression_model_project.git
   cd Liner_regression_model_project/summative/FlutterApp
   ```
3. Install the dependencies:
   ```bash
   flutter pub get
   ```
4. Run the app:
   ```bash
   flutter run
   ```
5. Fill in all 13 fields (each field shows its allowed values) and press **Predict**. The predicted grade and risk level appear at the bottom of the page.

---

## Repository structure

```
Liner_regression_model_project/
├── README.md
└── summative/
    ├── linear_regression/
    │   ├── multivariate.ipynb    # EDA, feature engineering, model training and comparison
    │   └── dataset.csv
    ├── API/
    │   ├── prediction.py         # FastAPI app (/predict, /retrain)
    │   ├── requirements.txt
    │   └── best_model.pkl        # preprocessing + best model pipeline
    └── FlutterApp/               # one-page Flutter app
```

## Model results (test set, MSE)

| Model                 | Train MSE | Test MSE |
| --------------------- | --------: | -------: |
| **Random forest**     | 4.06      | **6.76** |
| Decision tree         | 6.45      | 6.79     |
| SGD regressor         | 6.96      | 7.10     |
| Linear regression     | 6.95      | 7.12     |

The random forest has the lowest test MSE (RMSE of about 2.6 grade points), so it is the model saved and served by the API.

## Run the API locally

```bash
cd summative
uv sync
cd API
uv run uvicorn prediction:app --reload
```

Then open <http://127.0.0.1:8000/docs>.

## Render deployment settings

| Setting        | Value                                                   |
| -------------- | ------------------------------------------------------- |
| Root directory | `summative/API`                                         |
| Runtime        | Python 3                                                |
| Build command  | `pip install -r requirements.txt`                       |
| Start command  | `uvicorn prediction:app --host 0.0.0.0 --port $PORT`    |
| Env variable   | `PYTHON_VERSION=3.13.x`                                 |
