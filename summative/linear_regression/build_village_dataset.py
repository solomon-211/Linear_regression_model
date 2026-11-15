"""Build a village-level dataset from Uwezo Uganda 2015 child-household data.

Target: avg_learning_score = mean (English level 0-4 + maths level 0-6) of tested children in the village.
Source: https://data.humdata.org/dataset/learning-levels-in-uganda-2015 (Uwezo UG-2015)
"""
import sys
import numpy as np
import pandas as pd

src, out = sys.argv[1], sys.argv[2]
d = pd.read_csv(src, low_memory=False)

ENGLISH = {"Non- reader": 0, "Letter": 1, "Word": 2, "Paragraph": 3, "Story": 4}
MATHS = {"Non- numerate": 0, "Matching": 1, "Num Rec. 10 - 99": 2, "Addition": 3,
         "Subtraction": 4, "Multiplication": 5, "Divide": 6}
d["score"] = d["english"].map(ENGLISH) + d["math"].map(MATHS)

# mother's schooling: "No" to ever attending school means no formal education
mother_known = d["mothers_toschool"].notna()
d["mother_secondary"] = np.where(mother_known, d["mothers_edu"].isin(["Secondary", "> Secondary"]).astype(float), np.nan)
d["mother_schooled"] = d["mothers_toschool"].map({"Yes": 1.0, "No": 0.0})
d["private_school"] = d["schooltype"].map({"Private": 1.0, "Government": 0.0, "Community": 0.0})  # enrolled children only
d["paid_tuition"] = d["tuition"].map({"Yes": 1.0, "No": 0.0})
d["attended_preschool"] = d["preschool"].map({"Yes": 1.0, "No": 0.0})
d["girl"] = (d["gender"] == "Girl").astype(float)

# household-level facts: one row per household so large families don't count twice
hh = d.drop_duplicates("id_hh").copy()
hh["three_meals"] = hh["mealsPerDay"].map({"3 or more": 1.0, "Twice": 0.0, "Once": 0.0})
hh["toilet"] = hh["asset_toilet"].map({"Yes": 1.0, "No": 0.0})
hh["piped_or_borehole"] = hh["water_source"].isin(["Pipe", "Borehole"]).astype(float)
house = hh.groupby("id_village").agg(
    pct_electricity=("asset_elec", "mean"), pct_phone=("asset_phone", "mean"), pct_tv=("asset_tv", "mean"),
    pct_three_meals=("three_meals", "mean"), pct_toilet=("toilet", "mean"),
    pct_safe_water=("piped_or_borehole", "mean"), avg_household_size=("hh_size", "mean"),
)

kids = d.groupby("id_village").agg(
    region=("id_regionName", "first"), area=("urban_code", "first"), district=("id_districtName", "first"),
    pct_mother_secondary=("mother_secondary", "mean"), pct_mother_schooled=("mother_schooled", "mean"),
    pct_private_school=("private_school", "mean"), pct_paid_tuition=("paid_tuition", "mean"),
    pct_preschool=("attended_preschool", "mean"),
)
tested = d.dropna(subset=["score"]).groupby("id_village").agg(
    tested_children=("score", "size"), avg_child_age=("age", "mean"), pct_girls=("girl", "mean"),
    avg_learning_score=("score", "mean"),
)

v = kids.join(house).join(tested, how="inner")
v["area"] = v["area"].map({1: "Rural", 2: "Urban"})
v = v[v["tested_children"] >= 10]                     # stable averages only
pct = [c for c in v.columns if c.startswith("pct_")]
v[pct] = (v[pct] * 100).round(1)                       # shares as percentages 0-100
v[["avg_household_size", "avg_child_age", "avg_learning_score"]] = v[["avg_household_size", "avg_child_age", "avg_learning_score"]].round(2)
v = v.reset_index().rename(columns={"id_village": "village_id"})
v.to_csv(out, index=False)
print(v.shape)
