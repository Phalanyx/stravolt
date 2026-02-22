import { Controller } from "@hotwired/stimulus";
import "number-flow";
import { continuous } from "number-flow";

export default class extends Controller {
  static values = {
    start: { type: Number, default: 0 },
    end: { type: Number, default: 0 },
    duration: { type: Number, default: 700 },
    trigger: { type: String, default: "viewport" },
    prefix: String,
    suffix: String,
    formatOptions: String,
    trend: Number,
    realtime: { type: Boolean, default: false },
    updateInterval: { type: Number, default: 1000 },
    continuous: { type: Boolean, default: true },
    spinEasing: { type: String, default: "ease-in-out" },
    transformEasing: { type: String, default: "ease-in-out" },
    opacityEasing: { type: String, default: "ease-out" },
  };

  connect() {
    this.element.innerHTML = "<number-flow></number-flow>";
    this.flow = this.element.querySelector("number-flow");
    this.currentValue = this.startValue || 0;

    if (this.hasPrefixValue) this.flow.numberPrefix = this.prefixValue;
    if (this.hasSuffixValue) this.flow.numberSuffix = this.suffixValue;

    if (this.hasFormatOptionsValue) {
      try {
        this.flow.format = JSON.parse(this.formatOptionsValue);
      } catch (e) {
        console.error("Error parsing formatOptions JSON:", e);
      }
    }

    if (this.hasTrendValue) {
      this.flow.trend = this.trendValue;
    } else {
      this.flow.trend = Math.sign(this.endValue - this.currentValue) || 1;
    }

    if (!this.realtimeValue) {
      this.flow.update(this.currentValue);
    }

    this.configureTimings();

    if (this.continuousValue) {
      this.flow.plugins = [continuous];
    }

    this.handleTrigger();
  }

  configureTimings() {
    const animationDuration = this.durationValue || 700;

    this.flow.spinTiming = {
      duration: animationDuration,
      easing: this.spinEasingValue,
    };

    this.flow.transformTiming = {
      duration: animationDuration,
      easing: this.transformEasingValue,
    };

    this.flow.opacityTiming = {
      duration: 350,
      easing: this.opacityEasingValue,
    };
  }

  handleTrigger() {
    const trigger = this.triggerValue || "viewport";

    switch (trigger) {
      case "load":
        this.startAnimation();
        break;
      case "viewport":
        this.observeViewport();
        break;
      case "manual":
        break;
      default:
        this.startAnimation();
        break;
    }
  }

  startAnimation() {
    if (this.realtimeValue) {
      this.flow.update(this.currentValue);
      this.timerInterval = setInterval(() => {
        this.tick();
      }, this.updateIntervalValue);
    } else {
      this.animateToEnd();
    }
  }

  tick() {
    const step = Math.sign(this.endValue - this.startValue) || (this.startValue > this.endValue ? -1 : 1);
    this.currentValue += step;
    this.flow.update(this.currentValue);

    if ((step > 0 && this.currentValue >= this.endValue) || (step < 0 && this.currentValue <= this.endValue)) {
      clearInterval(this.timerInterval);
    }
  }

  animateToEnd() {
    if (!this.flow) return;

    if (!this.realtimeValue && this.hasDurationValue) {
      const overallDuration = this.durationValue || 2000;

      this.flow.spinTiming = {
        duration: overallDuration,
        easing: this.spinEasingValue,
      };

      this.flow.transformTiming = {
        duration: overallDuration,
        easing: this.transformEasingValue,
      };

      this.flow.opacityTiming = {
        duration: 350,
        easing: this.opacityEasingValue,
      };
    }
    this.flow.update(this.endValue);
  }

  observeViewport() {
    this.observer = new IntersectionObserver((entries) => {
      entries.forEach((entry) => {
        if (entry.isIntersecting) {
          this.startAnimation();
          this.observer.unobserve(this.element);
        }
      });
    });

    this.observer.observe(this.element);
  }

  triggerAnimation() {
    this.currentValue = this.startValue || 0;
    this.flow.update(this.currentValue);

    setTimeout(() => {
      this.startAnimation();
    }, 50);
  }

  disconnect() {
    if (this.timerInterval) {
      clearInterval(this.timerInterval);
    }
    if (this.observer) {
      this.observer.disconnect();
    }
  }
}
