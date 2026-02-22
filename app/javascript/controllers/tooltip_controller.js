import { Controller } from "@hotwired/stimulus";
import { computePosition, offset, flip, shift, arrow, autoUpdate } from "@floating-ui/dom";

class TooltipGlobalState {
  constructor() {
    this.visibleCount = 0;
    this.isFastMode = false;
    this.resetTimeout = null;
    this.fastModeResetDelay = 100;
    this.visibleTooltips = new Set();
    this.closingTooltips = new Set();
  }

  onTooltipShow(tooltipController) {
    this.visibleTooltips.add(tooltipController);
    this.closingTooltips.delete(tooltipController);
    this.visibleCount = this.visibleTooltips.size;
    if (this.visibleCount > 0 && !this.isFastMode) {
      this.isFastMode = true;
    }
    this.clearResetTimeout();
  }

  onTooltipStartHide(tooltipController) {
    this.visibleTooltips.delete(tooltipController);
    this.visibleCount = this.visibleTooltips.size;
  }

  onTooltipClosing(tooltipController) {
    this.closingTooltips.add(tooltipController);
  }

  onTooltipClosed(tooltipController) {
    this.closingTooltips.delete(tooltipController);

    if (this.visibleCount === 0 && this.closingTooltips.size === 0) {
      this.startResetTimeout();
    }
  }

  hideAllTooltipsInstantly(exceptController) {
    const visibleToHide = [...this.visibleTooltips].filter((controller) => controller !== exceptController);
    visibleToHide.forEach((controller) => {
      controller._hideTooltip(true);
    });

    const closingToHide = [...this.closingTooltips].filter((controller) => controller !== exceptController);
    closingToHide.forEach((controller) => {
      controller._finishClosingAnimation();
    });
  }

  isInFastMode() {
    return this.isFastMode;
  }

  startResetTimeout() {
    this.clearResetTimeout();
    this.resetTimeout = setTimeout(() => {
      this.isFastMode = false;
    }, this.fastModeResetDelay);
  }

  clearResetTimeout() {
    if (this.resetTimeout) {
      clearTimeout(this.resetTimeout);
      this.resetTimeout = null;
    }
  }
}

const tooltipGlobalState = new TooltipGlobalState();

export default class extends Controller {
  static values = {
    placement: { type: String, default: "top" },
    offset: { type: Number, default: 8 },
    maxWidth: { type: Number, default: 200 },
    delay: { type: Number, default: 0 },
    size: { type: String, default: "regular" },
    animation: { type: String, default: "fade" },
    trigger: { type: String, default: "auto" },
  };

  _hasAnimationType(type) {
    return this.animationValue.split(" ").includes(type);
  }

