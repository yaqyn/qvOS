import type { ReactElement, SVGProps } from "react";

type IconProps = SVGProps<SVGSVGElement>;

function IconFrame({ children, ...props }: IconProps): ReactElement {
  return (
    <svg aria-hidden="true" fill="none" viewBox="0 0 24 24" {...props}>
      {children}
    </svg>
  );
}

export function MenuIcon(props: IconProps): ReactElement {
  return (
    <IconFrame {...props}>
      <path d="M4 6h16M4 12h16M4 18h16" stroke="currentColor" strokeLinecap="round" />
    </IconFrame>
  );
}

export function PlayIcon(props: IconProps): ReactElement {
  return (
    <IconFrame {...props}>
      <path d="m8 5 11 7-11 7V5Z" fill="currentColor" />
    </IconFrame>
  );
}

export function EditIcon(props: IconProps): ReactElement {
  return (
    <IconFrame {...props}>
      <path d="m14.6 5.4 4 4M5 19l3.6-.8L19 6.8 17.2 5 5.8 15.4 5 19Z" stroke="currentColor" />
    </IconFrame>
  );
}

export function CloseIcon(props: IconProps): ReactElement {
  return (
    <IconFrame {...props}>
      <path d="m6 6 12 12M18 6 6 18" stroke="currentColor" strokeLinecap="round" />
    </IconFrame>
  );
}

export function RefreshIcon(props: IconProps): ReactElement {
  return (
    <IconFrame {...props}>
      <path
        d="M19 7v4h-4M5 17v-4h4M18 11a7 7 0 0 0-12-3M6 13a7 7 0 0 0 12 3"
        stroke="currentColor"
        strokeLinecap="round"
      />
    </IconFrame>
  );
}

export function SearchIcon(props: IconProps): ReactElement {
  return (
    <IconFrame {...props}>
      <circle cx="10.5" cy="10.5" r="5.5" stroke="currentColor" />
      <path d="m15 15 4 4" stroke="currentColor" strokeLinecap="round" />
    </IconFrame>
  );
}

export function SettingsIcon(props: IconProps): ReactElement {
  return (
    <IconFrame {...props}>
      <circle cx="12" cy="12" r="3" stroke="currentColor" />
      <path
        d="M12 3v2M12 19v2M3 12h2M19 12h2M5.6 5.6 7 7M17 17l1.4 1.4M18.4 5.6 17 7M7 17l-1.4 1.4"
        stroke="currentColor"
        strokeLinecap="round"
      />
    </IconFrame>
  );
}

export function InfoIcon(props: IconProps): ReactElement {
  return (
    <IconFrame {...props}>
      <circle cx="12" cy="12" r="8" stroke="currentColor" />
      <path d="M12 10v6M12 7.5v.1" stroke="currentColor" strokeLinecap="round" />
    </IconFrame>
  );
}

export function ImageIcon(props: IconProps): ReactElement {
  return (
    <IconFrame {...props}>
      <rect x="4" y="5" width="16" height="14" rx="1" stroke="currentColor" />
      <path d="m6 17 4-4 3 3 2-2 3 3M9 10h.01" stroke="currentColor" strokeLinecap="round" />
    </IconFrame>
  );
}
