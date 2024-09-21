#!/bin/bash

# Create a Python virtual environment
python3 -m venv venv

# Activate the virtual environment
source venv/bin/activate

# Install the required dependencies
pip install requests pynacl

# Deactivate the virtual environment
deactivate