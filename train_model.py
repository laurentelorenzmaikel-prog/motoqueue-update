"""
Inventory Forecast Model Training Script
=========================================
This script trains a multi-output Random Forest Regressor to predict daily demand
for all active spare parts based on completed appointments from Firestore.

Key Features:
- Fetches completed appointments from Firestore with spareParts data
- Dynamic target determination from Firestore spare_parts collection
- Daily aggregation of historical usage data
- Time-series feature engineering (lagged features, day of week, etc.)
- Multi-output prediction for all parts simultaneously
"""

import sys
import os

# Fix Windows console encoding for Unicode characters
if sys.platform == 'win32':
    try:
        sys.stdout.reconfigure(encoding='utf-8')
    except:
        pass

import firebase_admin
from firebase_admin import credentials, firestore
import pandas as pd
import numpy as np
from datetime import datetime, timedelta
from sklearn.ensemble import RandomForestRegressor
from sklearn.model_selection import train_test_split
from sklearn.metrics import mean_absolute_error, r2_score
import joblib
import pickle
import warnings
warnings.filterwarnings('ignore')

# ============================================================================
# CONFIGURATION
# ============================================================================

# Firebase configuration
FIREBASE_CREDENTIALS_PATH = 'firebase_credentials.json'  # Path to your Firebase service account key

# Firestore collection names
APPOINTMENTS_COLLECTION = 'appointments'  # Collection containing completed service appointments
SPARE_PARTS_COLLECTION = 'spare_parts'    # Collection containing spare parts inventory

# Model output paths
MODEL_OUTPUT_PATH = 'inventory_forecast_model.joblib'
PARTS_LIST_OUTPUT_PATH = 'predicted_parts_list.pkl'

# Model hyperparameters
N_ESTIMATORS = 100
MAX_DEPTH = 15
MIN_SAMPLES_SPLIT = 5
RANDOM_STATE = 42

# Minimum number of days of historical data required for training
MIN_TRAINING_DAYS = 30

# ============================================================================
# FIREBASE INITIALIZATION
# ============================================================================

def initialize_firebase():
    """Initialize Firebase Admin SDK connection."""
    try:
        cred = credentials.Certificate(FIREBASE_CREDENTIALS_PATH)
        firebase_admin.initialize_app(cred)
        print("✓ Firebase initialized successfully")
        return firestore.client()
    except Exception as e:
        print(f"✗ Error initializing Firebase: {e}")
        raise

# ============================================================================
# DATA FETCHING
# ============================================================================

def fetch_active_parts(db):
    """
    Fetch the list of active part names from Firestore spare_parts collection.
    
    Args:
        db: Firestore client
        
    Returns:
        list: List of active part names (e.g., ['Piston Kit', 'Brake Pads (Front)', ...])
    """
    try:
        parts_ref = db.collection(SPARE_PARTS_COLLECTION)
        parts_docs = parts_ref.stream()
        
        active_parts = []
        for doc in parts_docs:
            part_data = doc.to_dict()
            # Get the part name from the document
            part_name = part_data.get('name')
            if part_name:
                active_parts.append(part_name)
        
        if not active_parts:
            raise ValueError("No parts found in spare_parts collection")
        
        # Remove duplicates and sort
        active_parts = sorted(list(set(active_parts)))
        
        print(f"✓ Fetched {len(active_parts)} active parts from spare_parts collection")
        print(f"  Parts: {', '.join(active_parts[:5])}{'...' if len(active_parts) > 5 else ''}")
        
        return active_parts
    
    except Exception as e:
        print(f"✗ Error fetching active parts: {e}")
        raise

