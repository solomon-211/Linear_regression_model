# Village Learning Predictor: Targeting Education Support in Uganda

**Mission:** To develop and implement innovative educational technologies that bridge the gap in access to quality education for young people in South Sudan and beyond.
**Problem:** In East Africa, being in school does not guarantee learning, and where a child lives strongly shapes how much they learn.
This project predicts the **average reading-and-maths learning score (0–10)** of children in a Ugandan village from its community characteristics,
so that education officers and NGOs can direct teachers, learning tools and materials to the communities that need them most.

## Dataset

**Uwezo Uganda 2015 Learning Assessment** (Twaweza East Africa), published on the Humanitarian Data Exchange (HDX). Uwezo volunteers visited households across all four regions of Uganda and tested 164,129 children aged 6–16 in English reading and numeracy, recording household and schooling characteristics. Using `build_village_dataset.py`, I combined these child records into **3,219 villages** (each with at least 10 tested children). The target, `avg_learning_score`, is the village average of each child's English level (0–4) plus maths level (0–6). The features combine categorical variables (region, urban/rural) with numeric community indicators (shares of households with electricity, phones, toilets and three meals a day; mothers' secondary education; private schooling; paid tuition; preschool; average household size and child age).

- Source: https://data.humdata.org/dataset/learning-levels-in-uganda-2015

## API (Swagger UI)

**https://uganda-learning-predictor.onrender.com/docs**

- `POST /predict`: accepts the 12 input variables and returns the predicted learning score with a support priority (High, Medium or Low).
- `POST /retrain`: accepts a CSV file of new village records, retrains the model and applies it immediately.
- The service runs on Render's free plan, which sleeps after 15 minutes of inactivity; the first request may take up to one minute.

## Video Demonstration

**YouTube:** https://youtu.be/REPLACE_WITH_YOUR_VIDEO_ID

## Running the Mobile Application

1. Install Flutter (https://docs.flutter.dev/get-started/install) and verify the installation with `flutter doctor`.
2. Start an Android emulator (Android Studio → Device Manager → ▶) or connect a physical device with USB debugging enabled.
3. Clone the repository and open the application folder:
   ```bash
   git clone https://github.com/solomon-211/Liner_regression_model_project.git
   cd Liner_regression_model_project/summative/FlutterApp
   ```
4. The Android platform folder is included. To also run on iOS (macOS only), generate the iOS folder first (existing `lib/` and `pubspec.yaml` files are preserved):
   ```bash
   flutter create . --project-name uganda_learning_predictor --platforms=ios
   ```
5. Install the dependencies:
   ```bash
   flutter pub get
   ```
6. Run the application on the emulator or device:
   ```bash
   flutter devices        # list available device IDs
   flutter run -d <device-id>
   ```
7. Complete all 12 fields (or tap **Fill example**) and press **Predict**. Example input: region Central, area Rural, mothers with secondary education 27.8, electricity 22.2, phone 44.4, toilet 66.7, three meals 33.3, household size 4.78, private school 0, paid tuition 0, preschool 4.3, child age 10.11. The expected prediction is approximately 4.88 / 10 (Medium priority).

If the API is deployed under a different Render service name, update `apiUrl` at the top of `lib/main.dart`.

---

## Repository Structure

```
linear_regression_model/
├── README.md
└── summative/
    ├── pyproject.toml, uv.lock          # uv project configuration (Python 3.13)
    ├── linear_regression/
    │   ├── multivariate.ipynb           # data analysis, model training, evaluation and model export
    │   ├── uganda_village_learning.csv  # village-level dataset used for modelling
    │   └── build_village_dataset.py     # builds the village dataset from the raw Uwezo file
    ├── API/
    │   ├── prediction.py                # FastAPI service: /predict, /retrain, /docs
    │   ├── requirements.txt             # exported with uv
    │   ├── best_model.pkl               # preprocessing and linear regression Pipeline
    │   └── training_data.csv            # training records used by /retrain
    └── FlutterApp/                      # single-page Flutter application
```

To rebuild the village dataset, download `ug15_hhld.csv` from the HDX page above and run:
```bash
uv run python linear_regression/build_village_dataset.py ug15_hhld.csv linear_regression/uganda_village_learning.csv
```

## Results

| Model | Train MSE | Test MSE |
|---|---|---|
| **Linear regression, closed form (LinearRegression)** | 1.233 | **1.149** |
| Linear regression, gradient descent (SGDRegressor) | 1.234 | 1.152 |
| Random forest (300 trees, min_samples_leaf=10) | 0.810 | 1.170 |
| Decision tree (max_depth=6) | 1.212 | 1.597 |
| Baseline (always predict the training mean) | | 2.424 |

Linear regression achieves the lowest test MSE (RMSE ≈ 1.07 points on the 0–10 scale) and is therefore saved as `best_model.pkl`.

## Local Development (uv)

```bash
cd summative
uv sync                                   # create the virtual environment from uv.lock
uv run jupyter notebook linear_regression/multivariate.ipynb
cd API && uv run uvicorn prediction:app --reload   # then open http://127.0.0.1:8000/docs
```

To regenerate the API requirements after changing dependencies:
```bash
cd summative
uv export --format requirements.txt --no-hashes --no-dev -o API/requirements.txt
```

## Deployment on Render

Create a new Web Service connected to this repository with the following settings:
- **Name:** `uganda-learning-predictor`
- **Root Directory:** `summative/API`
- **Runtime:** Python 3 (version specified in `summative/API/.python-version`; set the `PYTHON_VERSION` environment variable to a 3.13 release if needed)
- **Build Command:** `pip install -r requirements.txt`
- **Start Command:** `uvicorn prediction:app --host 0.0.0.0 --port $PORT`
- **Instance Type:** Free

A model retrained through `/retrain` remains active until the free service restarts or sleeps, after which the API reloads `best_model.pkl` from the repository.
