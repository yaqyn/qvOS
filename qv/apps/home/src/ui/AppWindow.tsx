import type { ReactElement, ReactNode } from "react";
import { Button, Dialog, Heading, Modal, ModalOverlay } from "react-aria-components";
import { CloseIcon } from "../icons";

type AppWindowSize = "compact" | "wide" | "details";

interface AppWindowProps {
  actions?: ReactNode;
  children: ReactNode;
  closeLabel: string;
  eyebrow: string;
  footer?: ReactNode;
  isOpen: boolean;
  onClose: () => void;
  size?: AppWindowSize;
  title: string;
}

export function AppWindow({
  actions,
  children,
  closeLabel,
  eyebrow,
  footer,
  isOpen,
  onClose,
  size = "wide",
  title,
}: AppWindowProps): ReactElement {
  return (
    <ModalOverlay
      className="app-window-overlay"
      isDismissable
      isOpen={isOpen}
      onOpenChange={(open) => {
        if (!open) {
          onClose();
        }
      }}
    >
      <Modal className="app-window" data-size={size}>
        <Dialog className="app-window__dialog">
          <header className="app-window__header">
            <div className="app-window__title">
              <p>{eyebrow}</p>
              <Heading slot="title">{title}</Heading>
            </div>
            <div className="app-window__actions">
              {actions}
              <Button aria-label={closeLabel} className="icon-button" onPress={onClose}>
                <CloseIcon />
              </Button>
            </div>
          </header>
          <div className="app-window__body">{children}</div>
          {footer ? <footer className="app-window__footer">{footer}</footer> : null}
        </Dialog>
      </Modal>
    </ModalOverlay>
  );
}