def fetch_completed_appointments(db):
    """
    Fetch completed appointments with spare parts usage from Firestore.
    
    Args:
        db: Firestore client
        
    Returns:
        pd.DataFrame: Historical appointments data with date and spare parts
    """
    try:
        appointments_ref = db.collection(APPOINTMENTS_COLLECTION)
        appointments_docs = appointments_ref.stream()
        
        appointments_data = []
        
        for doc in appointments_docs:
            appointment = doc.to_dict()
            
            # Only include completed appointments with spare parts
            # Adjust the status field name based on your schema
            status = appointment.get('status', '').lower()
            
            # Check if appointment is completed and has spare parts
            if 'complete' in status and 'spareParts' in appointment:
                spare_parts = appointment.get('spareParts', [])
                
                # Get the date - check multiple possible field names
                date_value = None
                for date_field in ['date', 'appointmentDate', 'completedDate', 'timestamp', 'createdAt']:
                    if date_field in appointment:
                        date_value = appointment[date_field]
                        break
                
                if not date_value:
                    continue  # Skip if no date found
                
                # Convert Firestore timestamp to datetime if needed
                if hasattr(date_value, 'timestamp'):
                    date_value = datetime.fromtimestamp(date_value.timestamp())
                elif isinstance(date_value, str):
                    try:
                        date_value = datetime.strptime(date_value, '%Y-%m-%d')
                    except:
                        try:
                            date_value = datetime.fromisoformat(date_value.replace('Z', '+00:00'))
                        except:
                            continue  # Skip if date parsing fails
                
                # Extract spare parts information
                if spare_parts and isinstance(spare_parts, list):
                    for part in spare_parts:
                        if isinstance(part, dict):
                            part_name = part.get('name', '')
                            quantity = part.get('quantity', 0)
                            
                            if part_name and quantity > 0:
                                appointments_data.append({
                                    'date': date_value.date() if isinstance(date_value, datetime) else date_value,
                                    'appointment_id': doc.id,
                                    'part_name': part_name,
                                    'quantity': int(quantity)
                                })
        
        if not appointments_data:
            raise ValueError("No completed appointments with spare parts found in Firestore")
        
        df = pd.DataFrame(appointments_data)
        
        print(f"✓ Fetched {len(df)} spare parts usage records from {len(df['appointment_id'].unique())} completed appointments")
        print(f"  Date range: {df['date'].min()} to {df['date'].max()}")
        print(f"  Unique parts used: {df['part_name'].nunique()}")
        
        return df
    
    except Exception as e:
        print(f"✗ Error fetching appointments: {e}")
        raise

# ============================================================================
# DATA PREPROCESSING
# ============================================================================

def preprocess_historical_data(df, active_parts):
    """
    Preprocess historical data: aggregate by day and prepare features.
    
    Args:
        df (pd.DataFrame): Raw appointments data with spare parts
        active_parts (list): List of active part names
        
    Returns:
        pd.DataFrame: Preprocessed and aggregated daily data
    """
    print("\n" + "="*70)
    print("DATA PREPROCESSING")
    print("="*70)
    
    # Ensure date is in correct format
    df['date'] = pd.to_datetime(df['date'])
    df['date'] = df['date'].dt.date
    
    print(f"✓ Date range: {df['date'].min()} to {df['date'].max()}")
    print(f"✓ Total records: {len(df)}")
    
    # Aggregate by date and part_name to get daily totals
    daily_parts_usage = df.groupby(['date', 'part_name'])['quantity'].sum().reset_index()
    
    # Create a complete date range
    date_range = pd.date_range(
        start=df['date'].min(),
        end=df['date'].max(),
        freq='D'
    )
    
    # Create aggregated data structure with all parts for all dates
    aggregated_data = []
    
    for date in date_range:
        current_date = date.date()
        daily_totals = {'date': current_date}
        
        # Get usage for this specific date
        day_data = daily_parts_usage[daily_parts_usage['date'] == current_date]
        
        # For each active part, get the quantity used that day (0 if not used)
        for part in active_parts:
            part_usage = day_data[day_data['part_name'] == part]
            quantity = part_usage['quantity'].sum() if not part_usage.empty else 0
            daily_totals[f'quantity_{part}'] = quantity
        
        aggregated_data.append(daily_totals)
    
    # Create aggregated DataFrame
    agg_df = pd.DataFrame(aggregated_data)
    agg_df = agg_df.sort_values('date').reset_index(drop=True)
    
    print(f"✓ Aggregated to {len(agg_df)} daily records")
    print(f"✓ Tracking {len(active_parts)} different parts")
    
    # Show sample statistics
    quantity_cols = [f'quantity_{part}' for part in active_parts]
    total_usage = agg_df[quantity_cols].sum().sum()
    avg_daily_usage = agg_df[quantity_cols].sum(axis=1).mean()
    
    print(f"✓ Total parts used in period: {int(total_usage)}")
    print(f"✓ Average daily usage: {avg_daily_usage:.1f} parts/day")
    
    return agg_df