  connect() {
    this.tooltipContent = this.element.getAttribute("data-tooltip-content") || "";
    this.showArrow = this.element.getAttribute("data-tooltip-arrow") !== "false";
    this.showTimeoutId = null;
    this.hideTimeoutId = null;
    this.isVisible = false;

    if (!this.tooltipContent) {
      console.warn("Tooltip initialized without data-tooltip-content", this.element);
      return;
    }

    this.tooltipElement = document.createElement("div");
    this.tooltipElement.className =
      "tooltip-content pointer-events-none wrap-break-word shadow-sm border rounded-lg border-white/10 absolute bg-[#333333] text-white py-1 px-2 z-[1000]";

    const sizeClasses = {
      small: "text-xs",
      regular: "text-sm",
      large: "text-base",
    };
    const sizeClass = sizeClasses[this.sizeValue] || sizeClasses.regular;
    this.tooltipElement.classList.add(sizeClass);

    this.tooltipElement.classList.add("opacity-0");
    this.tooltipElement.style.visibility = "hidden";

    const hasFade = this._hasAnimationType("fade");
    const hasOrigin = this._hasAnimationType("origin");

    if (hasFade && hasOrigin) {
      this.tooltipElement.style.transition = "opacity 150ms ease-out, transform 150ms ease-out";
      this.tooltipElement.style.transform = "scale(0.95)";
    } else if (hasOrigin) {
      this.tooltipElement.style.transition = "transform 150ms ease-out";
      this.tooltipElement.style.transform = "scale(0.95)";
    } else if (hasFade) {
      this.tooltipElement.style.transition = "opacity 150ms ease-out";
    }

    this.tooltipElement.innerHTML = this.tooltipContent;
    this.tooltipElement.style.maxWidth = `${this.maxWidthValue}px`;

    if (this.showArrow) {
      this.arrowContainer = document.createElement("div");
      this.arrowContainer.className = "absolute z-[1000]";

      this.arrowElement = document.createElement("div");
      this.arrowElement.className = "tooltip-arrow-element bg-[#333333] w-2 h-2 border-white/10";
      this.arrowElement.style.transform = "rotate(45deg)";

      this.arrowContainer.appendChild(this.arrowElement);
      this.tooltipElement.appendChild(this.arrowContainer);
    }

    this.showTooltipBound = this._showTooltip.bind(this);
    this.hideTooltipBound = this._hideTooltip.bind(this);
    this.clickHideTooltipBound = this._handleClick.bind(this);
    this.clickToggleTooltipBound = this._handleClickToggle.bind(this);
    this.clickOutsideBound = this._handleClickOutside.bind(this);

    let triggerValue = this.triggerValue;
    if (triggerValue === "auto") {
      const isTouchDevice = "ontouchstart" in window || navigator.maxTouchPoints > 0;
      triggerValue = isTouchDevice ? "click" : "mouseenter focus";
    }

    const triggers = triggerValue.split(" ");
    this.hasMouseEnterTrigger = triggers.includes("mouseenter");
    this.hasClickTrigger = triggers.includes("click");

    triggers.forEach((event_type) => {
      if (event_type === "mouseenter") {
        this.element.addEventListener("mouseenter", this.showTooltipBound);
        this.element.addEventListener("mouseleave", this.hideTooltipBound);
      }
      if (event_type === "focus") {
        this.element.addEventListener("focus", this.showTooltipBound);
        this.element.addEventListener("blur", this.hideTooltipBound);
      }
      if (event_type === "click") {
        this.element.addEventListener("click", this.clickToggleTooltipBound);
      }
    });

    if (this.hasMouseEnterTrigger && !this.hasClickTrigger) {
      this.element.addEventListener("click", this.clickHideTooltipBound);
    }

    this.cleanupAutoUpdate = null;
    this.intersectionObserver = null;
  }

  disconnect() {
    clearTimeout(this.showTimeoutId);
    clearTimeout(this.hideTimeoutId);

    if (this.isVisible) {
      tooltipGlobalState.onTooltipStartHide(this);
      this.isVisible = false;
    }
    tooltipGlobalState.onTooltipClosed(this);

    let triggerValue = this.triggerValue;
    if (triggerValue === "auto") {
      const isTouchDevice = "ontouchstart" in window || navigator.maxTouchPoints > 0;
      triggerValue = isTouchDevice ? "click" : "mouseenter focus";
    }

    triggerValue.split(" ").forEach((event_type) => {
      if (event_type === "mouseenter") {
        this.element.removeEventListener("mouseenter", this.showTooltipBound);
        this.element.removeEventListener("mouseleave", this.hideTooltipBound);
      }
      if (event_type === "focus") {
        this.element.removeEventListener("focus", this.showTooltipBound);
        this.element.removeEventListener("blur", this.hideTooltipBound);
      }
      if (event_type === "click") {
        this.element.removeEventListener("click", this.clickToggleTooltipBound);
      }
    });

    if (this.hasMouseEnterTrigger && !this.hasClickTrigger) {
      this.element.removeEventListener("click", this.clickHideTooltipBound);
    }

    this._cleanupObservers();

    if (this.tooltipElement && this.tooltipElement.parentElement) {
      this.tooltipElement.remove();
    }
  }

