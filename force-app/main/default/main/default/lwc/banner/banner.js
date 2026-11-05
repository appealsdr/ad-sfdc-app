import { api, LightningElement } from "lwc";

const BANNER_CONFIG = {
  Base: {
    alertClass: "slds-notify slds-notify_alert",
    assistiveText: "info",
    closeButtonVariant: "bare-inverse",
    defaultIcon: "utility:user",
    iconVariant: "inverse"
  },
  Warning: {
    alertClass: "slds-notify slds-notify_alert slds-alert_warning",
    assistiveText: "warning",
    closeButtonVariant: "bare",
    defaultIcon: "utility:warning",
    iconVariant: "warning"
  },
  Error: {
    alertClass: "slds-notify slds-notify_alert slds-alert_error",
    assistiveText: "error",
    closeButtonVariant: "bare-inverse",
    defaultIcon: "utility:error",
    iconVariant: "inverse"
  }
};

const DEFAULT_TYPE = "Base";

export default class Banner extends LightningElement {
  @api type = DEFAULT_TYPE;
  @api icon;
  @api text = "Banner message";

  isVisible = true;

  get configuration() {
    return BANNER_CONFIG[this.normalizedType];
  }

  get normalizedType() {
    const requestedType = Object.keys(BANNER_CONFIG).find(
      (configuredType) =>
        configuredType.toLowerCase() === this.type?.trim().toLowerCase()
    );
    return requestedType || DEFAULT_TYPE;
  }

  get alertClass() {
    return this.configuration.alertClass;
  }

  get assistiveText() {
    return this.configuration.assistiveText;
  }

  get normalizedIconName() {
    const configuredIcon = this.icon?.trim();
    if (!configuredIcon) {
      return this.configuration.defaultIcon;
    }
    return configuredIcon.includes(":")
      ? configuredIcon
      : `utility:${configuredIcon}`;
  }

  get iconContainerClass() {
    const iconName = this.normalizedIconName.replace(":", "-");
    return `slds-icon_container slds-icon-${iconName} slds-m-right_x-small`;
  }

  get iconTitle() {
    return `${this.normalizedType} notification`;
  }

  get iconVariant() {
    return this.configuration.iconVariant;
  }

  get closeButtonVariant() {
    return this.configuration.closeButtonVariant;
  }

  get closeButtonClass() {
    return this.normalizedType === "Warning"
      ? "banner-close"
      : "banner-close banner-close_inverse";
  }

  handleClose() {
    this.isVisible = false;
    this.dispatchEvent(new CustomEvent("close"));
  }
}