/** Proposed appearance API v1. Feature-detect before use on stock IINA. */
export type IINAAppearanceSource = 'defaultBlue' | 'systemAccent' | 'textHighlight' | 'custom';

/** Opaque, uppercase, canonical sRGB #RRGGBB strings. */
export interface IINAThemeSnapshot {
  readonly version: 1;
  readonly source: IINAAppearanceSource;
  readonly accentColor: `#${string}`;
  readonly accentTextColor: `#${string}`;
}

/** Available in normal/global plugin scripts and main-frame plugin HTML. */
export interface IINAAppearanceAPI {
  /** Fresh snapshot; no subscription required. HTML CSS tokens update automatically. */
  getTheme(): IINAThemeSnapshot;
  /** Optional updates, with no initial callback. Returns an opaque listener identifier. */
  onChange(callback: (theme: IINAThemeSnapshot) => void): string;
  /** Unknown identifiers are ignored. */
  offChange(id: string): void;
}

/** Additive shape for casting an existing stock-IINA API type. */
export interface IINAWithAppearance {
  readonly appearance?: IINAAppearanceAPI;
}

declare global {
  interface WindowEventMap {
    'iina-theme-changed': CustomEvent<IINAThemeSnapshot>;
  }
}
