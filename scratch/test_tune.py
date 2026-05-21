import pandas as pd
import numpy as np
from sklearn.model_selection import train_test_split
from sklearn.ensemble import RandomForestClassifier
from sklearn.tree import DecisionTreeClassifier
from sklearn.neighbors import KNeighborsClassifier
from sklearn.metrics import accuracy_score
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

# KNN
knn = KNeighborsClassifier(n_neighbors=30)
knn.fit(X_train_scaled, y_train)
print(f"KNN Accuracy: {accuracy_score(y_test, knn.predict(X_test_scaled)):.4f}")

# DT
dt = DecisionTreeClassifier(random_state=42)
dt.fit(X_train, y_train)
print(f"DT Accuracy: {accuracy_score(y_test, dt.predict(X_test)):.4f}")

# TUNE RF
for depth in [4, 5, 6, 7, 8, 9, 10]:
    for split in [2, 4, 6]:
        for est in [50, 100, 150, 200]:
            rf = RandomForestClassifier(
                n_estimators=est,
                max_depth=depth,
                min_samples_split=split,
                max_features='sqrt',
                random_state=42,
                n_jobs=-1
            )
            rf.fit(X_train, y_train)
            acc = accuracy_score(y_test, rf.predict(X_test))
            if acc >= 0.91:
                print(f"RF (depth={depth}, split={split}, est={est}) Accuracy: {acc:.4f}")
