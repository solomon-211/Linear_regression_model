"""Retraining logic used by the /retrain route in prediction.py.

The saved model is updated with new price rows:
- SGDRegressor: keep training the saved model with partial_fit on the new rows,
  mixed with an equal-sized sample of old rows so it does not forget earlier prices.
- Any other model: refit the whole pipeline on the original data plus the new rows.
"""

from dataclasses import dataclass

import pandas as pd
from sklearn.base import clone
from sklearn.linear_model import SGDRegressor
from sklearn.metrics import mean_squared_error
from sklearn.pipeline import Pipeline

EPOCHS_ON_NEW_DATA = 5


@dataclass
class RetrainResult:
    model: Pipeline
    data: pd.DataFrame
    method: str
    mse_before: float
    mse_after: float


def retrain_model(model: Pipeline, old_data: pd.DataFrame, new_data: pd.DataFrame,
                  features: list[str], target: str) -> RetrainResult:
    X_new, y_new = new_data[features], new_data[target]
    mse_before = mean_squared_error(y_new, model.predict(X_new))
    combined = pd.concat([old_data, new_data], ignore_index=True)

    if isinstance(model.named_steps["model"], SGDRegressor):
        old_sample = old_data.sample(min(len(new_data), len(old_data)), random_state=0)
        mix = pd.concat([new_data, old_sample], ignore_index=True)
        Xt = model.named_steps["preprocess"].transform(mix[features])
        for _ in range(EPOCHS_ON_NEW_DATA):
            model.named_steps["model"].partial_fit(Xt, mix[target])
        updated = model
        method = "SGDRegressor: continued training with partial_fit on the new rows plus a sample of old rows"
    else:
        updated = clone(model).fit(combined[features], combined[target])
        method = f"{type(model.named_steps['model']).__name__}: refit on original data + new rows"

    mse_after = mean_squared_error(y_new, updated.predict(X_new))
    return RetrainResult(updated, combined, method, mse_before, mse_after)