  async _updatePositionAndArrow() {
    if (!this.element || !this.tooltipElement) return;

    const placements = this.placementValue.split(/[\s,]+/).filter(Boolean);
    const primaryPlacement = placements[0] || "top";
    const fallbackPlacements = placements.slice(1);

    const middleware = [
      offset(this.offsetValue),
      flip({
        fallbackPlacements: fallbackPlacements.length > 0 ? fallbackPlacements : undefined,
      }),
      shift({ padding: 5 }),
    ];
    if (this.showArrow && this.arrowContainer) {
      middleware.push(arrow({ element: this.arrowContainer, padding: 2 }));
    }

    const { x, y, placement, middlewareData } = await computePosition(this.element, this.tooltipElement, {
      placement: primaryPlacement,
      middleware: middleware,
    });

    Object.assign(this.tooltipElement.style, {
      left: `${x}px`,
      top: `${y}px`,
    });

    if (this._hasAnimationType("origin")) {
      const basePlacement = placement.split("-")[0];
      this.tooltipElement.classList.remove("origin-top", "origin-bottom", "origin-left", "origin-right");
      if (basePlacement === "top") {
        this.tooltipElement.classList.add("origin-bottom");
      } else if (basePlacement === "bottom") {
        this.tooltipElement.classList.add("origin-top");
      } else if (basePlacement === "left") {
        this.tooltipElement.classList.add("origin-right");
      } else if (basePlacement === "right") {
        this.tooltipElement.classList.add("origin-left");
      }
    }

    if (this.showArrow && this.arrowContainer && this.arrowElement && middlewareData.arrow) {
      const { x: arrowX, y: arrowY } = middlewareData.arrow;
      const basePlacement = placement.split("-")[0];
      const staticSide = {
        top: "bottom",
        right: "left",
        bottom: "top",
        left: "right",
      }[basePlacement];

      this.arrowContainer.classList.remove("px-1", "py-1");
      if (basePlacement === "top" || basePlacement === "bottom") {
        this.arrowContainer.classList.add("px-1");
      } else {
        this.arrowContainer.classList.add("py-1");
      }

      Object.assign(this.arrowContainer.style, {
        left: arrowX != null ? `${arrowX}px` : "",
        top: arrowY != null ? `${arrowY}px` : "",
        right: "",
        bottom: "",
        [staticSide]: "-0.275rem",
      });

      this.arrowElement.classList.remove("border-t", "border-r", "border-b", "border-l");

      if (staticSide === "bottom") {
        this.arrowElement.classList.add("border-b", "border-r");
      } else if (staticSide === "top") {
        this.arrowElement.classList.add("border-t", "border-l");
      } else if (staticSide === "left") {
        this.arrowElement.classList.add("border-b", "border-l");
      } else if (staticSide === "right") {
        this.arrowElement.classList.add("border-t", "border-r");
      }
    }
  }

  async _showTooltip() {
    if (!this.tooltipElement) return;

    clearTimeout(this.hideTimeoutId);
    clearTimeout(this.showTimeoutId);

    tooltipGlobalState.hideAllTooltipsInstantly(this);

    const isFastMode = tooltipGlobalState.isInFastMode();
    const effectiveDelay = isFastMode ? 0 : this.delayValue;

    this.showTimeoutId = setTimeout(async () => {
      const currentAppendTarget = this.element.closest("dialog[open]") || document.body;
      if (this.tooltipElement.parentElement !== currentAppendTarget) {
        currentAppendTarget.appendChild(this.tooltipElement);
      }

      await this._updatePositionAndArrow();

      this.tooltipElement.style.visibility = "visible";

      const applyVisibleState = () => {
        this.tooltipElement.classList.remove("opacity-0");
        this.tooltipElement.classList.add("opacity-100");

        if (this._hasAnimationType("origin")) {
          this.tooltipElement.style.transform = "scale(1)";
        }
      };

      if (isFastMode) {
        this.tooltipElement.setAttribute("data-instant", "");
        this._withoutTransition(applyVisibleState);
        requestAnimationFrame(() => {
          if (this.tooltipElement) {
            this.tooltipElement.removeAttribute("data-instant");
          }
        });
      } else {
        this.tooltipElement.removeAttribute("data-instant");
        requestAnimationFrame(applyVisibleState);
      }

      if (this.cleanupAutoUpdate) {
        this.cleanupAutoUpdate();
      }
      this.cleanupAutoUpdate = autoUpdate(
        this.element,
        this.tooltipElement,
        async () => {
          const appendTargetRecurring = this.element.closest("dialog[open]") || document.body;
          if (this.tooltipElement.parentElement !== appendTargetRecurring) {
            appendTargetRecurring.appendChild(this.tooltipElement);
          }
          await this._updatePositionAndArrow();
        },
        { animationFrame: true }
      );

      if (this.intersectionObserver) {
        this.intersectionObserver.disconnect();
      }
      this.intersectionObserver = new IntersectionObserver(
        (entries) => {
          entries.forEach((entry) => {
            if (!entry.isIntersecting) {
              this._hideTooltip();
            }
          });
        },
        { threshold: 0 }
      );
      this.intersectionObserver.observe(this.element);

      if (!this.isVisible) {
        this.isVisible = true;
        tooltipGlobalState.onTooltipShow(this);
      }

      if (this.hasClickTrigger) {
        setTimeout(() => {
          document.addEventListener("click", this.clickOutsideBound);
        }, 0);
      }
    }, effectiveDelay);
  }

