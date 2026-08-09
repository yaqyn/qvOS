# Set identification from install inputs
qvos_user_name=${QVOS_USER_NAME:-}
qvos_user_email=${QVOS_USER_EMAIL:-}

if [[ -n ${qvos_user_name//[[:space:]]/} ]]; then
  git config --global user.name "$qvos_user_name"
fi

if [[ -n ${qvos_user_email//[[:space:]]/} ]]; then
  git config --global user.email "$qvos_user_email"
fi
