// Renders art/icon.svg to art/icon.png (512x512) with headless Edge (no extra packages).
// Usage: node art/render-icon.js
const { execFileSync } = require("child_process");
const path = require("path");
const fs = require("fs");

const svg = path.join(__dirname, "icon.svg");
const out = path.join(__dirname, "icon.png");
const html = path.join(__dirname, ".icon-render.html");
fs.writeFileSync(
	html,
	`<!doctype html><html><body style="margin:0;overflow:hidden">${fs.readFileSync(svg, "utf8")}</body></html>`
);

const edge = "C:\\Program Files (x86)\\Microsoft\\Edge\\Application\\msedge.exe";
execFileSync(edge, [
	"--headless=new",
	"--disable-gpu",
	"--hide-scrollbars",
	"--force-device-scale-factor=1",
	"--window-size=512,512",
	`--screenshot=${out}`,
	"file:///" + html.replace(/\\/g, "/"),
], { stdio: "inherit" });
fs.unlinkSync(html);
console.log("wrote", out);
