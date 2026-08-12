# Configure bounded logs, bridge DNS, and loopback-only default publishing.
"$QVOS_PATH/qvcore/security/docker-policy"

# Start Docker on-demand
sudo systemctl enable docker.socket

# Give this user privileged Docker access
sudo usermod -aG docker "$USER"
