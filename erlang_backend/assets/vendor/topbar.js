// Simple topbar implementation
let progress = 0;
let topbar = document.createElement("div");
topbar.style.cssText = `
  position: fixed;
  top: 0;
  left: 0;
  width: 100%;
  height: 3px;
  background: linear-gradient(to right, #29d, #29d);
  transform: scaleX(0);
  transform-origin: left;
  transition: transform 0.2s ease;
  z-index: 9999;
`;
document.body.appendChild(topbar);

window.topbar = {
  config: function(options) {
    if (options.barColors) {
      topbar.style.background = options.barColors[0];
    }
    if (options.shadowColor) {
      topbar.style.boxShadow = `0 0 10px ${options.shadowColor}`;
    }
  },
  show: function() {
    topbar.style.transform = "scaleX(1)";
  },
  hide: function() {
    topbar.style.transform = "scaleX(0)";
  }
};