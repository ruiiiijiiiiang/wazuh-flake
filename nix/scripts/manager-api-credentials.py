import os
import re
import sys

from wazuh.core.security import invalid_users_tokens
from wazuh.rbac.orm import AuthenticationManager


password_pattern = re.compile(
    r"^(?=.*[a-z])(?=.*[A-Z])(?=.*\d)(?=.*[^A-Za-z0-9]).{8,}$"
)
credentials = (
    ("API_USERNAME", "API_PASSWORD", "wazuh-wui"),
    ("API_ADMIN_USERNAME", "API_ADMIN_PASSWORD", "wazuh"),
)
users = []

for username_variable, password_variable, expected_username in credentials:
    username = os.environ[username_variable]
    password = os.environ[password_variable]

    if username != expected_username:
        sys.exit(
            f"{username_variable} must be {expected_username!r} so the upstream "
            "reserved API account cannot retain its default password"
        )

    if len(password) > 64 or not password_pattern.fullmatch(password):
        sys.exit(
            f"{password_variable} must be 8-64 characters and contain an uppercase "
            "letter, a lowercase letter, a number, and a special character"
        )

    users.append((username, password))

if users[0][1] == users[1][1]:
    sys.exit("API_PASSWORD and API_ADMIN_PASSWORD must be different")

updated_user_ids = []
with AuthenticationManager() as authentication:
    for username, password in users:
        user = authentication.get_user(username)
        if not user:
            sys.exit(f"Wazuh API user {username!r} does not exist")

        if authentication.check_user(username, password):
            continue

        user_id = user["id"]
        if not authentication.update_user(user_id, password):
            sys.exit(f"Failed to update Wazuh API user {username!r}")
        updated_user_ids.append(user_id)

if updated_user_ids:
    invalid_users_tokens(users=updated_user_ids)

with AuthenticationManager() as authentication:
    for username, password in users:
        if not authentication.check_user(username, password):
            sys.exit(f"Failed to verify Wazuh API user {username!r}")
