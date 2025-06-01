yay -S --noconfirm docker

# Start Docker automatically
sudo systemctl enable docker
sudo systemctl start docker

# Give this user privileged Docker access
sudo usermod -aG docker ${USER}

# Limit log size to avoid running out of disk
echo '{"log-driver":"json-file","log-opts":{"max-size":"10m","max-file":"5"}}' | sudo tee /etc/docker/daemon.json
