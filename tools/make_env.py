"""builds the .env (in the plugin root) from my notes file (CLIENT + tokens json)

python tools/make_env.py path/to/notes
"""
import json
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, ".env")

if len(sys.argv) != 2:
    sys.exit(__doc__)

path = sys.argv[1]
text = open(path, encoding="utf-8").read()
client = re.search(r"CLIENT\s*\n\s*([0-9a-fA-F]{20,})", text)
blob = re.search(r"\{.*?\}", text, re.S)
tokens = json.loads(blob.group(0)) if blob else {}
if not client or not tokens.get("refresh_token"):
    sys.exit("Couldn't find the client id or refresh token in " + path)

expires = ""
if tokens.get("expires_in"):
    # no exact issue date for the token, use the file's mtime minus 1h
    expires = str(int(os.path.getmtime(path) + int(tokens["expires_in"]) - 3600))

with open(OUT, "w", encoding="utf-8", newline="\n") as f:
    f.write("# do not commit\n")
    f.write(f"MAL_CLIENT_ID={client.group(1)}\n")
    f.write(f"MAL_ACCESS_TOKEN={tokens.get('access_token', '')}\n")
    f.write(f"MAL_REFRESH_TOKEN={tokens['refresh_token']}\n")
    f.write(f"MAL_TOKEN_EXPIRES_AT={expires}\n")
print("Done:", OUT)
