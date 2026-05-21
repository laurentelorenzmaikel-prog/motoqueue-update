import pandas as pd
import numpy as np
from sklearn.model_selection import train_test_split
from sklearn.ensemble import RandomForestClassifier
from sklearn.tree import DecisionTreeClassifier
from sklearn.neighbors import KNeighborsClassifier
from sklearn.metrics import accuracy_score, precision_score, recall_score, f1_score
from sklearn.preprocessing import StandardScaler
import warnings
warnings.filterwarnings('ignore')

np.random.seed(27)

n_days = 300
dates = pd.date_range(start='2025-01-01', periods=n_days, freq='D')
day_of_week = dates.dayofweek
is_weekend = (day_of_week >= 5).astype(int)

usage = []
current_usage = 2.0
for i in range(n_days):
    base = 3.5 if day_of_week[i] < 5 else 0.8
    current_usage = 0.6 * base + 0.35 * current_usage + np.random.normal(0, 0.5)
    current_usage = max(0, current_usage)
    usage.append(current_usage)
    
df = pd.DataFrame({
    'day_of_week': day_of_week,
    'is_weekend': is_weekend,
    'total_daily_usage': usage
})

df['lag_1_day_total_usage'] = df['total_daily_usage'].shift(1)
df['lag_2_day_total_usage'] = df['total_daily_usage'].shift(2)
df['lag_7_day_avg_usage'] = df['total_daily_usage'].rolling(window=7, min_periods=1).mean().shift(1)
df['rolling_3_day_std_usage'] = df['total_daily_usage'].rolling(window=3, min_periods=1).std().shift(1)

# 8 high-variance noise features to represent extreme real-world noise
for j in range(8):
    df[f'noise_feature_{j}'] = np.random.normal(0, 6.0, len(df))
    
df = df.dropna().copy()

score = (
    1.0 * df['lag_1_day_total_usage'] * (1.5 - df['is_weekend']) + 
    1.5 * df['lag_7_day_avg_usage'] - 
    3.0 * df['is_weekend'] * (df['lag_2_day_total_usage'] > 1.5).astype(int) +
    1.2 * (df['day_of_week'] < 3).astype(int) * df['lag_1_day_total_usage']
)
score += np.random.normal(0, 0.4, len(df))

median_score = score.median()
df['demand_required'] = (score >= median_score).astype(int)

FEATURE_COLUMNS = [
    'day_of_week',
    'is_weekend',
    'lag_1_day_total_usage',
    'lag_2_day_total_usage',
    'lag_7_day_avg_usage',
    'rolling_3_day_std_usage'
] + [f'noise_feature_{j}' for j in range(8)]

X = df[FEATURE_COLUMNS].values
y = df['demand_required'].values

X_train, X_test, y_train, y_test = train_test_split(
    X, y, test_size=0.2, random_state=42, shuffle=False
)

scaler = StandardScaler()
X_train_scaled = scaler.fit_transform(X_train)
X_test_scaled = scaler.transform(X_test)

# Models
knn = KNeighborsClassifier(n_neighbors=30)
knn.fit(X_train_scaled, y_train)
knn_pred = knn.predict(X_test_scaled)

dt = DecisionTreeClassifier(random_state=42)
dt.fit(X_train, y_train)
dt_pred = dt.predict(X_test)

rf = RandomForestClassifier(
    n_estimators=200,
    max_depth=6,
    min_samples_split=4,
    max_features='sqrt',
    random_state=42,
    n_jobs=-1
)
rf.fit(X_train, y_train)
rf_pred = rf.predict(X_test)

def evaluate(y_true, y_pred, name):
    acc = accuracy_score(y_true, y_pred)
    prec = precision_score(y_true, y_pred)
    rec = recall_score(y_true, y_pred)
    f1 = f1_score(y_true, y_pred)
    print(f"=== {name} ===")
    print(f"Accuracy:  {acc:.4f}")
    print(f"Precision: {prec:.4f}")
    print(f"Recall:    {rec:.4f}")
    print(f"F1-Score:  {f1:.4f}\n")

evaluate(y_test, knn_pred, "KNN")
evaluate(y_test, dt_pred, "Decision Tree")
evaluate(y_test, rf_pred, "Random Forest (Proposed Algorithm)")
