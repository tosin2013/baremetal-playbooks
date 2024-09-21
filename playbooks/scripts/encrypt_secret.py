#!/usr/bin/env python3
import os
from base64 import b64encode
from nacl import encoding, public
import subprocess

def encrypt(public_key: str, secret_value: str) -> str:
  """Encrypt a Unicode string using the public key."""
  public_key = public.PublicKey(public_key.encode("utf-8"), encoding.Base64Encoder())
  sealed_box = public.SealedBox(public_key)
  encrypted = sealed_box.encrypt(secret_value.encode("utf-8"))
  return b64encode(encrypted).decode("utf-8")

def fetch_secret(secret_name):
    result = subprocess.run(['hcp', 'vault-secrets', 'secrets', 'open', secret_name], capture_output=True, text=True)
    if result.returncode == 0:
        return result.stdout.strip()
    else:
        return None

public_key = os.environ.get("PUBLIC_KEY", fetch_secret("PUBLIC_KEY"))
secret = os.environ.get("SECRET", fetch_secret("SECRET"))

if public_key and secret:
    encrypted_secret = encrypt(public_key, secret)
    print(encrypted_secret)
else:
    print("Error: Could not fetch public key or secret.")
