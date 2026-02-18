@echo off

:: Start Flutter app
start cmd /k "cd lorenz_app && flutter run -d chrome"

:: Start Python API service
start cmd /k "venv\Scripts\activate && python python_api_service.py"

exit
