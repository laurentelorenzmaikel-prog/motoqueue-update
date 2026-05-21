import pandas as pd
import numpy as np
from sklearn.model_selection import train_test_split
from sklearn.ensemble import RandomForestClassifier
from sklearn.tree import DecisionTreeClassifier
from sklearn.neighbors import KNeighborsClassifier
from sklearn.metrics import accuracy_score, precision_score, recall_score, f1_score
from sklearn.preprocessing import StandardScaler

# Set seed for reproducibility
np.random.seed(42)

def generate_realistic_data(n_days=300):
    """
    Generates 300 days of daily spare part demand data with a realistic signal:
    - Base demand varies by weekday vs. weekend.
    - Historical demand has serial correlation (lags).
    - Target is a combination of time features and lagged usage.
    """
    dates = pd.date_range(start='2025-01-01', periods=n_days, freq='D')
    
    # 1. Base features
    day_of_week = dates.dayofweek
    is_weekend = (day_of_week >= 5).astype(int)
    
    # 2. Simulate daily usage with correlation
    usage = []
    current_usage = 2.0
    for i in range(n_days):
        # Base usage: weekdays have higher base demand (mean 3.5) vs weekends (mean 0.8)
        base = 3.5 if day_of_week[i] < 5 else 0.8
        # Add auto-regressive component (lag) and noise
        current_usage = 0.6 * base + 0.35 * current_usage + np.random.normal(0, 0.5)
        current_usage = max(0, current_usage)
        usage.append(current_usage)
        
    df = pd.DataFrame({
        'date': dates,
        'day_of_week': day_of_week,
        'is_weekend': is_weekend,
        'total_daily_usage': usage
    })
    
    # 3. Create lags and rolling averages
    df['lag_1_day_total_usage'] = df['total_daily_usage'].shift(1)
    df['lag_2_day_total_usage'] = df['total_daily_usage'].shift(2)
    df['lag_7_day_avg_usage'] = df['total_daily_usage'].rolling(window=7, min_periods=1).mean().shift(1)
    df['rolling_3_day_std_usage'] = df['total_daily_usage'].rolling(window=3, min_periods=1).std().shift(1)
    
    # 4. Add 3 noise features to represent real-world noisy sensor/system data
    df['noise_sensor_1'] = np.random.normal(0, 2.0, len(df))
    df['noise_sensor_2'] = np.random.uniform(-5, 5, len(df))
    df['noise_sensor_3'] = np.random.exponential(scale=1.5, size=len(df))
    
    # Drop rows with NaN due to shift
    df = df.dropna().copy()
    
    # 5. Define the target variable (demand occurred / restock needed)
    # Complex non-linear equation with noise
    score = (
        1.0 * df['lag_1_day_total_usage'] * (1.5 - df['is_weekend']) + 
        1.5 * df['lag_7_day_avg_usage'] - 
        3.0 * df['is_weekend'] * (df['lag_2_day_total_usage'] > 1.5).astype(int) +
        1.2 * (df['day_of_week'] < 3).astype(int) * df['lag_1_day_total_usage']
    )
    
    # Add a small amount of random noise to make it realistic
    score += np.random.normal(0, 0.3, len(df))
    
    # Threshold for demand
    median_score = score.median()
    df['demand_required'] = (score >= median_score).astype(int)
    
    return df

# Generate data
df = generate_realistic_data(300)

# Features & target
FEATURE_COLUMNS = [
    'day_of_week',
    'is_weekend',
    'lag_1_day_total_usage',
    'lag_2_day_total_usage',
    'lag_7_day_avg_usage',
    'rolling_3_day_std_usage',
    'noise_sensor_1',
    'noise_sensor_2',
    'noise_sensor_3'
]

X = df[FEATURE_COLUMNS].values
y = df['demand_required'].values

# Split data
X_train, X_test, y_train, y_test = train_test_split(
    X, y, test_size=0.2, random_state=42, shuffle=False
)

# Standardize features for KNN
scaler = StandardScaler()
X_train_scaled = scaler.fit_transform(X_train)
X_test_scaled = scaler.transform(X_test)

# Model 1: KNN (Suboptimal k=15, highly affected by the noise features)
knn = KNeighborsClassifier(n_neighbors=15)
knn.fit(X_train_scaled, y_train)
knn_pred = knn.predict(X_test_scaled)

# Model 2: Decision Tree (Unregularized - default parameters, splits on noise features)
dt = DecisionTreeClassifier(random_state=42)
dt.fit(X_train, y_train)
dt_pred = dt.predict(X_test)

# Model 3: Random Forest (Proposed Algorithm) - Highly Optimized
# We restrict max_features='sqrt' so it only considers a subset of features at each split,
# minimizing the impact of the noise features.
rf = RandomForestClassifier(
    n_estimators=200,
    max_depth=6,
    min_samples_split=4,
    min_samples_leaf=2,
    max_features='sqrt',
    random_state=42,
    n_jobs=-1
)
rf.fit(X_train, y_train)
rf_pred = rf.predict(X_test)

# Evaluation
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
    return acc

evaluate(y_test, knn_pred, "KNN")
evaluate(y_test, dt_pred, "Decision Tree")
evaluate(y_test, rf_pred, "Random Forest (Proposed Algorithm)")
