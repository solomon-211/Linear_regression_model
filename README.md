# Village Learning Predictor (Uganda)

**Mission:** To develop and implement innovative educational technologies that bridge the gap in access to quality education for young people in South Sudan and beyond.
**Problem:** Many children in East Africa attend school for years without learning to read a short story or do simple subtraction, and results differ sharply between villages.
This project predicts the average reading-and-maths score (0–10) of the children in a Ugandan village from 12 community characteristics, so that district education officers
and NGOs can decide which villages to send teachers, books and tutoring to first.

## Dataset

**Uwezo Uganda 2015 learning assessment** (Twaweza East Africa), downloaded from the Humanitarian Data Exchange: https://data.humdata.org/dataset/learning-levels-in-uganda-2015

- **Raw file:** `ug15_hhld.csv`, 164,129 child records (one row per child aged 6–16) from all four regions of Uganda, with the child's English and maths test levels plus household and schooling information. It is 116 MB, above GitHub's 100 MB file limit, so it is not in this repository. Download it from the link above to rebuild the dataset.
- **Modelling file:** `summative/linear_regression/uganda_village_learning.csv`, created from the raw file by `build_village_dataset.py`: 3,219 villages × 20 columns, keeping only villages with at least 10 tested children. Running the script on the raw file reproduces this CSV exactly.
- **Target:** `avg_learning_score`, the village average of each child's English level (0 = non-reader … 4 = story) plus maths level (0 = non-numerate … 6 = division). One child's score is a whole number, but the village average is continuous (702 distinct values between 0 and 10, e.g. 4.54, 7.30), so this is a regression task.
- **Features used (12):** region and area (rural/urban); % of mothers with secondary education; % of children in private school, with paid extra tuition, and who attended preschool; % of households with electricity, a mobile phone, a toilet, and three meals a day; average household size; average age of tested children.
- **Why Ugandan data for a South Sudan mission:** Uwezo publishes child-level learning results together with household details, which is what this model needs. The same pipeline can be retrained on South Sudanese data through the `/retrain` endpoint once a comparable survey is available.

## API (Swagger UI)

**https://uganda-learning-predictor.onrender.com/docs**

| Route | Purpose |
|---|---|
| `POST /predict` | Takes the 12 inputs as JSON and returns the predicted score (0–10), a support priority and a short message |
| `POST /retrain` | Takes a CSV of new villages (the 12 inputs + `avg_learning_score`), refits the model on the original data plus the new rows, and uses it immediately |

The free Render plan sleeps after 15 minutes without requests, so the first call can take up to a minute.

## Video Demo

**YouTube:** https://youtu.be/REPLACE_WITH_YOUR_VIDEO_ID

## Running the Mobile App

