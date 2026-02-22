import { Controller } from "@hotwired/stimulus";

// Shared global counter for open dialogs (modals and slideovers)
if (!window.__openDialogCount) {
  window.__openDialogCount = 0;
}

// Reset dialog count on page navigation to prevent desync issues
if (!window.__dialogCountResetBound) {
  window.__dialogCountResetBound = true;

  const resetDialogCount = () => {
    const openDialogs = document.querySelectorAll("dialog[open]");
    if (openDialogs.length === 0) {
      window.__openDialogCount = 0;
      document.documentElement.style.removeProperty("--scrollbar-compensation");
      document.body.classList.remove("modal-open", "slideover-open");
    } else {
      window.__openDialogCount = openDialogs.length;
    }
  };

  document.addEventListener("turbo:before-cache", resetDialogCount);
  document.addEventListener("turbo:load", resetDialogCount);
}

export default class extends Controller {
  static targets = ["dialog", "template"];
  static values = {
    open: { type: Boolean, default: false },
    lazyLoad: { type: Boolean, default: false },
    turboFrameSrc: { type: String, default: "" },
    preventDismiss: { type: Boolean, default: false },
    autoFocus: { type: Boolean, default: false },
  };

  connect() {
    this.contentLoaded = false;
    this.isBouncing = false;
    this.isOpen = false;

    this.focusableElements = [];
    this.firstFocusableElement = null;
    this.lastFocusableElement = null;

    this.isDialog = this.dialogTarget.tagName.toLowerCase() === "dialog";

    if (this.isDialog && this.dialogTarget.open) {
      this.isOpen = true;
      this.dialogTarget.close();
      this.cleanupScrollbarCompensation();
    } else if (!this.isDialog && this.dialogTarget.classList.contains("modal-open")) {
      this.isOpen = true;
      this.hideDivModal();
      this.cleanupScrollbarCompensation();
    }

    if (this.openValue) this.open();

    this.boundBeforeCache = this.beforeCache.bind(this);
    this.boundBeforeVisit = this.beforeVisit.bind(this);
    document.addEventListener("turbo:before-cache", this.boundBeforeCache);
    document.addEventListener("turbo:before-visit", this.boundBeforeVisit);

    if (this.isDialog) {
      this.dialogTarget.addEventListener("close", this.handleDialogClose.bind(this));
      this.dialogTarget.addEventListener("cancel", this.handleDialogCancel.bind(this));
    }

    this.boundHandleKeydown = this.handleKeydown.bind(this);
    this.dialogTarget.addEventListener("keydown", this.boundHandleKeydown);

    if (!this.isDialog) {
      this.boundHandleGlobalKeydown = this.handleGlobalKeydown.bind(this);
      document.addEventListener("keydown", this.boundHandleGlobalKeydown);
    }
  }

  disconnect() {
    if (this.isOpen) {
      this.cleanupScrollbarCompensation();
    }

    document.removeEventListener("turbo:before-cache", this.boundBeforeCache);
    document.removeEventListener("turbo:before-visit", this.boundBeforeVisit);

    if (this.isDialog) {
      this.dialogTarget.removeEventListener("close", this.handleDialogClose.bind(this));
      this.dialogTarget.removeEventListener("cancel", this.handleDialogCancel.bind(this));
    }

    this.dialogTarget.removeEventListener("keydown", this.boundHandleKeydown);

    if (!this.isDialog && this.boundHandleGlobalKeydown) {
      document.removeEventListener("keydown", this.boundHandleGlobalKeydown);
    }
  }

  async open() {
    if (this.isOpen) return;

    if (this.lazyLoadValue && !this.contentLoaded) {
      await this.#loadTemplateContent();
      this.contentLoaded = true;
    }

    window.__openDialogCount++;
    this.isOpen = true;

    if (window.__openDialogCount === 1) {
      const scrollbarWidth = this.getScrollbarWidth();
      if (scrollbarWidth > 0) {
        document.documentElement.style.setProperty("--scrollbar-compensation", `${scrollbarWidth}px`);
        document.body.classList.add("modal-open");
      }
    }

    if (this.isDialog) {
      this.dialogTarget.showModal();
    } else {
      this.showDivModal();
    }

    this.setupFocusTrapping();

    if (this.isTouchDevice()) {
      const focusedElement = this.dialogTarget.querySelector(":focus");
      if (focusedElement && !focusedElement.hasAttribute("autofocus")) {
        focusedElement.blur();
      }
    }
  }

