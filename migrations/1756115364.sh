echo "Remove buggy native Zoom client without replacing it with a webapp"

if omarchy-pkg-present zoom; then
  omarchy-pkg-drop zoom
fi
