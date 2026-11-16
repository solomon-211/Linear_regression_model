# Rwanda Food Price Predictor: Protecting Refugees' Food Budgets

**Mission:** To build practical technology that closes the gap in access to the basics of a healthy life for the families most often left behind in East Africa, starting with enough food.
**Problem:** Refugees in Rwanda's camps buy food with a monthly cash transfer, so when staple prices rise, families eat less before anyone notices.
This project predicts **next month's retail price per kg (RWF)** of 19 foods in Rwandan town markets and refugee camps,
so that WFP cash-transfer officers can check whether the planned transfer still covers a basic food basket and top it up in time.

## Dataset

**WFP Food Prices for Rwanda** (World Food Programme), published on the Humanitarian Data Exchange (HDX). WFP field monitors and Rwanda's Ministry of Agriculture record food prices in markets across the country each month; the file has 157,793 prices from 2000 to 2026. I kept only **retail prices per kg of food**, only prices flagged `actual` (observed in a market rather than calculated by WFP), and only **January 2018 onward**, the period with a consistent set of markets that includes the five refugee camps. After removing 15 entry errors and rows without a price for the previous month, the model uses **16,735 prices** from 37 markets. There are 8 features: commodity, province and market type (categorical); distance from Kigali, year, month, last month's price in the same market, and last month's national median price (numeric). The target is `price` in Rwandan francs per kg.

- Source: https://data.humdata.org/dataset/wfp-food-prices-for-rwanda

## API (Swagger UI)

**https://rwanda-food-price-predictor.onrender.com/docs**

- `POST /predict`: accepts the 8 input variables and returns the predicted price (RWF per kg), the change from last month and a price alert (Rising, Stable or Falling).
- `POST /retrain`: accepts a CSV file of new prices, updates the model and applies it immediately.
- The service runs on Render's free plan, which sleeps after 15 minutes of inactivity, so the first request may take up to one minute.

## Video Demonstration

**YouTube:** https://youtu.be/REPLACE_WITH_YOUR_VIDEO_ID

## Running the Mobile Application

1. Install Flutter (https://docs.flutter.dev/get-started/install) and check the installation with `flutter doctor`.
2. Start an Android emulator (Android Studio → Device Manager → ▶) or connect a physical device with USB debugging turned on.
3. Clone the repository and open the app folder:
   ```bash
   git clone https://github.com/solomon-211/Liner_regression_model_project.git
   cd Liner_regression_model_project/summative/FlutterApp
   ```
4. The Android platform folder is included. To also run on iOS (macOS only), generate the iOS folder first (the existing `lib/` and `pubspec.yaml` files are kept):
   ```bash
   flutter create . --project-name rwanda_food_price_predictor --platforms=ios
   ```
5. Install the dependencies:
   ```bash
   flutter pub get
   ```
6. Run the app on the emulator or device:
   ```bash
   flutter devices        # list available device IDs
   flutter run -d <device-id>
   ```
7. Fill in all 8 fields (or tap **Fill example**) and press **Predict**. Example input: Cassava, Eastern Province, Refugee camp, 44.8 km, year 2025, month 9, last month's price 362.5, national median 350. The expected prediction is about 389.5 RWF per kg (+7.4%, Price rising).

If the API is deployed under a different Render service name, update `apiUrl` at the top of `lib/main.dart`.

---

## Repository Structure

```
linear_regression_model/
├── README.md
└── summative/
    ├── pyproject.toml, uv.lock          # uv project configuration (Python 3.13)
    ├── linear_regression/
    │   ├── multivariate.ipynb           # cleaning, analysis, model training, evaluation and model export
    │   └── wfp_food_prices_rwa.csv      # WFP dataset as downloaded from HDX
    ├── API/
    │   ├── prediction.py                # FastAPI service: /predict, /retrain, /docs
    │   ├── requirements.txt             # exported with uv
    │   ├── best_model.pkl               # preprocessing and SGDRegressor Pipeline
    │   └── training_data.csv            # training rows used by /retrain
    └── FlutterApp/                      # one-page Flutter application
```

## Results

Time-based split: trained on February 2018 to August 2025 (15,600 prices), tested on September 2025 to July 2026 (1,135 prices).

| Model | Train MSE | Test MSE | Test RMSE (RWF/kg) |
|---|---|---|---|
| **Linear regression, gradient descent (SGDRegressor)** | 20,065 | **57,037** | **239** |
| Linear regression, closed form (LinearRegression) | 19,766 | 64,040 | 253 |
| Decision tree (max_depth=8) | 9,099 | 102,727 | 321 |
| Random forest (300 trees, min_samples_leaf=1) | 1,959 | 115,209 | 339 |
| Baseline: same price as last month | | 78,964 | 281 |
| Baseline: always predict the training mean | | 3,090,359 | 1,758 |

SGDRegressor has the lowest test MSE, 28% below the "same as last month" rule, so it is saved as `best_model.pkl`. The tree models cannot predict prices above those they saw in training, and 2025 to 2026 prices are the highest in the data.

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

Create a new Web Service connected to this repository with these settings:
- **Name:** `rwanda-food-price-predictor`
- **Root Directory:** `summative/API`
- **Runtime:** Python 3 (version in `summative/API/.python-version`; set the `PYTHON_VERSION` environment variable to a 3.13 release if needed)
- **Build Command:** `pip install -r requirements.txt`
- **Start Command:** `uvicorn prediction:app --host 0.0.0.0 --port $PORT`
- **Instance Type:** Free

A model updated through `/retrain` stays active until the free service restarts or sleeps; after that, the API reloads `best_model.pkl` from the repository.