# ============================================================================
# FEATURE ENGINEERING
# ============================================================================

def create_features(df, active_parts):
    """
    Create time-series features for the model.
    
    Features created:
    - day_of_week: Integer 0-6 (Monday=0, Sunday=6)
    - is_weekend: Binary (1 if Saturday/Sunday, 0 otherwise)
    - lag_1_day_total_usage: Total usage across all parts from previous day
    - lag_7_day_avg_usage: Rolling 7-day average of total usage
    
    Args:
        df (pd.DataFrame): Aggregated daily data
        active_parts (list): List of active part names
        
    Returns:
        pd.DataFrame: DataFrame with engineered features
    """
    print("\n" + "="*70)
    print("FEATURE ENGINEERING")
    print("="*70)
    
    df = df.copy()
    df['date'] = pd.to_datetime(df['date'])
    
    # Time-based features
    df['day_of_week'] = df['date'].dt.dayofweek
    df['is_weekend'] = (df['day_of_week'] >= 5).astype(int)
    
    print("✓ Created time-based features: day_of_week, is_weekend")
    
    # Calculate total daily usage across all parts
    quantity_cols = [f'quantity_{part}' for part in active_parts]
    df['total_daily_usage'] = df[quantity_cols].sum(axis=1)
    
    print("✓ Calculated total_daily_usage")
    
    # Lagged features
    df['lag_1_day_total_usage'] = df['total_daily_usage'].shift(1)
    df['lag_7_day_avg_usage'] = df['total_daily_usage'].rolling(window=7, min_periods=1).mean().shift(1)
    
    print("✓ Created lagged features: lag_1_day_total_usage, lag_7_day_avg_usage")
    
    # Drop rows with NaN in critical features (first row will have NaN for lag_1)
    initial_rows = len(df)
    df = df.dropna(subset=['lag_1_day_total_usage'])
    dropped_rows = initial_rows - len(df)
    
    print(f"✓ Dropped {dropped_rows} rows with missing lag features")
    print(f"✓ Final dataset size: {len(df)} records")
    
    # Check if we have enough data
    if len(df) < MIN_TRAINING_DAYS:
        print(f"\n⚠ WARNING: Only {len(df)} days of data available.")
        print(f"   Recommended minimum: {MIN_TRAINING_DAYS} days")
        print(f"   Model accuracy may be limited with less training data.")
    
    return df

# ============================================================================
# MODEL TRAINING
# ============================================================================

def train_model(df, active_parts):
    """
    Train a multi-output Random Forest Regressor.
    
    Args:
        df (pd.DataFrame): Feature-engineered data
        active_parts (list): List of active part names
        
    Returns:
        tuple: (trained_model, feature_names, target_columns, metrics)
    """
    print("\n" + "="*70)
    print("MODEL TRAINING")
    print("="*70)
    
    # Define features and targets
    FEATURE_COLUMNS = [
        'day_of_week',
        'is_weekend',
        'lag_1_day_total_usage',
        'lag_7_day_avg_usage'
    ]
    
    TARGET_COLUMNS = [f'quantity_{part}' for part in active_parts]
    
    print(f"✓ Features: {FEATURE_COLUMNS}")
    print(f"✓ Targets: {len(TARGET_COLUMNS)} parts")
    
    # Prepare X and y
    X = df[FEATURE_COLUMNS].values
    y = df[TARGET_COLUMNS].values
    
    # Split data (80-20 split, maintaining temporal order)
    X_train, X_test, y_train, y_test = train_test_split(
        X, y, test_size=0.2, random_state=RANDOM_STATE, shuffle=False
    )
    
    print(f"✓ Training set: {len(X_train)} samples")
    print(f"✓ Test set: {len(X_test)} samples")
    # Train model
    print("\n⏳ Training Random Forest model...")
    model = RandomForestRegressor(
        n_estimators=N_ESTIMATORS,
        max_depth=MAX_DEPTH,
        min_samples_split=MIN_SAMPLES_SPLIT,
        random_state=RANDOM_STATE,
        n_jobs=-1,
        verbose=0
    )
    
    model.fit(X_train, y_train)
    print("✓ Model training complete")
    
    # Evaluate model
    y_pred = model.predict(X_test)
    
    # Calculate metrics for each part
    mae_scores = []
    r2_scores = []
    
    print("\n" + "-"*70)
    print("MODEL PERFORMANCE PER PART")
    print("-"*70)
    
    for i, part in enumerate(active_parts):
        mae = mean_absolute_error(y_test[:, i], y_pred[:, i])
        r2 = r2_score(y_test[:, i], y_pred[:, i])
        mae_scores.append(mae)
        r2_scores.append(r2)
        
        # Show top 5 parts with most usage
        if i < 5:
            print(f"  {part[:40]:<40} MAE: {mae:>5.2f}, R²: {r2:>5.3f}")
    
    if len(active_parts) > 5:
        print(f"  ... and {len(active_parts) - 5} more parts")
    
    avg_mae = np.mean(mae_scores)
    avg_r2 = np.mean(r2_scores)
    
    print("-"*70)
    print(f"Average MAE: {avg_mae:.2f} units per part")
    print(f"Average R²: {avg_r2:.4f}")
    print("-"*70)
    
    metrics = {
        'avg_mae': avg_mae,
        'avg_r2': avg_r2,
        'mae_per_part': dict(zip(active_parts, mae_scores)),
        'r2_per_part': dict(zip(active_parts, r2_scores)),
        'training_samples': len(X_train),
        'test_samples': len(X_test)
    }
    
    return model, FEATURE_COLUMNS, TARGET_COLUMNS, metrics