  close() {
    if (!this.isOpen) return;

    this.dialogTarget.setAttribute("closing", "");

    Promise.all(this.dialogTarget.getAnimations().map((animation) => animation.finished)).then(() => {
      this.dialogTarget.removeAttribute("closing");

      if (this.isDialog) {
        this.dialogTarget.close();
      } else {
        this.hideDivModal();
        setTimeout(() => {
          this.handleDialogClose();
        }, 200);
      }

      this.isBouncing = false;
    });
  }

  backdropClose(event) {
    let isBackdropClick = false;

    if (this.isDialog) {
      if (event.target.nodeName === "DIALOG") {
        const rect = this.dialogTarget.getBoundingClientRect();
        isBackdropClick =
          event.clientX < rect.left ||
          event.clientX > rect.right ||
          event.clientY < rect.top ||
          event.clientY > rect.bottom;
      }
    } else {
      isBackdropClick = event.target === this.dialogTarget || event.target.hasAttribute("data-modal-backdrop");
    }

    if (isBackdropClick) {
      event.stopPropagation();
      if (this.preventDismissValue) {
        this.bounce();
      } else {
        this.close();
      }
    }
  }

  show() {
    this.dialogTarget.show();
  }

  hide() {
    this.close();
  }

  beforeCache() {
    if (this.isOpen) {
      this.dialogTarget.removeAttribute("closing");
      if (this.isDialog) {
        this.dialogTarget.close();
      } else {
        this.hideDivModal();
      }
      this.cleanupScrollbarCompensation();
    }
  }

  beforeVisit() {
    if (this.isOpen) {
      this.dialogTarget.removeAttribute("closing");
      if (this.isDialog) {
        this.dialogTarget.close();
      } else {
        this.hideDivModal();
      }
      this.cleanupScrollbarCompensation();
    }
  }

  getScrollbarWidth() {
    const outer = document.createElement("div");
    outer.style.visibility = "hidden";
    outer.style.overflow = "scroll";
    outer.style.msOverflowStyle = "scrollbar";
    document.body.appendChild(outer);

    const inner = document.createElement("div");
    outer.appendChild(inner);

    const scrollbarWidth = outer.offsetWidth - inner.offsetWidth;
    outer.parentNode.removeChild(outer);

    return scrollbarWidth;
  }

  async #loadTemplateContent() {
    const container = this.dialogTarget.querySelector("[data-modal-content]") || this.dialogTarget;

