import { Controller } from "@hotwired/stimulus";

// Connects to data-controller="dark-mode"
export default class extends Controller {
  connect() {
    this.apply(localStorage.getItem("theme") || "light");
  }

  toggle() {
    this.apply(document.documentElement.classList.contains("dark") ? "light" : "dark");
  }

  apply(theme) {
    document.documentElement.classList.toggle("dark", theme === "dark");
    localStorage.setItem("theme", theme);
  }
}