  _handleClick() {
    this._hideTooltip();
  }

  _handleClickToggle(event) {
    if (this.isVisible) {
      this._hideTooltip();
    } else {
      this._showTooltip();
    }

    const isInteractive = this.element.matches("button, a, [role='button'], input, select, textarea");
    if (!isInteractive) {
      event.stopPropagation();
    }
  }

  _handleClickOutside(event) {
    if (!this.element.contains(event.target)) {
      this._hideTooltip();
    }
  }

  _withoutTransition(callback) {
    if (!this.tooltipElement) return;
    this.tooltipElement.setAttribute("data-instant", "");
    this.tooltipElement.offsetHeight;
    callback();
  }

  _applyHiddenState() {
    if (!this.tooltipElement) return;

    this.tooltipElement.classList.remove("opacity-100");
    this.tooltipElement.classList.add("opacity-0");
    if (this._hasAnimationType("origin")) {
      this.tooltipElement.style.transform = "scale(0.95)";
    }
    this.tooltipElement.style.visibility = "hidden";
  }

  _cleanupObservers() {
    if (this.cleanupAutoUpdate) {
      this.cleanupAutoUpdate();
      this.cleanupAutoUpdate = null;
    }
    if (this.intersectionObserver) {
      this.intersectionObserver.disconnect();
      this.intersectionObserver = null;
    }
    if (this.hasClickTrigger) {
      document.removeEventListener("click", this.clickOutsideBound);
    }
  }

  _hideTooltip(isInstantHide = false) {
    clearTimeout(this.showTimeoutId);
    clearTimeout(this.hideTimeoutId);

    if (!this.tooltipElement) return;

    if (this.isVisible) {
      this.isVisible = false;
      tooltipGlobalState.onTooltipStartHide(this);
    }

    this._cleanupObservers();

    if (isInstantHide) {
      this.tooltipElement.setAttribute("data-instant", "");
      this._withoutTransition(() => {
        this._applyHiddenState();
      });
      tooltipGlobalState.onTooltipClosed(this);
      return;
    }

    this.tooltipElement.removeAttribute("data-instant");

    tooltipGlobalState.onTooltipClosing(this);

    const needsAnimation = this._hasAnimationType("fade") || this._hasAnimationType("origin");

    if (needsAnimation || this.animationValue === "none") {
      this.tooltipElement.classList.remove("opacity-100");
      this.tooltipElement.classList.add("opacity-0");
      if (this._hasAnimationType("origin")) {
        this.tooltipElement.style.transform = "scale(0.95)";
      }
    }

    const animationDelay = needsAnimation ? 150 : 0;

    this.hideTimeoutId = setTimeout(() => {
      if (this.tooltipElement) {
        this.tooltipElement.style.visibility = "hidden";
      }
      tooltipGlobalState.onTooltipClosed(this);
    }, animationDelay);
  }

  _finishClosingAnimation() {
    clearTimeout(this.hideTimeoutId);

    if (!this.tooltipElement) return;

    this.tooltipElement.setAttribute("data-instant", "");
    this._withoutTransition(() => {
      this._applyHiddenState();
    });

    tooltipGlobalState.onTooltipClosed(this);
  }
}
