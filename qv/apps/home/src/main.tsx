import "@fontsource-variable/archivo";
import "@fontsource-variable/jetbrains-mono";
import "@fontsource/michroma/400.css";
import "@fontsource/montserrat/800.css";
import { StrictMode } from "react";
import { createRoot } from "react-dom/client";
import { QvPlayApp } from "./App";
import "./styles.css";

const root = document.getElementById("root");

if (!root) {
  throw new Error("qvPLAY root element is missing");
}

createRoot(root).render(
  <StrictMode>
    <QvPlayApp />
  </StrictMode>,
);
