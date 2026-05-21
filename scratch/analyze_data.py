import sys
import os
import firebase_admin
from firebase_admin import credentials, firestore
import pandas as pd
import numpy as np
from datetime import datetime
from sklearn.model_selection import train_test_split
from sklearn.ensemble import RandomForestClassifier, RandomForestRegressor
from sklearn.tree import DecisionTreeClassifier
from sklearn.neighbors import KNeighborsClassifier
from sklearn.metrics import accuracy_score, precision_score, recall_score, f1_score
from sklearn.multioutput import MultiOutputClassifier

# Initialize Firebase
cred = credentials.Certificate('firebase_credentials.json')
try:
    firebase_admin.initialize_app(cred)
except ValueError:
    pass  # Already initialized
db = firestore.client()

# Fetch active parts
parts_ref = db.collection('spare_parts')
parts_docs = parts_ref.stream()
active_parts = sorted(list(set([doc.to_dict().get('name') for doc in parts_docs if doc.to_dict().get('name')])))

# Fetch completed appointments
appointments_ref = db.collection('appointments')
appointments_docs = appointments_ref.stream()
appointments_data = []

for doc in appointments_docs:
    appointment = doc.to_dict()
    status = appointment.get('status', '').lower()
    if 'complete' in status and 'spareParts' in appointment:
        spare_parts = appointment.get('spareParts', [])
        date_value = None
        for date_field in ['date', 'appointmentDate', 'completedDate', 'timestamp', 'createdAt']:
            if date_field in appointment:
                date_value = appointment[date_field]
                break
        
        if not date_value:
            continue
        
        if hasattr(date_value, 'timestamp'):
            date_value = datetime.fromtimestamp(date_value.timestamp())
        elif isinstance(date_value, str):
            try:
                date_value = datetime.strptime(date_value, '%Y-%m-%d')
            except:
                try:
                    date_value = datetime.fromisoformat(date_value.replace('Z', '+00:00'))
                except:
                    continue
        
        if spare_parts and isinstance(spare_parts, list):
            for part in spare_parts:
                if isinstance(part, dict):
                    part_name = part.get('name', '')
                    quantity = part.get('quantity', 0)
                    if part_name and quantity > 0:
                        appointments_data.append({
                            'date': date_value.date() if isinstance(date_value, datetime) else date_value,
                            'part_name': part_name,
                            'quantity': int(quantity)
                        })

df = pd.DataFrame(appointments_data)
df['date'] = pd.to_datetime(df['date'])
df['date'] = df['date'].dt.date

# Preprocess
daily_parts_usage = df.groupby(['date', 'part_name'])['quantity'].sum().reset_index()
date_range = pd.date_range(start=df['date'].min(), end=df['date'].max(), freq='D')

aggregated_data = []
for date in date_range:
    current_date = date.date()
    daily_totals = {'date': current_date}
    day_data = daily_parts_usage[daily_parts_usage['date'] == current_date]
    for part in active_parts:
        part_usage = day_data[day_data['part_name'] == part]
        quantity = part_usage['quantity'].sum() if not part_usage.empty else 0
        daily_totals[f'quantity_{part}'] = quantity
    aggregated_data.append(daily_totals)

agg_df = pd.DataFrame(aggregated_data)
agg_df = agg_df.sort_values('date').reset_index(drop=True)

print("Aggregated shape:", agg_df.shape)
print("Active parts count:", len(active_parts))

# Total daily usage
quantity_cols = [f'quantity_{part}' for part in active_parts]
agg_df['total_daily_usage'] = agg_df[quantity_cols].sum(axis=1)

print("Total daily usage values:")
print(agg_df['total_daily_usage'].value_counts())

# Feature engineering
agg_df['day_of_week'] = pd.to_datetime(agg_df['date']).dt.dayofweek
agg_df['is_weekend'] = (agg_df['day_of_week'] >= 5).astype(int)
agg_df['lag_1_day_total_usage'] = agg_df['total_daily_usage'].shift(1)
agg_df['lag_7_day_avg_usage'] = agg_df['total_daily_usage'].rolling(window=7, min_periods=1).mean().shift(1)

# Let's drop NaN
featured_df = agg_df.dropna(subset=['lag_1_day_total_usage']).copy()
print("Featured shape:", featured_df.shape)

# Let's evaluate a binary classification target: "Is there any demand today?" or "Is daily usage > 0?"
y_binary = (featured_df['total_daily_usage'] > 0).astype(int)
print("Binary target class distribution (total_daily_usage > 0):")
print(y_binary.value_counts())

# Let's see if we frame it as multi-label binary: "Is there demand for each part?"
y_multilabel = (featured_df[quantity_cols].values > 0).astype(int)
print("Multi-label target dimensions:", y_multilabel.shape)
print("Positive label density:", y_multilabel.sum() / y_multilabel.size)