    if (this.turboFrameSrcValue) {
      let turboFrame = container.querySelector("turbo-frame");

      if (!turboFrame) {
        turboFrame = document.createElement("turbo-frame");
        turboFrame.id = "modal-lazy-content";
        container.innerHTML = "";
        container.appendChild(turboFrame);
      }

      turboFrame.src = this.turboFrameSrcValue;

      return new Promise((resolve) => {
        const handleLoad = () => {
          turboFrame.removeEventListener("turbo:frame-load", handleLoad);
          resolve();
        };

        turboFrame.addEventListener("turbo:frame-load", handleLoad);

        setTimeout(() => {
          turboFrame.removeEventListener("turbo:frame-load", handleLoad);
          resolve();
        }, 5000);
      });
    } else if (this.hasTemplateTarget) {
      const templateContent = this.templateTarget.content.cloneNode(true);
      container.innerHTML = "";
      container.appendChild(templateContent);
    }
  }

  handleDialogClose() {
    if (this.isOpen) {
      this.cleanupScrollbarCompensation();
    }
    this.dialogTarget.removeAttribute("closing");
    this.isBouncing = false;
  }

  cleanupScrollbarCompensation() {
    if (!this.isOpen) return;

    window.__openDialogCount = Math.max(0, window.__openDialogCount - 1);
    this.isOpen = false;

    if (window.__openDialogCount === 0) {
      document.documentElement.style.removeProperty("--scrollbar-compensation");
      document.body.classList.remove("modal-open", "slideover-open");
    }
  }

  handleKeydown(event) {
    if (event.key === "Escape" && this.preventDismissValue) {
      event.preventDefault();
      event.stopPropagation();
      event.stopImmediatePropagation();
      this.bounce();
      return false;
    }

    if (event.key === "Tab") {
      this.handleTabKey(event);
    }
  }

  handleDialogCancel(event) {
    if (this.preventDismissValue) {
      event.preventDefault();
      event.stopPropagation();
      this.bounce();
      return false;
    }
  }

  bounce() {
    if (this.isBouncing) return;

    this.isBouncing = true;

    this.dialogTarget.classList.add("scale-105", "transition-transform");

    setTimeout(() => {
      this.dialogTarget.classList.remove("scale-105");
      this.dialogTarget.classList.add("scale-100");

      setTimeout(() => {
        this.dialogTarget.classList.remove("scale-100", "transition-transform");

        setTimeout(() => {
          this.isBouncing = false;
        }, 200);
      }, 150);
    }, 150);
  }

  isTouchDevice() {
    return "ontouchstart" in window || navigator.maxTouchPoints > 0 || navigator.msMaxTouchPoints > 0;
  }

  setupFocusTrapping() {
    this.updateFocusableElements();

    const autofocusElement = this.dialogTarget.querySelector("[autofocus]");
    if (autofocusElement) {
      autofocusElement.focus();
    } else if (this.autoFocusValue && this.firstFocusableElement && !this.isTouchDevice()) {
      this.firstFocusableElement.focus();
    }
  }

  updateFocusableElements() {
    const focusableSelector = [
      "a[href]",
      "area[href]",
      'input:not([disabled]):not([tabindex="-1"])',
      'button:not([disabled]):not([tabindex="-1"])',
      'textarea:not([disabled]):not([tabindex="-1"])',
      'select:not([disabled]):not([tabindex="-1"])',
      "details",
      '[tabindex]:not([tabindex="-1"])',
      '[contenteditable]:not([contenteditable="false"])',
    ].join(",");

    this.focusableElements = Array.from(this.dialogTarget.querySelectorAll(focusableSelector)).filter((element) => {
      return (
        element.offsetWidth > 0 &&
        element.offsetHeight > 0 &&
        getComputedStyle(element).display !== "none" &&
        getComputedStyle(element).visibility !== "hidden"
      );
    });

    this.firstFocusableElement = this.focusableElements[0] || null;
    this.lastFocusableElement = this.focusableElements[this.focusableElements.length - 1] || null;
  }

  handleTabKey(event) {
    this.updateFocusableElements();

    if (this.focusableElements.length === 0) {
      event.preventDefault();
      return;
    }

    if (this.focusableElements.length === 1) {
      event.preventDefault();
      this.firstFocusableElement.focus();
      return;
    }

    if (event.shiftKey) {
      if (document.activeElement === this.firstFocusableElement) {
        event.preventDefault();
        this.lastFocusableElement.focus();
      }
    } else {
      if (document.activeElement === this.lastFocusableElement) {
        event.preventDefault();
        this.firstFocusableElement.focus();
      }
    }
  }

  showDivModal() {
    this.dialogTarget.classList.add("modal-open");
    this.dialogTarget.style.display = "flex";
    this.dialogTarget.offsetHeight;
    this.dialogTarget.classList.add("modal-visible");
  }

  hideDivModal() {
    this.dialogTarget.classList.remove("modal-visible");
    setTimeout(() => {
      this.dialogTarget.style.display = "none";
      this.dialogTarget.classList.remove("modal-open");
    }, 200);
  }

  handleGlobalKeydown(event) {
    if (!this.isOpen) return;

    const allOpenModals = document.querySelectorAll('[data-controller*="modal"] [data-modal-target="dialog"].modal-open');
    const isTopmost = allOpenModals.length === 0 || allOpenModals[allOpenModals.length - 1] === this.dialogTarget;

    if (event.key === "Escape" && isTopmost) {
      if (this.preventDismissValue) {
        event.preventDefault();
        event.stopPropagation();
        this.bounce();
      } else {
        event.preventDefault();
        this.close();
      }
    }
  }
}