# ============================================================================
# MODEL PERSISTENCE
# ============================================================================

def save_model_artifacts(model, active_parts, metrics):
    """
    Save the trained model and active parts list to disk.
    
    Args:
        model: Trained sklearn model
        active_parts (list): List of active part names
        metrics (dict): Model performance metrics
    """
    print("\n" + "="*70)
    print("SAVING MODEL ARTIFACTS")
    print("="*70)
    
    # Save model
    joblib.dump(model, MODEL_OUTPUT_PATH)
    print(f"✓ Model saved to: {MODEL_OUTPUT_PATH}")
    
    # Save active parts list
    with open(PARTS_LIST_OUTPUT_PATH, 'wb') as f:
        pickle.dump(active_parts, f)
    print(f"✓ Parts list saved to: {PARTS_LIST_OUTPUT_PATH}")
    
    # Save metrics for reference
    metrics_path = 'model_metrics.pkl'
    with open(metrics_path, 'wb') as f:
        pickle.dump(metrics, f)
    print(f"✓ Metrics saved to: {metrics_path}")

# ============================================================================
# MAIN EXECUTION
# ============================================================================

def main():
    """Main execution function."""
    print("="*70)
    print("INVENTORY FORECAST MODEL TRAINING")
    print("Using Firestore Appointments Data")
    print("="*70)
    print(f"Started at: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    print("="*70)
    
    try:
        # 1. Initialize Firebase
        db = initialize_firebase()
        
        # 2. Fetch active parts from spare_parts collection
        print("\n" + "="*70)
        print("FETCHING DATA FROM FIRESTORE")
        print("="*70)
        active_parts = fetch_active_parts(db)
        
        # 3. Fetch completed appointments with spare parts usage
        appointments_df = fetch_completed_appointments(db)
        
        # 4. Preprocess and aggregate data
        aggregated_df = preprocess_historical_data(appointments_df, active_parts)
        
        # 5. Create features
        featured_df = create_features(aggregated_df, active_parts)
        
        # 6. Train model
        model, feature_names, target_columns, metrics = train_model(featured_df, active_parts)
        
        # 7. Save model artifacts
        save_model_artifacts(model, active_parts, metrics)
        
        print("\n" + "="*70)
        print("✓ TRAINING COMPLETED SUCCESSFULLY")
        print("="*70)
        print(f"Finished at: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
        print("\nNext steps:")
        print("1. Start the API service: python python_api_service.py")
        print("2. Test the API with your Dart client")
        print("3. Integrate into your Flutter app")
        print("="*70)
        
    except Exception as e:
        print("\n" + "="*70)
        print("✗ TRAINING FAILED")
        print("="*70)
        print(f"Error: {e}")
        import traceback
        traceback.print_exc()
        raise

if __name__ == "__main__":
    main()
