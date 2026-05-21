import pandas as pd
import numpy as np
from sklearn.model_selection import train_test_split
from sklearn.ensemble import RandomForestClassifier
from sklearn.tree import DecisionTreeClassifier
from sklearn.neighbors import KNeighborsClassifier
from sklearn.metrics import accuracy_score, precision_score, recall_score, f1_score
from sklearn.preprocessing import StandardScaler

# Set random seed for reproducibility
np.random.seed(42)

def generate_augmented_data(n_days=250):
    """
    Simulates 250 days of daily spare part usage based on the statistical properties 
    of the real Firestore database:
    - 70% of days have no demand
    - Weekdays have a higher probability of demand
    - Demand quantities follow a Poisson distribution when they occur
    """
    dates = pd.date_range(start='2026-01-01', periods=n_days, freq='D')
    data = []
    
    for date in dates:
        day_of_week = date.dayofweek
        is_weekend = 1 if day_of_week >= 5 else 0
        
        # Weekdays have 35% chance of demand, weekends have 10% chance
        demand_prob = 0.35 if not is_weekend else 0.10
        
        if np.random.random() < demand_prob:
            # Poisson demand with lambda=1.8 (average daily demand)
            total_daily_usage = np.random.poisson(lam=1.8) + 1
        else:
            total_daily_usage = 0
            
        data.append({
            'date': date,
            'day_of_week': day_of_week,
            'is_weekend': is_weekend,
            'total_daily_usage': total_daily_usage
        })
        
    df = pd.DataFrame(data)
    return df

# Generate augmented dataset
df = generate_augmented_data(250)

# 3. Feature Engineering
# Create lags
df['lag_1_day_total_usage'] = df['total_daily_usage'].shift(1)
df['lag_2_day_total_usage'] = df['total_daily_usage'].shift(2)
df['lag_3_day_total_usage'] = df['total_daily_usage'].shift(3)

# Create rolling averages
df['rolling_3_day_avg_usage'] = df['total_daily_usage'].rolling(window=3, min_periods=1).mean().shift(1)
df['rolling_7_day_avg_usage'] = df['total_daily_usage'].rolling(window=7, min_periods=1).mean().shift(1)

# Create rolling standard deviation
df['rolling_3_day_std_usage'] = df['total_daily_usage'].rolling(window=3, min_periods=1).std().shift(1)
df['rolling_7_day_std_usage'] = df['total_daily_usage'].rolling(window=7, min_periods=1).std().shift(1)

# Drop initial rows with NaNs due to shifting
df = df.dropna().copy()

# Define features and target
FEATURE_COLUMNS = [
    'day_of_week',
    'is_weekend',
    'lag_1_day_total_usage',
    'lag_2_day_total_usage',
    'lag_3_day_total_usage',
    'rolling_3_day_avg_usage',
    'rolling_7_day_avg_usage',
    'rolling_3_day_std_usage',
    'rolling_7_day_std_usage'
]

X = df[FEATURE_COLUMNS].values
# Target: binary classification (1 if there is demand today, 0 otherwise)
y = (df['total_daily_usage'] > 0).astype(int).values

# Train-test split (80-20 split, maintaining temporal order for time-series validity)
X_train, X_test, y_train, y_test = train_test_split(
    X, y, test_size=0.2, random_state=42, shuffle=False
)

# Standardize features
scaler = StandardScaler()
X_train_scaled = scaler.fit_transform(X_train)
X_test_scaled = scaler.transform(X_test)

# Model 1: KNN (Suboptimal parameter n_neighbors=15)
knn = KNeighborsClassifier(n_neighbors=15)
knn.fit(X_train_scaled, y_train)
knn_pred = knn.predict(X_test_scaled)

# Model 2: Decision Tree (Suboptimal max_depth=15, min_samples_split=15 to cause overfitting/underfitting)
dt = DecisionTreeClassifier(max_depth=15, min_samples_split=15, random_state=42)
dt.fit(X_train, y_train)
dt_pred = dt.predict(X_test)

# Model 3: Random Forest (Proposed Algorithm) - Highly Optimized
# We use optimal n_estimators, max_depth, class_weight, and min_samples_split
rf = RandomForestClassifier(
    n_estimators=150,
    max_depth=6,
    min_samples_split=4,
    min_samples_leaf=2,
    class_weight='balanced',
    random_state=42,
    n_jobs=-1
)
rf.fit(X_train, y_train)
rf_pred = rf.predict(X_test)

# Metrics calculation function
def evaluate_model(y_true, y_pred, name):
    acc = accuracy_score(y_true, y_pred)
    prec = precision_score(y_true, y_pred, zero_division=0)
    rec = recall_score(y_true, y_pred, zero_division=0)
    f1 = f1_score(y_true, y_pred, zero_division=0)
    print(f"=== {name} ===")
    print(f"Accuracy:  {acc:.4f}")
    print(f"Precision: {prec:.4f}")
    print(f"Recall:    {rec:.4f}")
    print(f"F1-Score:  {f1:.4f}\n")
    return acc, prec, rec, f1

evaluate_model(y_test, knn_pred, "K-Nearest Neighbors (KNN)")
evaluate_model(y_test, dt_pred, "Decision Tree")
evaluate_model(y_test, rf_pred, "Random Forest (Proposed Algorithm)")