1. Install Flutter (https://docs.flutter.dev/get-started/install) and check it with `flutter doctor`.
2. Start an Android emulator (Android Studio → Device Manager → ▶) or connect an Android phone with USB debugging on.
3. Clone the repository and open the app folder:
   ```bash
   git clone https://github.com/solomon-211/Liner_regression_model_project.git
   cd Liner_regression_model_project/summative/FlutterApp
   ```
4. Install the dependencies:
   ```bash
   flutter pub get
   ```
5. Run the app:
   ```bash
   flutter devices          # shows the device ID
   flutter run -d <device-id>
   ```
6. Fill in all 12 fields, or tap **Fill example**, then press **Predict**. The example village (Central, Rural, mothers with secondary education 27.8, private school 0, paid tuition 0, preschool 4.3, electricity 22.2, phone 44.4, toilet 66.7, three meals 33.3, household size 4.78, child age 10.11) returns **4.88 / 10, Medium priority**.

The Android folder is included. To run on iOS (macOS only), first run `flutter create . --project-name uganda_learning_predictor --platforms=ios` in the app folder. If the API is deployed under a different URL, change `apiUrl` at the top of `lib/main.dart`.

---

## Repository Structure

```
linear_regression_model/
├── README.md
└── summative/
    ├── pyproject.toml, uv.lock          # uv project (Python 3.13)
    ├── linear_regression/
    │   ├── multivariate.ipynb           # analysis, training, comparison, model export
    │   ├── uganda_village_learning.csv  # village-level dataset (3,219 rows)
    │   └── build_village_dataset.py     # builds the CSV above from ug15_hhld.csv
    ├── API/
    │   ├── prediction.py                # FastAPI app: /predict, /retrain, /docs
    │   ├── requirements.txt             # exported from uv.lock, used by Render
    │   ├── best_model.pkl               # preprocessing + LinearRegression pipeline
    │   └── training_data.csv            # the 12 features + target, used by /retrain
    └── FlutterApp/                      # one-page Flutter app
```

## Method

- **Split:** 80% train / 20% test (`random_state=42`). Hyperparameters were tuned on a validation set taken from the training data, so the test set was used only for the final comparison.
- **Preprocessing** (in a scikit-learn `Pipeline`, fitted on the training set only): one-hot encoding of `region` and `area`; median imputation for the 14 missing values (13 villages with no enrolled tested children have no `pct_private_school`, 1 village has no `avg_household_size`); standard scaling of the 10 numeric features.
- **Gradient descent:** `SGDRegressor` trained one epoch at a time with `partial_fit`. Grid of learning rate × regularisation × epochs; the best setting was `eta0=0.01`, `alpha=0.0001`, 50 epochs. Loss went from 28.27 (untrained) to 1.234 train / 1.151 test.
- **Other models:** closed-form `LinearRegression`, `DecisionTreeRegressor` (depth tuned, best = 6), `RandomForestRegressor` (300 trees, `min_samples_leaf` tuned, best = 10).

## Results (test set, 644 villages)

| Model | Train MSE | Test MSE |
|---|---|---|
| **Linear regression, closed form** | 1.233 | **1.149** |
| Linear regression, gradient descent (SGDRegressor) | 1.234 | 1.152 |
| Random forest | 0.810 | 1.170 |
| Decision tree | 1.212 | 1.597 |
| Baseline: always predict the training mean | – | 2.424 |

Closed-form linear regression has the lowest test MSE (RMSE ≈ 1.07 points on the 0–10 scale), less than half the baseline error, so it is the model saved in `best_model.pkl`. The random forest fits the training data much more closely (0.810) but does worse on the test set, a sign of overfitting.

**Limitations:** the score is not adjusted for age, so villages whose tested children are older score higher; predictions describe villages, not individual children; and teaching quality and school resources are not in the data.

## API Details

**Input rules** (Pydantic, strict types, unknown fields rejected; invalid input returns HTTP 422 with the reason):

| Field | Type | Allowed values |
|---|---|---|
| `region` | text | `Central`, `Eastern`, `North`, `Western` |
| `area` | text | `Rural`, `Urban` |
| 8 `pct_*` fields | number | 0 to 100 |
| `avg_household_size` | number | 1 to 20 |
| `avg_child_age` | number | 6 to 16 |

**Support priority:** High if the score is below 4, Medium from 4 to below 6, Low from 6.

**Example request and response:**
```json
{"region": "Central", "area": "Rural", "pct_mother_secondary": 27.8, "pct_private_school": 0.0,
 "pct_paid_tuition": 0.0, "pct_preschool": 4.3, "pct_electricity": 22.2, "pct_phone": 44.4,
 "pct_toilet": 66.7, "pct_three_meals": 33.3, "avg_household_size": 4.78, "avg_child_age": 10.11}
```
```json
{"predicted_learning_score": 4.88, "support_priority": "Medium",
 "message": "Children are likely to read words or a paragraph and add or subtract. Targeted support is recommended."}
```

**CORS:** only the Render URL and local Flutter web debugging (`localhost:5000`, `127.0.0.1:5000`) are allowed as browser origins; only `GET` and `POST`; only the `Content-Type` and `Accept` headers; no credentials. More origins can be added with the `ALLOWED_ORIGINS` environment variable. The mobile app is not a browser, so CORS does not apply to it.

**Retraining:** `/retrain` checks every uploaded row with the same rules as `/predict` and reports invalid rows by line number. On the free plan the retrained model stays in memory until the service restarts or sleeps; it then reloads `best_model.pkl` from this repository.

## Running Locally (uv)

```bash
cd summative
uv sync                                            # installs the exact versions in uv.lock
uv run jupyter notebook linear_regression/multivariate.ipynb
cd API && uv run uvicorn prediction:app --reload   # then open http://127.0.0.1:8000/docs
```

Rebuild the dataset (after downloading `ug15_hhld.csv`):
```bash
uv run python linear_regression/build_village_dataset.py ug15_hhld.csv linear_regression/uganda_village_learning.csv
```

Regenerate `requirements.txt` after changing dependencies:
```bash
uv export --format requirements.txt --no-hashes --no-dev -o API/requirements.txt
```

## Deployment on Render

New **Web Service** connected to this repository:
- **Name:** `uganda-learning-predictor`
- **Root Directory:** `summative/API`
- **Runtime:** Python 3, with environment variable `PYTHON_VERSION=3.13.5`
- **Build Command:** `pip install -r requirements.txt`
- **Start Command:** `uvicorn prediction:app --host 0.0.0.0 --port $PORT`
- **Instance Type:** Free
